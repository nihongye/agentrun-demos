import path from "node:path";
import crypto from "node:crypto";
import { fileURLToPath } from "node:url";
import { Sandbox } from "e2b";
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
import type { ResolvedE2bPluginConfig } from "./config.js";

const __dirname = path.dirname(fileURLToPath(import.meta.url));

type CreateE2bSandboxBackendFactoryParams = {
  pluginConfig: ResolvedE2bPluginConfig;
};

export function createE2bSandboxBackendFactory(
  params: CreateE2bSandboxBackendFactoryParams,
): SandboxBackendFactory {
  return async (createParams) =>
    await createE2bSandboxBackend({ ...params, createParams });
}

export function createE2bSandboxBackendManager(params: {
  pluginConfig: ResolvedE2bPluginConfig;
}): SandboxBackendManager {
  return {
    async describeRuntime({ entry }): Promise<SandboxBackendRuntimeInfo> {
      try {
        const sb = await Sandbox.connect(entry.containerName, {
          apiKey: params.pluginConfig.apiKey,
          apiUrl: params.pluginConfig.apiUrl,
          sandboxUrl: params.pluginConfig.sandboxUrl,
        });
        // If connect succeeds, sandbox is running
        return {
          running: true,
          actualConfigLabel: params.pluginConfig.template,
          configLabelMatch: entry.image === params.pluginConfig.template,
        };
      } catch {
        return {
          running: false,
          configLabelMatch: false,
        };
      }
    },
    async removeRuntime({ entry }) {
      try {
        const sb = await Sandbox.connect(entry.containerName, {
          apiKey: params.pluginConfig.apiKey,
          apiUrl: params.pluginConfig.apiUrl,
          sandboxUrl: params.pluginConfig.sandboxUrl,
        });
        await sb.kill();
      } catch {
        // Already dead, ignore
      }
    },
  };
}

async function createE2bSandboxBackend(params: {
  pluginConfig: ResolvedE2bPluginConfig;
  createParams: CreateSandboxBackendParams;
}): Promise<SandboxBackendHandle> {
  const config = params.pluginConfig;
  const sandboxName = buildE2bSandboxName(params.createParams.scopeKey);

  const impl = new E2bSandboxBackendImpl({
    config,
    createParams: params.createParams,
    sandboxName,
  });

  return {
    id: "e2b",
    runtimeId: sandboxName,
    runtimeLabel: `e2b:${sandboxName}`,
    workdir: config.workdir,
    env: params.createParams.cfg.docker?.env,
    configLabel: config.template,
    configLabelKind: "Template",

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

class E2bSandboxBackendImpl {
  private sandbox: Sandbox | null = null;
  private sandboxId: string | null = null;
  private ensurePromise: Promise<void> | null = null;

  constructor(
    private readonly params: {
      config: ResolvedE2bPluginConfig;
      createParams: CreateSandboxBackendParams;
      sandboxName: string;
    },
  ) {}

  async buildExecSpec(p: {
    command: string;
    workdir?: string;
    env: Record<string, string>;
    usePty: boolean;
  }): Promise<SandboxBackendExecSpec> {
    await this.ensureSandboxExists();
    const execScript = "/app/e2b-exec.mjs";
    return {
      argv: [
        "node",
        execScript,
        "--sandbox-id", this.sandboxId!,
        "--api-url", this.params.config.apiUrl,
        "--sandbox-url", this.params.config.sandboxUrl,
        "--api-key", this.params.config.apiKey,
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
    const sb = this.sandbox!;

    // Build the shell command: /bin/sh -c "$script" -- "$arg1" "$arg2" ...
    const args = params.args ?? [];
    const shellParts = [params.script, "e2b-sandbox-fs", ...args];
    const shellCmd = shellParts
      .map((a) => `'${a.replace(/'/g, "'\\''")}'`)
      .join(" ");
    const fullCmd = `/bin/sh -c ${shellCmd}`;

    // Handle stdin: write to temp file, then pipe via cat
    let actualCmd = fullCmd;
    if (params.stdin != null) {
      const stdinBuf =
        typeof params.stdin === "string"
          ? Buffer.from(params.stdin, "utf8")
          : params.stdin;
      const tmpName = `/tmp/.e2b-stdin-${crypto.randomUUID()}`;
      // E2B SDK files.write() accepts string | ArrayBuffer, not Buffer
      await sb.files.write(tmpName, new Uint8Array(stdinBuf).buffer as ArrayBuffer);
      actualCmd = `cat '${tmpName}' | ${fullCmd}; __exit=$?; rm -f '${tmpName}'; exit $__exit`;
    }

    let stdout = "";
    let stderr = "";
    let exitCode = 0;

    try {
      // LESSONS #4: commands.run() throws CommandExitError on non-zero exit
      // LESSONS #5: onStdout/onStderr callbacks receive plain string
      const result = await sb.commands.run(actualCmd, {
        cwd: this.params.config.workdir,
        timeoutMs: this.params.config.timeoutMs,
        onStdout: (data: string) => { stdout += data; },
        onStderr: (data: string) => { stderr += data; },
      });
      exitCode = result.exitCode;
      // Use accumulated stdout/stderr from callbacks (more reliable for streaming)
      if (!stdout && result.stdout) stdout = result.stdout;
      if (!stderr && result.stderr) stderr = result.stderr;
    } catch (err: unknown) {
      // LESSONS #4: CommandExitError has exitCode, stdout, stderr
      if (err && typeof err === "object" && "exitCode" in err) {
        const cmdErr = err as { exitCode: number; stdout: string; stderr: string };
        exitCode = cmdErr.exitCode;
        if (!stdout && cmdErr.stdout) stdout = cmdErr.stdout;
        if (!stderr && cmdErr.stderr) stderr = cmdErr.stderr;
      } else {
        if (!params.allowFailure) throw err;
        exitCode = 1;
      }
    }

    if (exitCode !== 0 && !params.allowFailure) {
      const error = new Error(
        `E2B command failed (exit ${exitCode}): ${stderr.slice(0, 500)}`,
      );
      (error as any).code = exitCode;
      throw error;
    }

    return {
      stdout: Buffer.from(stdout, "utf8"),
      stderr: Buffer.from(stderr, "utf8"),
      code: exitCode,
    };
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
    if (this.sandbox) return;
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
    const sb = await Sandbox.create(cfg.template, {
      apiKey: cfg.apiKey,
      apiUrl: cfg.apiUrl,
      sandboxUrl: cfg.sandboxUrl,
      timeoutMs: cfg.timeoutMs,
    });
    this.sandbox = sb;
    this.sandboxId = sb.sandboxId;
  }
}

function buildE2bSandboxName(scopeKey: string): string {
  const trimmed = scopeKey.trim() || "session";
  const safe = trimmed
    .toLowerCase()
    .replace(/[^a-z0-9._-]+/g, "-")
    .replace(/^-+|-+$/g, "")
    .slice(0, 32);
  const hash = Array.from(trimmed).reduce(
    (acc, char) => ((acc * 33) ^ char.charCodeAt(0)) >>> 0,
    5381,
  );
  return `e2b-${safe || "session"}-${hash.toString(16).slice(0, 8)}`;
}
