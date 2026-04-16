FROM node:22-slim

WORKDIR /app

# Copy pre-built dist and node_modules
# NOTE: Do NOT prune --prod — OpenClaw dist references devDependencies at runtime
COPY node_modules/ ./node_modules/
COPY dist/ ./dist/
COPY openclaw.mjs ./openclaw.mjs
COPY docs/ ./docs/

# Install both sandbox plugins into dist/extensions/
# IMPORTANT: Only copy compiled .js + metadata. Do NOT copy .ts source files —
# OpenClaw will try to load .ts first, which fails due to missing plugin-sdk paths.
# build.sh prepares these in dist-plugins/ with only the needed files.
COPY dist-plugins/e2b-sandbox/ ./dist/extensions/e2b-sandbox/
COPY dist-plugins/agentscope-sandbox/ ./dist/extensions/agentscope-sandbox/

# Build-time patch: make all mega chunks share a single SANDBOX_BACKEND_FACTORIES Map
# via globalThis[Symbol.for(...)]. Fixes esbuild code splitting issue.
# Uses unified version that scans BOTH dist/ top-level AND dist/plugin-sdk/ subdirectory.
# Original only scans top-level, missing plugin-sdk/setup-wizard-helpers-*.js
# which is the import target for independently-compiled plugins (AgentScope).
COPY patch-sandbox-map-unified.mjs ./patch-sandbox-map.mjs
RUN node patch-sandbox-map.mjs /app/dist && rm patch-sandbox-map.mjs

# Exec helper scripts — spawned by OpenClaw exec runtime to run commands in sandbox
COPY e2b-exec.mjs ./e2b-exec.mjs
COPY agentscope-exec.mjs ./agentscope-exec.mjs

# Both config templates — entrypoint selects one based on SANDBOX_BACKEND env var
COPY openclaw-config-e2b.json ./openclaw-config-e2b.json
COPY openclaw-config-agentscope.json ./openclaw-config-agentscope.json
COPY entrypoint.sh ./entrypoint.sh
RUN chmod +x /app/entrypoint.sh

EXPOSE 18789

CMD ["/app/entrypoint.sh"]
