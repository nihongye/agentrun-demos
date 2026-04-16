/**
 * index.ts — Code Execution MCP Server
 *
 * 基于 streamable HTTP 协议的 MCP 服务，提供多语言代码执行能力。
 * 支持语言：python | javascript | typescript | java | shell
 *
 * 调试入口：编辑项目根目录的 hooks.js，修改 pre_hook / post_hook 函数，
 *            保存后重启服务即可生效，无需重新构建。
 */

import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import {
  StreamableHTTPServerTransport,
  EventStore,
} from "@modelcontextprotocol/sdk/server/streamableHttp.js";
import express, { Request, Response } from "express";
import cors from "cors";
import { randomUUID } from "node:crypto";
import { fileURLToPath } from "node:url";
import { dirname, resolve } from "node:path";
import { z } from "zod";
import { executeCode, type Language, type ExecutionContext, type ExecutionResult } from "./executor.js";

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

// --------------------------------------------------------------------------
// Hook 加载
// --------------------------------------------------------------------------

interface Hooks {
  pre_hook: (ctx: ExecutionContext) => Promise<ExecutionContext>;
  post_hook: (ctx: ExecutionContext, result: ExecutionResult) => Promise<ExecutionResult>;
}

// hooks.js 位于项目根目录（dist/ 的上一级）
const HOOKS_PATH = resolve(__dirname, "../hooks.js");

async function loadHooks(): Promise<Hooks> {
  try {
    // 每次加载时添加时间戳参数以绕过 ESM 模块缓存，支持热更新
    const mod = await import(`${HOOKS_PATH}?t=${Date.now()}`);
    return {
      pre_hook: mod.pre_hook ?? (async (ctx: ExecutionContext) => ctx),
      post_hook: mod.post_hook ?? (async (_: ExecutionContext, r: ExecutionResult) => r),
    };
  } catch (err) {
    console.error("[warn] Failed to load hooks.js, using defaults:", err);
    return {
      pre_hook: async (ctx) => ctx,
      post_hook: async (_, r) => r,
    };
  }
}

// --------------------------------------------------------------------------
// MCP Server 工厂
// --------------------------------------------------------------------------

const LANGUAGES: [Language, ...Language[]] = [
  "python",
  "javascript",
  "typescript",
  "java",
  "shell",
];

const DEFAULT_TIMEOUT = Number(process.env.EXECUTION_TIMEOUT ?? 30);
const MAX_TIMEOUT = Number(process.env.MAX_EXECUTION_TIMEOUT ?? 120);

function createMcpServer(): { server: McpServer; cleanup: () => void } {
  const server = new McpServer({
    name: "code-execution-mcp",
    version: "1.0.0",
  });

  server.registerTool(
    "execute_code",
    {
      title: "Execute Code",
      description:
        "Execute a code snippet in the specified programming language and return the output. " +
        "Supported languages: python, javascript, typescript, java, shell. " +
        "For Java, define a public class named 'Main' with a 'public static void main(String[] args)' method. " +
        "Returns stdout, stderr, exit code, and execution time.",
      inputSchema: {
        language: z
          .enum(LANGUAGES)
          .describe("Programming language to execute the code in"),
        code: z.string().min(1).describe("Source code to execute"),
        timeout: z
          .number()
          .int()
          .min(1)
          .max(MAX_TIMEOUT)
          .optional()
          .default(DEFAULT_TIMEOUT)
          .describe(`Execution timeout in seconds (default: ${DEFAULT_TIMEOUT}, max: ${MAX_TIMEOUT})`),
      },
    },
    async (args) => {
      const ctx: ExecutionContext = {
        language: args.language as Language,
        code: args.code,
        timeout: args.timeout ?? DEFAULT_TIMEOUT,
      };

      // 加载 hooks（每次调用时重新加载，支持实时修改 hooks.js）
      const hooks = await loadHooks();

      let finalCtx: ExecutionContext;
      try {
        finalCtx = await hooks.pre_hook(ctx);
      } catch (err) {
        const msg = err instanceof Error ? err.message : String(err);
        return {
          content: [
            {
              type: "text" as const,
              text: `[pre_hook error] ${msg}`,
            },
          ],
          isError: true,
        };
      }

      let result: ExecutionResult;
      try {
        result = await executeCode(finalCtx);
      } catch (err) {
        const msg = err instanceof Error ? err.message : String(err);
        return {
          content: [{ type: "text" as const, text: `[executor error] ${msg}` }],
          isError: true,
        };
      }

      result = await hooks.post_hook(finalCtx, result);

      const success = result.exitCode === 0;
      const parts: string[] = [];

      if (result.stdout) {
        parts.push(`=== stdout ===\n${result.stdout}`);
      }
      if (result.stderr) {
        parts.push(`=== stderr ===\n${result.stderr}`);
      }
      parts.push(
        `=== summary ===\nexit_code: ${result.exitCode}\nexecution_time: ${result.executionTimeMs}ms`
      );

      return {
        content: [{ type: "text" as const, text: parts.join("\n\n") }],
        isError: !success,
      };
    }
  );

  return {
    server,
    cleanup: () => {
      // 预留清理逻辑（如每个 session 的资源回收）
    },
  };
}

// --------------------------------------------------------------------------
// In-Memory Event Store（支持 SSE 断线重连）
// --------------------------------------------------------------------------

class InMemoryEventStore implements EventStore {
  private events: Map<string, { streamId: string; message: unknown }> = new Map();

  async storeEvent(streamId: string, message: unknown): Promise<string> {
    const eventId = randomUUID();
    this.events.set(eventId, { streamId, message });
    return eventId;
  }

