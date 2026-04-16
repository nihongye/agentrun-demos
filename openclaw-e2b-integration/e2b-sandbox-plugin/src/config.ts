import path from "node:path";
import type { OpenClawPluginConfigSchema } from "openclaw/plugin-sdk/core";

export type E2bPluginConfig = {
  apiUrl?: string;
  sandboxUrl?: string;
  apiKey?: string;
  template?: string;
  workdir?: string;
  agentWorkdir?: string;
  timeoutSeconds?: number;
};

export type ResolvedE2bPluginConfig = {
  apiUrl: string;
  sandboxUrl: string;
  apiKey: string;
  template: string;
  workdir: string;
  agentWorkdir: string;
  timeoutMs: number;
};

const DEFAULT_WORKDIR = "/home/user";
const DEFAULT_AGENT_WORKDIR = "/home/user/agent";
const DEFAULT_TIMEOUT_MS = 300_000;

type ParseSuccess = { success: true; data?: E2bPluginConfig };
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
    throw new Error(`E2B remote path must be absolute: ${candidate}`);
  }
  return normalized;
}
