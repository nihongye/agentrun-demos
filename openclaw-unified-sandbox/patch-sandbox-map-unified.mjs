#!/usr/bin/env node
/**
 * Build-time patch: make all mega chunks share a single SANDBOX_BACKEND_FACTORIES Map
 * via globalThis[Symbol.for(...)].
 *
 * Enhanced version for unified sandbox image — scans both dist/ top-level AND
 * dist/plugin-sdk/ subdirectory. The original patch-sandbox-map.mjs only scans
 * the top-level, missing plugin-sdk/setup-wizard-helpers-*.js which is used by
 * the AgentScope plugin's import chain.
 *
 * Problem (E2B LESSONS #37): esbuild code splitting duplicates
 *   const SANDBOX_BACKEND_FACTORIES = /* @__PURE__ *​/ new Map();
 * into multiple mega chunks. Each chunk gets its own independent Map instance.
 * Plugin registers into chunk A's Map, Gateway reads from chunk B's Map → not found.
 *
 * Fix: replace the Map initialization so all chunks reference the same globalThis instance.
 */

import fs from "node:fs";
import path from "node:path";

const DIST_DIR = process.argv[2] || "/app/dist";
const SYMBOL_KEY = "openclaw.sandbox-backend-factories";

const OLD_PATTERN = `const SANDBOX_BACKEND_FACTORIES = /* @__PURE__ */ new Map();`;
const NEW_CODE = `const SANDBOX_BACKEND_FACTORIES = globalThis[Symbol.for("${SYMBOL_KEY}")] || (globalThis[Symbol.for("${SYMBOL_KEY}")] = new Map());`;

let patchedCount = 0;

// Scan directories: top-level dist/ AND dist/plugin-sdk/
const dirsToScan = [DIST_DIR];
const pluginSdkDir = path.join(DIST_DIR, "plugin-sdk");
if (fs.existsSync(pluginSdkDir)) {
  dirsToScan.push(pluginSdkDir);
}

for (const dir of dirsToScan) {
  const files = fs.readdirSync(dir).filter((f) => f.endsWith(".js"));
  for (const file of files) {
    const fp = path.join(dir, file);
    const stat = fs.statSync(fp);
    // Only patch mega chunks (>3MB)
    if (stat.size < 3_000_000) continue;

    const content = fs.readFileSync(fp, "utf8");
    if (!content.includes(OLD_PATTERN)) continue;

    const patched = content.replace(OLD_PATTERN, NEW_CODE);
    if (patched === content) continue;

    fs.writeFileSync(fp, patched, "utf8");
    patchedCount++;
    const relPath = path.relative(DIST_DIR, fp);
    console.log(`Patched: ${relPath}`);
  }
}

console.log(`\nDone. Patched ${patchedCount} file(s) across ${dirsToScan.length} directory(ies).`);
if (patchedCount === 0) {
  console.error("WARNING: No files were patched! The pattern may have changed.");
  process.exit(1);
}
