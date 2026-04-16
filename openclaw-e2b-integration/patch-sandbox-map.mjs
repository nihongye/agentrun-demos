#!/usr/bin/env node
/**
 * Build-time patch: make all mega chunks share a single SANDBOX_BACKEND_FACTORIES Map
 * via globalThis[Symbol.for(...)].
 *
 * Problem (E2B LESSONS #37): esbuild code splitting duplicates
 *   const SANDBOX_BACKEND_FACTORIES = /* @__PURE__ *​/ new Map();
 * into 7 mega chunks. Each chunk gets its own independent Map instance.
 * Plugin registers into chunk A's Map, Gateway reads from chunk B's Map → not found.
 *
 * Fix: replace the Map initialization so all chunks reference the same globalThis instance:
 *   const SANDBOX_BACKEND_FACTORIES = globalThis[Symbol.for("openclaw.sandbox-backend-factories")]
 *     || (globalThis[Symbol.for("openclaw.sandbox-backend-factories")] = new Map());
 */

import fs from "node:fs";
import path from "node:path";

const DIST_DIR = process.argv[2] || "/app/dist";
const SYMBOL_KEY = "openclaw.sandbox-backend-factories";

const OLD_PATTERN = `const SANDBOX_BACKEND_FACTORIES = /* @__PURE__ */ new Map();`;
const NEW_CODE = `const SANDBOX_BACKEND_FACTORIES = globalThis[Symbol.for("${SYMBOL_KEY}")] || (globalThis[Symbol.for("${SYMBOL_KEY}")] = new Map());`;

let patchedCount = 0;

const files = fs.readdirSync(DIST_DIR).filter((f) => f.endsWith(".js"));
for (const file of files) {
  const fp = path.join(DIST_DIR, file);
  const stat = fs.statSync(fp);
  // Only patch mega chunks (>3MB)
  if (stat.size < 3_000_000) continue;

  const content = fs.readFileSync(fp, "utf8");
  if (!content.includes(OLD_PATTERN)) continue;

  const patched = content.replace(OLD_PATTERN, NEW_CODE);
  if (patched === content) continue;

  fs.writeFileSync(fp, patched, "utf8");
  patchedCount++;
  console.log(`Patched: ${file}`);
}

console.log(`\nDone. Patched ${patchedCount} mega chunk(s).`);
if (patchedCount === 0) {
  console.error("WARNING: No chunks were patched! The pattern may have changed.");
  process.exit(1);
}
