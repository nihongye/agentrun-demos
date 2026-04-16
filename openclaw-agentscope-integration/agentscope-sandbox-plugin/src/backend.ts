import path from "node:path";
import { fileURLToPath } from "node:url";
import type {
  CreateSandboxBackendParams,
  SandboxBackendCommandParams,
  SandboxBackendCommandResult,
  SandboxBackendExecSpec,
  SandboxBackendFactory,
  SandboxBackendHandle,
  SandboxBackendManager,
  SandboxBackendRuntimeInfo,
  SandboxFsBridge,
  RemoteShellSandboxHandle,
} from "openclaw/plugin-sdk/sandbox";
import { createRemoteShellSandboxFsBridge } from "openclaw/plugin-sdk/sandbox";
import type { SandboxContext } from "openclaw/plugin-sdk/sandbox";
import type { ResolvedAgentscopePluginConfig } from "./config.js";

const __dirname = path.dirname(fileURLToPath(import.meta.url));

// ── sandbox-manager HTTP client ──

interface SandboxManagerClient {
  managerUrl: string;
  managerToken: string;

  createSandbox(sandboxType: string, sessionCtxId: string): Promise<string>;
  releaseSandbox(sandboxId: string): Promise<void>;
  checkHealth(sandboxId: string): Promise<boolean>;
  callTool(sandboxId: string, toolName: string, args: Record<string, unknown>): Promise<CallToolResult>;
}

interface CallToolResult {
  stdout: string;
  stderr: string;
  returncode: number;
  isError: boolean;
}

function createSandboxManagerClient(managerUrl: string, managerToken: string): SandboxManagerClient {
  const headers = {
    "Content-Type": "application/json",
    ...(managerToken ? { Authorization: `Bearer ${managerToken}` } : {}),
  };

  async function post(endpoint: string, body: Record<string, unknown>): Promise<unknown> {
    const resp = await fetch(`${managerUrl}${endpoint}`, {
      method: "POST",
      headers,
      body: JSON.stringify(body),
    });
    if (!resp.ok) {
      const text = await resp.text().catch(() => "");
      throw new Error(`sandbox-manager ${endpoint} failed (${resp.status}): ${text}`);
    }
    return resp.json();
  }

  return {
    managerUrl,
    managerToken,

    async createSandbox(sandboxType: string, sessionCtxId: string): Promise<string> {
      const result = (await post("/create_from_pool", {
        sandbox_type: sandboxType,
        meta: { session_ctx_id: sessionCtxId },
      })) as { data: string };
      return result.data;
    },

    async releaseSandbox(sandboxId: string): Promise<void> {
      await post("/release", { identity: sandboxId });
    },

    async checkHealth(sandboxId: string): Promise<boolean> {
      try {
        const result = (await post("/check_health", { identity: sandboxId })) as { data: boolean };
        return result.data === true;
      } catch {
        return false;
      }
    },

    async callTool(sandboxId: string, toolName: string, args: Record<string, unknown>): Promise<CallToolResult> {
      const result = (await post("/call_tool", {
        identity: sandboxId,
        tool_name: toolName,
        arguments: args,
      })) as { data: { content?: Array<{ type: string; text: string; description?: string }>; isError?: boolean } };

      // Parse agentscope response format: data.content[] array
      const content = result.data?.content ?? [];
      let stdout = "";
      let stderr = "";
      let returncode = 0;

      for (const item of content) {
        if (item.description === "stdout") stdout += item.text;
        else if (item.description === "stderr") stderr += item.text;
        else if (item.description === "returncode") returncode = parseInt(item.text, 10) || 0;
      }

      return { stdout, stderr, returncode, isError: result.data?.isError ?? false };
    },
  };
}

// ── Factory & Manager ──

export function createAgentscopeSandboxBackendFactory(params: {
  pluginConfig: ResolvedAgentscopePluginConfig;
}): SandboxBackendFactory {
  return async (createParams) =>
    await createAgentscopeSandboxBackend({ ...params, createParams });
}

export function createAgentscopeSandboxBackendManager(params: {
  pluginConfig: ResolvedAgentscopePluginConfig;
}): SandboxBackendManager {
  const client = createSandboxManagerClient(
    params.pluginConfig.managerUrl,
    params.pluginConfig.managerToken,
  );

  return {
    async describeRuntime({ entry }): Promise<SandboxBackendRuntimeInfo> {
      try {
        const healthy = await client.checkHealth(entry.containerName);
        return {
          running: healthy,
          actualConfigLabel: params.pluginConfig.sandboxType,
          configLabelMatch: entry.image === params.pluginConfig.sandboxType,
        };
      } catch {
        return { running: false, configLabelMatch: false };
      }
    },

    async removeRuntime({ entry }) {
      try {
        await client.releaseSandbox(entry.containerName);
      } catch {
        // Already dead, ignore
      }
    },
  };
}

// ── Backend Handle ──

