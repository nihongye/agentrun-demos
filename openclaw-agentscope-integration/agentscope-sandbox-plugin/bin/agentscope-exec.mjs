#!/usr/bin/env node
/**
 * AgentScope sandbox exec helper — spawned by OpenClaw's exec runtime.
 * Connects to an existing AgentScope sandbox via sandbox-manager and runs a command,
 * piping stdout/stderr to the local process.
 *
 * Usage:
 *   node agentscope-exec.mjs --sandbox-id <id> --manager-url <url>
 *                             --manager-token <token> --workdir <dir> --command <cmd>
 */

function parseArgs(argv) {
  const args = {};
  for (let i = 2; i < argv.length; i += 2) {
    const key = argv[i].replace(/^--/, "");
    args[key] = argv[i + 1];
  }
  return args;
}

const args = parseArgs(process.argv);
const {
  "sandbox-id": sandboxId,
  "manager-url": managerUrl,
  "manager-token": managerToken,
  workdir,
  command,
} = args;

if (!sandboxId || !command) {
  process.stderr.write("agentscope-exec: missing --sandbox-id or --command\n");
  process.exit(1);
}

if (!managerUrl) {
  process.stderr.write("agentscope-exec: missing --manager-url\n");
  process.exit(1);
}

// Collect stdin (if any) with a short timeout
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
    // stdin closed or errored
  }
  process.stdin.destroy();
}

try {
  const headers = {
    "Content-Type": "application/json",
    ...(managerToken ? { Authorization: `Bearer ${managerToken}` } : {}),
  };

  // If we have stdin, prepend it as a heredoc
  let actualCommand = command;
  if (stdinBuf && stdinBuf.length > 0) {
    const tmpName = `/tmp/.as-stdin-${Date.now()}`;
    // Write stdin to temp file first
    const writeResp = await fetch(`${managerUrl}/call_tool`, {
      method: "POST",
      headers,
      body: JSON.stringify({
        identity: sandboxId,
        tool_name: "run_shell_command",
        arguments: {
          command: `cat > ${tmpName} << 'AGENTSCOPE_STDIN_EOF'\n${stdinBuf.toString("utf8")}\nAGENTSCOPE_STDIN_EOF`,
        },
      }),
    });
    if (!writeResp.ok) {
      process.stderr.write(`agentscope-exec: failed to write stdin: ${writeResp.status}\n`);
    }
    actualCommand = `cat '${tmpName}' | ${command}; __exit=$?; rm -f '${tmpName}'; exit $__exit`;
  }

  const resp = await fetch(`${managerUrl}/call_tool`, {
    method: "POST",
    headers,
    body: JSON.stringify({
      identity: sandboxId,
      tool_name: "run_shell_command",
      arguments: { command: actualCommand },
    }),
  });

  if (!resp.ok) {
    const text = await resp.text().catch(() => "");
    process.stderr.write(`agentscope-exec: sandbox-manager error (${resp.status}): ${text}\n`);
    process.exit(1);
  }

  const result = await resp.json();
  const content = result.data?.content ?? [];

  let exitCode = 0;
  for (const item of content) {
    if (item.description === "stdout") process.stdout.write(item.text);
    else if (item.description === "stderr") process.stderr.write(item.text);
    else if (item.description === "returncode") exitCode = parseInt(item.text, 10) || 0;
  }

  process.exit(exitCode);
} catch (err) {
  process.stderr.write(`agentscope-exec: ${err?.message || err}\n`);
  process.exit(1);
}
