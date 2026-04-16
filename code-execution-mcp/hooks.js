/**
 * hooks.js — 用户自定义 Hook（调试入口）
 *
 * 此文件为用户预留的调试与定制入口，无需重新构建即可生效。
 * 直接编辑此文件，保存后重启服务即可应用修改。
 *
 * 两个 Hook 的调用时机：
 *   pre_hook  → 代码执行前，可修改/拦截执行上下文
 *   post_hook → 代码执行后，可修改/记录执行结果
 */

/**
 * pre_hook: 代码执行前调用。
 *
 * @param {Object} ctx              执行上下文
 * @param {string} ctx.language     编程语言：python | javascript | typescript | java | shell
 * @param {string} ctx.code         待执行的代码字符串
 * @param {number} ctx.timeout      超时时间（秒）
 *
 * @returns {Object} 返回（可修改的）上下文；throw 可中止本次执行并返回错误。
 *
 * 示例用途：
 *   - 打印执行信息用于调试
 *   - 替换/注入代码片段
 *   - 根据 language 禁用某些操作（直接 throw new Error(...)）
 */
export async function pre_hook(ctx) {
  // --- 调试示例（取消注释启用）---
  // console.error(`[pre_hook] language=${ctx.language}, codeLen=${ctx.code.length}`);

  // --- 拦截示例：禁止执行 shell 命令 ---
  // if (ctx.language === 'shell') {
  //   throw new Error('Shell execution is disabled by pre_hook.');
  // }

  // --- 代码注入示例：在 Python 代码末尾追加调试语句 ---
  // if (ctx.language === 'python') {
  //   ctx.code += '\nprint("[debug] execution finished")';
  // }

  return ctx;
}

/**
 * post_hook: 代码执行后调用。
 *
 * @param {Object} ctx                    执行上下文（同 pre_hook）
 * @param {Object} result                 执行结果
 * @param {string} result.stdout          标准输出
 * @param {string} result.stderr          标准错误
 * @param {number} result.exitCode        进程退出码（0 表示成功）
 * @param {number} result.executionTimeMs 执行耗时（毫秒）
 *
 * @returns {Object} 返回（可修改的）结果。
 *
 * 示例用途：
 *   - 记录执行日志
 *   - 过滤/脱敏输出内容
 *   - 在 stderr 非空时发送告警
 */
export async function post_hook(ctx, result) {
  // --- 调试示例（取消注释启用）---
  // console.error(
  //   `[post_hook] language=${ctx.language}, exitCode=${result.exitCode}, time=${result.executionTimeMs}ms`
  // );

  // --- 输出过滤示例：隐藏敏感关键词 ---
  // result.stdout = result.stdout.replace(/secret/gi, '***');

  return result;
}
