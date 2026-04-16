/**
 * executor.ts — 多语言代码执行引擎
 *
 * 支持语言：python | javascript | typescript | java | shell
 *
 * 执行流程：
 *   1. 将代码写入临时文件
 *   2. 启动子进程执行（带超时保护）
 *   3. 收集 stdout / stderr
 *   4. 清理临时文件
 *   5. 返回执行结果
 */

import { spawn } from "node:child_process";
import { writeFile, mkdir, rm } from "node:fs/promises";
import { join } from "node:path";
import { tmpdir } from "node:os";
import { randomUUID } from "node:crypto";
import { fileURLToPath } from "node:url";
import { dirname, resolve } from "node:path";

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

// tsx 二进制路径（相对于 dist/ 目录，指向项目根 node_modules/.bin/tsx）
const TSX_BIN = resolve(__dirname, "../node_modules/.bin/tsx");

export type Language = "python" | "javascript" | "typescript" | "java" | "shell";

export interface ExecutionContext {
  language: Language;
  code: string;
  /** 超时时间（秒），默认 30 */
  timeout: number;
}

export interface ExecutionResult {
  stdout: string;
  stderr: string;
  /** 进程退出码；超时时为 -1 */
  exitCode: number;
  executionTimeMs: number;
}

// --------------------------------------------------------------------------
// 内部工具
// --------------------------------------------------------------------------

/**
 * 在子进程中运行命令，带超时控制。
 */
function runProcess(
  cmd: string,
  args: string[],
  options: { cwd?: string; timeoutMs: number }
): Promise<{ stdout: string; stderr: string; exitCode: number }> {
  return new Promise((resolve) => {
    const child = spawn(cmd, args, {
      cwd: options.cwd,
      stdio: ["ignore", "pipe", "pipe"],
      // 不继承父进程 shell，避免环境污染
      env: { ...process.env },
    });

    let stdout = "";
    let stderr = "";

    child.stdout.on("data", (d: Buffer) => (stdout += d.toString()));
    child.stderr.on("data", (d: Buffer) => (stderr += d.toString()));

    let timedOut = false;
    const timer = setTimeout(() => {
      timedOut = true;
      child.kill("SIGKILL");
    }, options.timeoutMs);

    child.on("close", (code) => {
      clearTimeout(timer);
      if (timedOut) {
        resolve({
          stdout,
          stderr: stderr + "\n[Execution timed out]",
          exitCode: -1,
        });
      } else {
        resolve({ stdout, stderr, exitCode: code ?? 0 });
      }
    });

    child.on("error", (err) => {
      clearTimeout(timer);
      resolve({ stdout, stderr: err.message, exitCode: -1 });
    });
  });
}

// --------------------------------------------------------------------------
// 运行环境检测
// --------------------------------------------------------------------------

import { execFileSync } from "node:child_process";

/**
 * 检查命令是否存在于 PATH 中。
 */
function commandExists(cmd: string): boolean {
  try {
    execFileSync("which", [cmd], { stdio: "ignore" });
    return true;
  } catch {
    return false;
  }
}

/**
 * 检查语言运行环境，缺失时直接返回带 stderr 提示的结果。
 */
function checkRuntime(
  language: string,
  commands: string[],
  installHint: string
): ExecutionResult | null {
  const missing = commands.filter((c) => !commandExists(c));
  if (missing.length === 0) return null;
  return {
    stdout: "",
    stderr: `[环境缺失] 执行 ${language} 代码需要以下命令: ${missing.join(", ")}\n${installHint}`,
    exitCode: -1,
    executionTimeMs: 0,
  };
}

// --------------------------------------------------------------------------
// 各语言执行策略
// --------------------------------------------------------------------------

async function executePython(ctx: ExecutionContext): Promise<ExecutionResult> {
  const envErr = checkRuntime("Python", ["python3"], "请安装 Python 3: https://www.python.org/downloads/ 或运行 brew install python3");
  if (envErr) return envErr;
  const tmpDir = join(tmpdir(), `exec-python-${randomUUID()}`);
  await mkdir(tmpDir, { recursive: true });
  const file = join(tmpDir, "main.py");
  await writeFile(file, ctx.code, "utf-8");

  const start = Date.now();
  try {
    const res = await runProcess("python3", [file], {
      cwd: tmpDir,
      timeoutMs: ctx.timeout * 1000,
    });
    return { ...res, executionTimeMs: Date.now() - start };
  } finally {
    await rm(tmpDir, { recursive: true, force: true });
  }
}

