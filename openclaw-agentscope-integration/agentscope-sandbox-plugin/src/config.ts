import path from "node:path";
import type { OpenClawPluginConfigSchema } from "openclaw/plugin-sdk/core";

export type AgentscopePluginConfig = {
  managerUrl?: string;
  managerToken?: string;
  sandboxType?: string;
  workdir?: string;
  agentWorkdir?: string;
  timeoutSeconds?: number;
};

export type ResolvedAgentscopePluginConfig = {
  managerUrl: string;
  managerToken: string;
  sandboxType: string;
  workdir: string;
  agentWorkdir: string;
  timeoutMs: number;
};

const DEFAULT_WORKDIR = "/workspace";
const DEFAULT_AGENT_WORKDIR = "/workspace/agent";
const DEFAULT_TIMEOUT_MS = 300_000;
const DEFAULT_SANDBOX_TYPE = "agentscope-sandbox";

type ParseSuccess = { success: true; data?: AgentscopePluginConfig };
type ParseFailure = {
  success: false;
  error: { issues: Array<{ path: Array<string | number>; message: string }> };
};

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function trimString(value: unknown): string | undefined {
  if (typeof value !== "string") return undefined;
  const trimmed = value.trim();
  return trimmed || undefined;
}

function normalizeRemotePath(value: string | undefined, fallback: string): string {
  const candidate = value ?? fallback;
  const normalized = path.posix.normalize(candidate.trim() || fallback);
  if (!normalized.startsWith("/")) {
    throw new Error(`Remote path must be absolute: ${candidate}`);
  }
  return normalized;
}

export function createAgentscopePluginConfigSchema(): OpenClawPluginConfigSchema {
  const safeParse = (value: unknown): ParseSuccess | ParseFailure => {
    if (value === undefined) return { success: true, data: undefined };
    if (!isRecord(value)) {
      return { success: false, error: { issues: [{ path: [], message: "expected config object" }] } };
    }
    const allowedKeys = new Set([
      "managerUrl", "managerToken", "sandboxType",
      "workdir", "agentWorkdir", "timeoutSeconds",
    ]);
    for (const key of Object.keys(value)) {
      if (!allowedKeys.has(key)) {
        return { success: false, error: { issues: [{ path: [key], message: `unknown config key: ${key}` }] } };
      }
    }
    const timeoutSeconds = value.timeoutSeconds;
    if (
      timeoutSeconds !== undefined &&
      (typeof timeoutSeconds !== "number" || !Number.isFinite(timeoutSeconds) || timeoutSeconds < 1)
    ) {
      return { success: false, error: { issues: [{ path: ["timeoutSeconds"], message: "timeoutSeconds must be a number >= 1" }] } };
    }
    return {
      success: true,
      data: {
        managerUrl: trimString(value.managerUrl),
        managerToken: trimString(value.managerToken),
        sandboxType: trimString(value.sandboxType),
        workdir: trimString(value.workdir),
        agentWorkdir: trimString(value.agentWorkdir),
        timeoutSeconds: timeoutSeconds as number | undefined,
      },
    };
  };

  return {
    safeParse,
    jsonSchema: {
      type: "object",
      additionalProperties: false,
      properties: {
        managerUrl: { type: "string" },
        managerToken: { type: "string" },
        sandboxType: { type: "string" },
        workdir: { type: "string" },
        agentWorkdir: { type: "string" },
        timeoutSeconds: { type: "number", minimum: 1 },
      },
    },
  };
}

export function resolveAgentscopePluginConfig(value: unknown): ResolvedAgentscopePluginConfig {
  const parsed = createAgentscopePluginConfigSchema().safeParse?.(value);
  if (!parsed || !parsed.success) {
    const issues = parsed && !parsed.success ? parsed.error?.issues : undefined;
    const message = issues?.map((i: { message: string }) => i.message).join(", ") || "invalid config";
    throw new Error(`Invalid agentscope-sandbox plugin config: ${message}`);
  }
  const cfg = (parsed.data ?? {}) as AgentscopePluginConfig;
  if (!cfg.managerUrl) throw new Error("agentscope-sandbox plugin config: managerUrl is required");
  if (!cfg.managerToken) throw new Error("agentscope-sandbox plugin config: managerToken is required");

  return {
    managerUrl: cfg.managerUrl.replace(/\/+$/, ""),
    managerToken: cfg.managerToken,
    sandboxType: cfg.sandboxType || DEFAULT_SANDBOX_TYPE,
    workdir: normalizeRemotePath(cfg.workdir, DEFAULT_WORKDIR),
    agentWorkdir: normalizeRemotePath(cfg.agentWorkdir, DEFAULT_AGENT_WORKDIR),
    timeoutMs: typeof cfg.timeoutSeconds === "number" ? Math.floor(cfg.timeoutSeconds * 1000) : DEFAULT_TIMEOUT_MS,
  };
}