async function createAgentscopeSandboxBackend(params: {
  pluginConfig: ResolvedAgentscopePluginConfig;
  createParams: CreateSandboxBackendParams;
}): Promise<SandboxBackendHandle> {
  const config = params.pluginConfig;
  const scopeKey = params.createParams.scopeKey;

  const impl = new AgentscopeSandboxBackendImpl({ config, scopeKey });

  return {
    id: "agentscope",
    runtimeId: `agentscope-${scopeKey}`,
    runtimeLabel: `agentscope:${scopeKey}`,
    workdir: config.workdir,
    env: params.createParams.cfg.docker?.env,
    configLabel: config.sandboxType,
    configLabelKind: "SandboxType",

    buildExecSpec: async ({ command, workdir, env, usePty }) => {
      return await impl.buildExecSpec({ command, workdir, env, usePty });
    },

    runShellCommand: async (cmdParams) => {
      return await impl.runShellCommand(cmdParams);
    },

    createFsBridge: ({ sandbox }) => {
      return impl.createFsBridge({ sandbox });
    },
  };
}

// ── Implementation ──

class AgentscopeSandboxBackendImpl {
  private client: SandboxManagerClient | null = null;
  private sandboxId: string | null = null;
  private ensurePromise: Promise<void> | null = null;

  constructor(
    private readonly params: {
      config: ResolvedAgentscopePluginConfig;
      scopeKey: string;
    },
  ) {}

  async buildExecSpec(p: {
    command: string;
    workdir?: string;
    env: Record<string, string>;
    usePty: boolean;
  }): Promise<SandboxBackendExecSpec> {
    await this.ensureSandboxExists();
    const execScript = "/app/agentscope-exec.mjs";
    return {
      argv: [
        "node",
        execScript,
        "--sandbox-id", this.sandboxId!,
        "--manager-url", this.params.config.managerUrl,
        "--manager-token", this.params.config.managerToken,
        "--workdir", p.workdir ?? this.params.config.workdir,
        "--command", p.command,
      ],
      env: process.env,
      stdinMode: "pipe-closed",
    };
  }

  async runShellCommand(
    params: SandboxBackendCommandParams,
  ): Promise<SandboxBackendCommandResult> {
    await this.ensureSandboxExists();

    // Build the shell command
    const args = params.args ?? [];
    const shellParts = [params.script, "agentscope-sandbox-fs", ...args];
    const shellCmd = shellParts
      .map((a) => `'${a.replace(/'/g, "'\\''")}'`)
      .join(" ");
    const fullCmd = `/bin/sh -c ${shellCmd}`;

    // Handle stdin: write to temp file via shell, then pipe
    let actualCmd = fullCmd;
    if (params.stdin != null) {
      const stdinStr =
        typeof params.stdin === "string"
          ? params.stdin
          : Buffer.from(params.stdin).toString("utf8");
      // Escape for shell heredoc
      const escaped = stdinStr.replace(/'/g, "'\\''");
      const tmpName = `/tmp/.as-stdin-${Date.now()}`;
      actualCmd = `printf '%s' '${escaped}' > ${tmpName} && cat ${tmpName} | ${fullCmd}; __exit=$?; rm -f ${tmpName}; exit $__exit`;
    }

    const result = await this.client!.callTool(
      this.sandboxId!,
      "run_shell_command",
      { command: actualCmd },
    );

    const exitCode = result.returncode;
    const stdout = Buffer.from(result.stdout, "utf8");
    const stderr = Buffer.from(result.stderr, "utf8");

    if (exitCode !== 0 && !params.allowFailure) {
      const error = new Error(
        `AgentScope command failed (exit ${exitCode}): ${result.stderr.slice(0, 500)}`,
      );
      (error as any).code = exitCode;
      throw error;
    }

    return { stdout, stderr, code: exitCode };
  }

  createFsBridge({ sandbox }: { sandbox: SandboxContext }): SandboxFsBridge {
    const self = this;
    const runtime: RemoteShellSandboxHandle = {
      remoteWorkspaceDir: this.params.config.workdir,
      remoteAgentWorkspaceDir: this.params.config.agentWorkdir,
      runRemoteShellScript: (p) => self.runShellCommand(p),
    };
    return createRemoteShellSandboxFsBridge({ sandbox, runtime });
  }

  private async ensureSandboxExists(): Promise<void> {
    if (this.sandboxId) return;
    if (this.ensurePromise) return await this.ensurePromise;
    this.ensurePromise = this.doCreateSandbox();
    try {
      await this.ensurePromise;
    } catch (err) {
      this.ensurePromise = null;
      throw err;
    }
  }

  private async doCreateSandbox(): Promise<void> {
    const cfg = this.params.config;
    this.client = createSandboxManagerClient(cfg.managerUrl, cfg.managerToken);
    const sessionCtxId = `openclaw-${this.params.scopeKey}-${Date.now()}`;
    this.sandboxId = await this.client.createSandbox(cfg.sandboxType, sessionCtxId);

    // Wait for sandbox to be healthy
    const maxAttempts = 30;
    const interval = 2000;
    for (let i = 0; i < maxAttempts; i++) {
      if (await this.client.checkHealth(this.sandboxId)) return;
      await new Promise((r) => setTimeout(r, interval));
    }
    throw new Error(`AgentScope sandbox ${this.sandboxId} failed health check after ${maxAttempts * interval / 1000}s`);
  }
}
