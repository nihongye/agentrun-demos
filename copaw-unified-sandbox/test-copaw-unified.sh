#!/bin/bash
# CoPaw 统一沙箱后端 — E2E 测试脚本
# 支持 --backend e2b|agentscope 参数选择测试目标后端
#
# 用法:
#   ./test-copaw-unified.sh --backend e2b          # 测试 E2B 后端
#   ./test-copaw-unified.sh --backend agentscope   # 测试 AgentScope 后端
#   ./test-copaw-unified.sh --backend e2b --test code  # 只跑代码执行测试

set -euo pipefail

# ========== 配置 ==========
GATEWAY_IP="${GATEWAY_IP:-${GATEWAY_IP}}"
HOST_HEADER="${HOST_HEADER:-copaw-unified-sandbox.<YOUR_DOMAIN_SUFFIX>}"
COPAW_API_KEY="${COPAW_API_KEY:-${COPAW_API_KEY}}"
TIMEOUT="${TIMEOUT:-120}"
BACKEND="e2b"

# ========== 颜色 ==========
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
NC='\033[0m'

PASSED=0
FAILED=0

# ========== 工具函数 ==========
log_test() { echo -e "\n${YELLOW}[TEST]${NC} $1"; }
log_pass() { echo -e "${GREEN}[PASS]${NC} $1"; PASSED=$((PASSED + 1)); }
log_fail() { echo -e "${RED}[FAIL]${NC} $1"; FAILED=$((FAILED + 1)); }
log_info() { echo -e "${CYAN}[INFO]${NC} $1"; }

BASE_URL="http://${GATEWAY_IP}/api/agent/process"
HEALTH_URL="http://${GATEWAY_IP}/api/version"

# 生成随机令牌
RAND_TOKEN=$(openssl rand -hex 8)
RAND_NUM_A=$((RANDOM * 1000 + RANDOM))
RAND_NUM_B=$((RANDOM * 1000 + RANDOM))
RAND_SUM=$((RAND_NUM_A + RAND_NUM_B))

# 发送 CoPaw 请求（SSE 流式）
send_request() {
    local message="$1"
    local session_id="test-unified-${BACKEND}-$(date +%s)-${RANDOM}"
    curl -sS -N --max-time "$TIMEOUT" "${BASE_URL}" \
        -H "Host: ${HOST_HEADER}" \
        -H "Authorization: Bearer ${COPAW_API_KEY}" \
        -H "Content-Type: application/json" \
        -d "{
            \"input\": [{\"role\": \"user\", \"content\": [{\"type\": \"text\", \"text\": \"${message}\"}]}],
            \"session_id\": \"${session_id}\"
        }" 2>&1
}

# 从 SSE 响应中提取文本和工具输出
extract_text() {
    python3 -c "
import sys, json
parts = []
for line in sys.stdin:
    line = line.strip()
    if not line.startswith('data:'): continue
    try:
        d = json.loads(line[5:])
        t = d.get('text', '')
        if t: parts.append(t)
        o = d.get('data', {}).get('output', '') if isinstance(d.get('data'), dict) else ''
        if o: parts.append(o)
    except: pass
print(''.join(parts))
" 2>/dev/null
}

# ========== 测试用例 ==========

test_health() {
    log_test "1. 健康检查 (${BACKEND} 后端)"
    local http_code
    http_code=$(curl -sS -o /dev/null -w "%{http_code}" --max-time 10 \
        "${HEALTH_URL}" -H "Host: ${HOST_HEADER}" 2>/dev/null || echo "000")

    if [[ "$http_code" == "200" ]]; then
        log_pass "健康检查通过 (HTTP $http_code)"
    else
        log_fail "健康检查失败 (HTTP $http_code) — Pod 可能还在 scale up，等 60s 重试"
        sleep 60
        http_code=$(curl -sS -o /dev/null -w "%{http_code}" --max-time 10 \
            "${HEALTH_URL}" -H "Host: ${HOST_HEADER}" 2>/dev/null || echo "000")
        if [[ "$http_code" == "200" ]]; then
            log_pass "健康检查重试通过 (HTTP $http_code)"
        else
            log_fail "健康检查重试仍失败 (HTTP $http_code)"
        fi
    fi
}