async function executeJavaScript(ctx: ExecutionContext): Promise<ExecutionResult> {
  const tmpDir = join(tmpdir(), `exec-js-${randomUUID()}`);
  await mkdir(tmpDir, { recursive: true });
  const file = join(tmpDir, "main.js");
  await writeFile(file, ctx.code, "utf-8");

  const start = Date.now();
  try {
    const res = await runProcess("node", [file], {
      cwd: tmpDir,
      timeoutMs: ctx.timeout * 1000,
    });
    return { ...res, executionTimeMs: Date.now() - start };
  } finally {
    await rm(tmpDir, { recursive: true, force: true });
  }
}

async function executeTypeScript(ctx: ExecutionContext): Promise<ExecutionResult> {
  const tmpDir = join(tmpdir(), `exec-ts-${randomUUID()}`);
  await mkdir(tmpDir, { recursive: true });
  const file = join(tmpDir, "main.ts");
  await writeFile(file, ctx.code, "utf-8");

  const start = Date.now();
  try {
    const res = await runProcess("node", [TSX_BIN, file], {
      cwd: tmpDir,
      timeoutMs: ctx.timeout * 1000,
    });
    return { ...res, executionTimeMs: Date.now() - start };
  } finally {
    await rm(tmpDir, { recursive: true, force: true });
  }
}

async function executeJava(ctx: ExecutionContext): Promise<ExecutionResult> {
  const envErr = checkRuntime("Java", ["javac", "java"], "请安装 JDK: https://adoptium.net/ 或运行 brew install openjdk");
  if (envErr) return envErr;
  // Java 要求类名与文件名一致，统一使用 Main 类
  const tmpDir = join(tmpdir(), `exec-java-${randomUUID()}`);
  await mkdir(tmpDir, { recursive: true });
  const file = join(tmpDir, "Main.java");
  await writeFile(file, ctx.code, "utf-8");

  const start = Date.now();
  try {
    // 第一步：编译
    const compileRes = await runProcess("javac", ["Main.java"], {
      cwd: tmpDir,
      timeoutMs: ctx.timeout * 1000,
    });
    if (compileRes.exitCode !== 0) {
      return { ...compileRes, executionTimeMs: Date.now() - start };
    }

    // 第二步：运行（剩余超时时间）
    const elapsed = Date.now() - start;
    const remaining = ctx.timeout * 1000 - elapsed;
    if (remaining <= 0) {
      return {
        stdout: compileRes.stdout,
        stderr: compileRes.stderr + "\n[Compilation timed out]",
        exitCode: -1,
        executionTimeMs: elapsed,
      };
    }

    const runRes = await runProcess("java", ["Main"], {
      cwd: tmpDir,
      timeoutMs: remaining,
    });
    return {
      stdout: runRes.stdout,
      stderr: compileRes.stderr + runRes.stderr,
      exitCode: runRes.exitCode,
      executionTimeMs: Date.now() - start,
    };
  } finally {
    await rm(tmpDir, { recursive: true, force: true });
  }
}

async function executeShell(ctx: ExecutionContext): Promise<ExecutionResult> {
  const tmpDir = join(tmpdir(), `exec-shell-${randomUUID()}`);
  await mkdir(tmpDir, { recursive: true });
  const file = join(tmpDir, "main.sh");
  await writeFile(file, ctx.code, "utf-8");

  const start = Date.now();
  try {
    const res = await runProcess("bash", [file], {
      cwd: tmpDir,
      timeoutMs: ctx.timeout * 1000,
    });
    return { ...res, executionTimeMs: Date.now() - start };
  } finally {
    await rm(tmpDir, { recursive: true, force: true });
  }
}

// --------------------------------------------------------------------------
// 对外接口
// --------------------------------------------------------------------------

const EXECUTORS: Record<Language, (ctx: ExecutionContext) => Promise<ExecutionResult>> = {
  python: executePython,
  javascript: executeJavaScript,
  typescript: executeTypeScript,
  java: executeJava,
  shell: executeShell,
};

/**
 * 执行指定语言的代码，返回执行结果。
 */
export async function executeCode(ctx: ExecutionContext): Promise<ExecutionResult> {
  const executor = EXECUTORS[ctx.language];
  if (!executor) {
    throw new Error(`Unsupported language: ${ctx.language}`);
  }
  return executor(ctx);
}
