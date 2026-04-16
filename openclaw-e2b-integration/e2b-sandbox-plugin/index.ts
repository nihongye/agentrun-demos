import type { OpenClawPluginApi } from "openclaw/plugin-sdk/core";
import { registerSandboxBackend } from "openclaw/plugin-sdk/sandbox";
import {
  createE2bSandboxBackendFactory,
  createE2bSandboxBackendManager,
} from "./src/backend.js";
import { createE2bPluginConfigSchema, resolveE2bPluginConfig } from "./src/config.js";

const plugin = {
  id: "e2b-sandbox",
  name: "E2B Cloud Sandbox",
  description: "Remote cloud sandbox backend powered by E2B protocol.",
  configSchema: createE2bPluginConfigSchema(),
  register(api: OpenClawPluginApi) {
    if (api.registrationMode !== "full") return;
    const pluginConfig = resolveE2bPluginConfig(api.pluginConfig);
    // Normal registration — works because Dockerfile runs patch-sandbox-map.mjs
    // at build time to make all mega chunks share a single Map via globalThis.
    // See E2B LESSONS #37, #40, #41 for why runtime workarounds don't work.
    registerSandboxBackend("e2b", {
      factory: createE2bSandboxBackendFactory({ pluginConfig }),
      manager: createE2bSandboxBackendManager({ pluginConfig }),
    });
  },
};

export default plugin;
