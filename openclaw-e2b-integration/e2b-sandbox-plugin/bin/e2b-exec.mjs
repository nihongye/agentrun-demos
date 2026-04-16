#!/usr/bin/env node
/**
 * E2B sandbox exec helper — spawned by OpenClaw's exec runtime.
 * Connects to an existing E2B sandbox and runs a command,
 * piping stdin/stdout/stderr between the local process and the remote sandbox.
 *
 * Usage:
 *   node e2b-exec.mjs --sandbox-id <id> --api-url <url> --sandbox-url <url>
 *                      --api-key <key> --workdir <dir> --command <cmd>
 */

import { Sandbox } from "e2b";

function parseArgs(argv) {
  const args = {};
  for (let i = 2; i < argv.length; i += 2) {
    const key = argv[i].replace(/^--/, "");
    args[key] = argv[i + 1];
  }
  return args;
}

const args = parseArgs(process.argv);
const { "sandbox-id": sandboxId, "api-url": apiUrl, "sandbox-url": sandboxUrl,
        "api-key": apiKey, workdir, command } = args;

if (!sandboxId || !command) {
  process.stderr.write("e2b-exec: missing --sandbox-id or --command\n");
  process.exit(1);
}

// Collect stdin (if any) with a short timeout — OpenClaw may spawn us with
// pipe-open stdin that never sends EOF, so we must not block indefinitely.
let stdinBuf = null;
if (!process.stdin.isTTY) {
  const chunks = [];
  try {
    await Promise.race([
      (async () => {
        for await (const chunk of process.stdin) {
          chunks.push(chunk);
        }
      })(),
      new Promise((resolve) => setTimeout(resolve, 200)),
    ]);
    if (chunks.length > 0) {
      stdinBuf = Buffer.concat(chunks);
    }
  } catch {
    // stdin closed or errored, that's fine
  }
  // Ensure stdin doesn't keep the process alive
  process.stdin.destroy();
}

try {
  const sb = await Sandbox.connect(sandboxId, {
    apiKey,
    apiUrl,
    sandboxUrl,
  });

  // If we have stdin, write it to a temp file and pipe it
  let actualCommand = command;
  if (stdinBuf && stdinBuf.length > 0) {
    const tmpName = `/tmp/.e2b-stdin-${Date.now()}`;
    await sb.files.write(tmpName, new Uint8Array(stdinBuf).buffer);
    actualCommand = `cat '${tmpName}' | ${command}; __exit=$?; rm -f '${tmpName}'; exit $__exit`;
  }

  let exitCode = 0;
  try {
    const result = await sb.commands.run(actualCommand, {
      cwd: workdir || "/home/user",
      timeoutMs: 300_000,
      onStdout: (data) => process.stdout.write(data),
      onStderr: (data) => process.stderr.write(data),
    });
    exitCode = result.exitCode;
  } catch (err) {
    // E2B SDK throws CommandExitError on non-zero exit (LESSONS #4)
    if (err && typeof err === "object" && "exitCode" in err) {
      exitCode = err.exitCode;
      if (err.stdout) process.stdout.write(err.stdout);
      if (err.stderr) process.stderr.write(err.stderr);
    } else {
      process.stderr.write(`e2b-exec error: ${err?.message || err}\n`);
      exitCode = 1;
    }
  }

  process.exit(exitCode);
} catch (err) {
  process.stderr.write(`e2b-exec: failed to connect to sandbox ${sandboxId}: ${err?.message || err}\n`);
  process.exit(1);
}
