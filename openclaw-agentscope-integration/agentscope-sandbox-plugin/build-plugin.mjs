#!/usr/bin/env node
/**
 * Build the agentscope-sandbox plugin into a single index.js bundle.
 *
 * Usage (from the openclaw root, after `npm install`):
 *   node extensions/agentscope-sandbox/build-plugin.mjs
 *
 * Resolves `openclaw/plugin-sdk/*` imports to relative paths pointing at
 * dist/plugin-sdk/*.js, keeping them external (not bundled).
 */
import { build } from "esbuild";
import path from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const openclawRoot = path.resolve(__dirname, "..", "..");
const outDir = __dirname; // output index.js next to index.ts

// Plugin: rewrite `openclaw/plugin-sdk/foo` → `../../plugin-sdk/foo.js` (relative from dist/extensions/agentscope-sandbox/)
const openclawRewritePlugin = {
  name: "openclaw-rewrite",
  setup(b) {
    b.onResolve({ filter: /^openclaw\/plugin-sdk/ }, (args) => {
      const subpath = args.path.replace(/^openclaw\/plugin-sdk\/?/, "");
      const relTarget = subpath
        ? `../../plugin-sdk/${subpath}.js`
        : `../../plugin-sdk/index.js`;
      return { path: relTarget, external: true };
    });
  },
};

await build({
  entryPoints: [path.join(__dirname, "index.ts")],
  bundle: true,
  format: "esm",
  platform: "node",
  target: "node22",
  outfile: path.join(outDir, "index.js"),
  external: ["node:*"],
  plugins: [openclawRewritePlugin],
});

console.log("Built agentscope-sandbox plugin → index.js");