test_auth() {
    log_test "2. 认证校验 (${BACKEND})"
    local http_code
    http_code=$(curl -sS -o /dev/null -w "%{http_code}" --max-time 10 \
        "${BASE_URL}" \
        -H "Host: ${HOST_HEADER}" \
        -H "Authorization: Bearer wrong-token" \
        -H "Content-Type: application/json" \
        -d '{"session_id":"auth-test","input":[{"role":"user","content":[{"type":"text","text":"hi"}]}]}' \
        2>/dev/null || echo "000")

    if [[ "$http_code" == "401" || "$http_code" == "403" ]]; then
        log_pass "错误 Token 被拒绝 (HTTP $http_code)"
    else
        log_fail "认证校验异常 (HTTP $http_code, 期望 401/403)"
    fi
}

test_python() {
    log_test "3. Python 代码执行 — 随机令牌验证 (${BACKEND})"
    local token
    token=$(openssl rand -hex 8)
    log_info "随机令牌: ${token}"

    local response response_text
    response=$(send_request "请直接调用execute_python_code工具执行这段代码，只执行不解释，不要自己回答：print('SANDBOX_OUTPUT:${token}')")
    response_text=$(echo "$response" | extract_text)

    if echo "$response" | grep -q "SANDBOX_OUTPUT:${token}"; then
        log_pass "Python 执行: 找到 SANDBOX_OUTPUT:${token}"
    else
        log_fail "Python 执行: 未找到 SANDBOX_OUTPUT:${token}"
        log_info "响应片段: ${response_text:0:300}"
    fi
}

test_shell() {
    log_test "4. Shell 命令执行 — 随机令牌验证 (${BACKEND})"
    local token
    token=$(openssl rand -hex 8)
    log_info "随机令牌: ${token}"

    local response response_text
    response=$(send_request "请直接调用execute_shell_command工具执行：echo 'SHELL_OUTPUT:${token}'，只执行不解释，不要自己回答")
    response_text=$(echo "$response" | extract_text)

    if echo "$response" | grep -q "SHELL_OUTPUT:${token}"; then
        log_pass "Shell 执行: 找到 SHELL_OUTPUT:${token}"
    else
        log_fail "Shell 执行: 未找到 SHELL_OUTPUT:${token}"
        log_info "响应片段: ${response_text:0:300}"
    fi
}

test_calc() {
    log_test "5. Python 计算 — 随机大数加法 (${BACKEND})"
    log_info "计算: ${RAND_NUM_A} + ${RAND_NUM_B} = ${RAND_SUM}"

    local response response_text
    response=$(send_request "请直接调用execute_python_code工具执行：print(${RAND_NUM_A}+${RAND_NUM_B})，只执行不解释，不要自己回答")
    response_text=$(echo "$response" | extract_text)

    if echo "$response" | grep -q "${RAND_SUM}"; then
        log_pass "Python 计算: ${RAND_NUM_A}+${RAND_NUM_B}=${RAND_SUM}"
    else
        log_fail "Python 计算: 未找到 ${RAND_SUM}"
        log_info "响应片段: ${response_text:0:300}"
    fi
}

test_multiline() {
    log_test "6. 多行代码执行 (${BACKEND})"
    local token
    token=$(openssl rand -hex 8)
    log_info "随机令牌: ${token}"

    local response response_text
    response=$(send_request "请直接调用execute_python_code工具执行以下代码，只执行不解释，不要自己回答：\nimport sys\nprint(f'PYVER:{sys.version_info.major}.{sys.version_info.minor}')\nprint('MULTILINE_OK:${token}')")
    response_text=$(echo "$response" | extract_text)

    if echo "$response" | grep -q "MULTILINE_OK:${token}"; then
        log_pass "多行代码: 找到 MULTILINE_OK:${token}"
    else
        log_fail "多行代码: 未找到 MULTILINE_OK:${token}"
        log_info "响应片段: ${response_text:0:300}"
    fi
}