  async replayEventsAfter(
    lastEventId: string,
    { send }: { send: (eventId: string, message: unknown) => Promise<void> }
  ): Promise<string> {
    const entries = Array.from(this.events.entries());
    const startIndex = entries.findIndex(([id]) => id === lastEventId);
    if (startIndex === -1) return lastEventId;

    let lastId = lastEventId;
    for (let i = startIndex + 1; i < entries.length; i++) {
      const [eventId, { message }] = entries[i];
      await send(eventId, message);
      lastId = eventId;
    }
    return lastId;
  }
}

// --------------------------------------------------------------------------
// Express + Streamable HTTP 路由
// --------------------------------------------------------------------------

const app = express();
app.use(express.json());
app.use(
  cors({
    origin: "*",
    methods: "GET,POST,DELETE",
    preflightContinue: false,
    optionsSuccessStatus: 204,
    exposedHeaders: ["mcp-session-id", "last-event-id", "mcp-protocol-version"],
  })
);

// sessionId → transport 映射表
const transports: Map<string, StreamableHTTPServerTransport> = new Map();

// --------------------------------------------------------------------------
// 请求处理函数（复用于 / 和 /mcp 两个路径）
// --------------------------------------------------------------------------

async function handlePost(req: Request, res: Response): Promise<void> {
  try {
    const sessionId = req.headers["mcp-session-id"] as string | undefined;

    if (sessionId && transports.has(sessionId)) {
      await transports.get(sessionId)!.handleRequest(req, res, req.body);
      return;
    }

    if (!sessionId) {
      const { server, cleanup } = createMcpServer();
      const eventStore = new InMemoryEventStore();
      const transport = new StreamableHTTPServerTransport({
        sessionIdGenerator: () => randomUUID(),
        eventStore,
        onsessioninitialized: (sid: string) => {
          console.log(`[session] initialized: ${sid}`);
          transports.set(sid, transport);
        },
      });

      server.server.onclose = async () => {
        const sid = transport.sessionId;
        if (sid && transports.has(sid)) {
          console.log(`[session] closed: ${sid}`);
          transports.delete(sid);
          cleanup();
        }
      };

      await server.connect(transport);
      await transport.handleRequest(req, res, req.body);
      return;
    }

    res.status(400).json({
      jsonrpc: "2.0",
      error: { code: -32000, message: "Bad Request: No valid session ID provided" },
      id: req.body?.id,
    });
  } catch (err) {
    console.error("[error] POST:", err);
    if (!res.headersSent) {
      res.status(500).json({
        jsonrpc: "2.0",
        error: { code: -32603, message: "Internal server error" },
        id: req.body?.id,
      });
    }
  }
}

async function handleGet(req: Request, res: Response): Promise<void> {
  const sessionId = req.headers["mcp-session-id"] as string | undefined;
  if (!sessionId || !transports.has(sessionId)) {
    res.status(400).json({
      jsonrpc: "2.0",
      error: { code: -32000, message: "Bad Request: No valid session ID provided" },
      id: req.body?.id,
    });
    return;
  }

  const lastEventId = req.headers["last-event-id"] as string | undefined;
  if (lastEventId) {
    console.log(`[session] ${sessionId} reconnecting with Last-Event-ID: ${lastEventId}`);
  } else {
    console.log(`[session] ${sessionId} establishing SSE stream`);
  }

  await transports.get(sessionId)!.handleRequest(req, res);
}

async function handleDelete(req: Request, res: Response): Promise<void> {
  const sessionId = req.headers["mcp-session-id"] as string | undefined;
  if (!sessionId || !transports.has(sessionId)) {
    res.status(400).json({
      jsonrpc: "2.0",
      error: { code: -32000, message: "Bad Request: No valid session ID provided" },
      id: req.body?.id,
    });
    return;
  }

  console.log(`[session] terminating: ${sessionId}`);
  try {
    await transports.get(sessionId)!.handleRequest(req, res);
  } catch (err) {
    console.error("[error] DELETE:", err);
    if (!res.headersSent) {
      res.status(500).json({
        jsonrpc: "2.0",
        error: { code: -32603, message: "Error handling session termination" },
        id: req.body?.id,
      });
    }
  }
}

// 同时挂载到 / 和 /mcp
for (const path of ["/", "/mcp"]) {
  app.post(path, handlePost);
  app.get(path, handleGet);
  app.delete(path, handleDelete);
}

app.get("/health", (_req, res) => {
  res.json({ status: "ok" });
});

// --------------------------------------------------------------------------
// 启动
// --------------------------------------------------------------------------

const HOST = process.env.HOST ?? "0.0.0.0";
const PORT = Number(process.env.PORT ?? 80);

const httpServer = app.listen(PORT, HOST, () => {
  console.log(`Code Execution MCP Server listening on http://${HOST}:${PORT}`);
  console.log(`Endpoints: / and /mcp`);
  console.log(`Hooks file: ${HOOKS_PATH}`);
  console.log(`Default timeout: ${DEFAULT_TIMEOUT}s, Max timeout: ${MAX_TIMEOUT}s`);
});

httpServer.on("error", (err: NodeJS.ErrnoException) => {
  if (err.code === "EADDRINUSE") {
    console.error(`Port ${PORT} is already in use. Set PORT to a free port.`);
  } else {
    console.error("HTTP server error:", err);
  }
  process.exit(1);
});

process.on("SIGINT", async () => {
  console.log("\nShutting down...");
  for (const [sid, transport] of transports) {
    try {
      await transport.close();
      transports.delete(sid);
    } catch {
      // ignore
    }
  }
  httpServer.close(() => {
    console.log("Server stopped.");
    process.exit(0);
  });
});
