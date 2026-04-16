import type { OpenClawPluginApi } from "openclaw/plugin-sdk/core";
import { registerSandboxBackend } from "openclaw/plugin-sdk/sandbox";
import {
  createAgentscopeSandboxBackendFactory,
  createAgentscopeSandboxBackendManager,
} from "./src/backend.js";
import { createAgentscopePluginConfigSchema, resolveAgentscopePluginConfig } from "./src/config.js";

const plugin = {
  id: "agentscope-sandbox",
  name: "AgentScope Sandbox",
  description: "Remote sandbox backend powered by AgentScope protocol via sandbox-manager.",
  configSchema: createAgentscopePluginConfigSchema(),
  register(api: OpenClawPluginApi) {
    if (api.registrationMode !== "full") return;
    const pluginConfig = resolveAgentscopePluginConfig(api.pluginConfig);
    registerSandboxBackend("agentscope", {
      factory: createAgentscopeSandboxBackendFactory({ pluginConfig }),
      manager: createAgentscopeSandboxBackendManager({ pluginConfig }),
    });
  },
};

export default plugin;