test_read_file() {
    log_test "7. 文件读取 — sandbox_read_file (${BACKEND})"
    local token
    token=$(openssl rand -hex 8)
    log_info "随机令牌: ${token}"

    local response response_text
    response=$(send_request "请直接按顺序调用工具，只执行不解释，不要自己回答：1.调用execute_shell_command执行 echo FILE_READ_TOKEN:${token} > /tmp/test_read_${token}.txt ，2.再调用sandbox_read_file读取/tmp/test_read_${token}.txt内容")
    response_text=$(echo "$response" | extract_text)

    if echo "$response" | grep -q "FILE_READ_TOKEN:${token}"; then
        log_pass "文件读取: 找到 FILE_READ_TOKEN:${token}"
    else
        log_fail "文件读取: 未找到 FILE_READ_TOKEN:${token}"
        log_info "响应片段: ${response_text:0:300}"
    fi
}

test_write_file() {
    log_test "8. 文件写入 — sandbox_write_file (${BACKEND})"
    local token
    token=$(openssl rand -hex 8)
    log_info "随机令牌: ${token}"

    local response response_text
    response=$(send_request "请直接按顺序调用工具，只执行不解释，不要自己回答：1.调用sandbox_write_file写入文件/tmp/test_write_${token}.txt内容为FILE_WRITE_TOKEN:${token}，2.再调用sandbox_read_file读取/tmp/test_write_${token}.txt")
    response_text=$(echo "$response" | extract_text)

    if echo "$response" | grep -q "FILE_WRITE_TOKEN:${token}"; then
        log_pass "文件写入: 找到 FILE_WRITE_TOKEN:${token}"
    else
        log_fail "文件写入: 未找到 FILE_WRITE_TOKEN:${token}"
        log_info "响应片段: ${response_text:0:300}"
    fi
}

test_list_files() {
    log_test "9. 列目录 — sandbox_list_files (${BACKEND})"
    local token
    token=$(openssl rand -hex 8)
    local rand_filename="listcheck_${token}.txt"
    log_info "随机文件名: ${rand_filename}"

    local response response_text
    response=$(send_request "请直接按顺序调用工具，只执行不解释，不要自己回答：1.调用execute_shell_command执行 touch /tmp/${rand_filename} ，2.再调用sandbox_list_files列出/tmp目录")
    response_text=$(echo "$response" | extract_text)

    if echo "$response" | grep -q "${rand_filename}"; then
        log_pass "列目录: 找到 ${rand_filename}"
    elif echo "$response" | grep -q "${token}"; then
        log_pass "列目录: 找到随机令牌 ${token}"
    else
        log_fail "列目录: 未找到 ${rand_filename}"
        log_info "响应片段: ${response_text:0:300}"
    fi
}

# ========== 主流程 ==========

TARGET_TEST="all"
while [[ $# -gt 0 ]]; do
    case $1 in
        --backend) BACKEND="$2"; shift 2 ;;
        --test)    TARGET_TEST="$2"; shift 2 ;;
        *) shift ;;
    esac
done

if [[ "$BACKEND" != "e2b" ]] && [[ "$BACKEND" != "agentscope" ]]; then
    echo "错误: --backend 必须是 'e2b' 或 'agentscope'，当前值: '$BACKEND'"
    exit 1
fi

echo "============================================"
echo " CoPaw 统一沙箱后端 — E2E 测试"
echo " 后端: ${BACKEND}"
echo "============================================"
echo "Gateway:  http://${GATEWAY_IP}"
echo "Host:     ${HOST_HEADER}"
echo "Timeout:  ${TIMEOUT}s"
echo "============================================"

case "$TARGET_TEST" in
    health)    test_health ;;
    auth)      test_auth ;;
    python)    test_python ;;
    shell)     test_shell ;;
    calc)      test_calc ;;
    multiline) test_multiline ;;
    read)      test_read_file ;;
    write)     test_write_file ;;
    list)      test_list_files ;;
    all)
        test_health
        test_auth
        test_python
        test_shell
        test_calc
        test_multiline
        test_read_file
        test_write_file
        test_list_files
        ;;
    *)
        echo "Unknown test: $TARGET_TEST"
        echo "Available: health, auth, python, shell, calc, multiline, read, write, list, all"
        exit 1
        ;;
esac

# ========== 汇总 ==========
echo ""
echo "============================================"
echo -e " 结果 (${BACKEND}): ${GREEN}${PASSED} passed${NC}, ${RED}${FAILED} failed${NC}"
echo "============================================"

[ "$FAILED" -eq 0 ] || exit 1
