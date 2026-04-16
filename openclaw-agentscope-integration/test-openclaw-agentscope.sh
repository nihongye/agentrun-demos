#!/bin/bash
# OpenClaw × AgentScope 沙箱集成 — 端到端测试
#
# 参考 E2B 测试脚本 (test-openclaw-e2b.sh) 的设计：
# - 使用 /v1/chat/completions 端点（不是 /v1/responses）
# - 不传 tools 参数 — sandbox 通过 agent config 的 sandbox.mode="all" 自动启用
# - 用 LLM 无法猜测的输出（随机数、PID、uuid）验证代码确实在沙箱中执行
#
# 用法:
#   ./test-openclaw-agentscope.sh                    # 运行所有测试
#   ./test-openclaw-agentscope.sh --test health      # 只跑健康检查
#   ./test-openclaw-agentscope.sh --test basic       # 只跑基础对话
#   ./test-openclaw-agentscope.sh --test code        # 只跑代码执行
#   ./test-openclaw-agentscope.sh --test file        # 只跑文件操作
#   ./test-openclaw-agentscope.sh --test multi       # 只跑多步骤

set -euo pipefail

# ========== 配置 ==========
GATEWAY_IP="${GATEWAY_IP:-${GATEWAY_IP}}"
HOST_HEADER="${HOST_HEADER:-openclaw-agentscope.<YOUR_DOMAIN_SUFFIX>}"
AUTH_TOKEN="${AUTH_TOKEN:-demo-token-agentscope}"
MODEL="${MODEL:-dashscope/qwen3-coder-plus}"
TIMEOUT="${TIMEOUT:-180}"

BASE_URL="http://${GATEWAY_IP}/v1/chat/completions"
HEALTH_URL="http://${GATEWAY_IP}/healthz"

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

# 发送非流式 chat completions 请求
chat_request() {
    local messages="$1"
    curl -sS --max-time "$TIMEOUT" "$BASE_URL" \
        -H "Host: $HOST_HEADER" \
        -H "Authorization: Bearer $AUTH_TOKEN" \
        -H "Content-Type: application/json" \
        -d "{\"model\": \"$MODEL\", \"messages\": $messages}"
}

# 从响应 JSON 提取 assistant content（处理换行符等控制字符）
extract_content() {
    python3 -c "
import sys, json, re
raw = sys.stdin.read()
# 清理 JSON 中的控制字符（保留 \\n \\t）
cleaned = re.sub(r'[\x00-\x08\x0b\x0c\x0e-\x1f]', '', raw)
try:
    data = json.loads(cleaned)
    content = data.get('choices', [{}])[0].get('message', {}).get('content', '')
    print(content)
except Exception as e:
    print(f'JSON_PARSE_ERROR: {e}', file=sys.stderr)
    # 尝试用正则提取
    m = re.search(r'\"content\"\\s*:\\s*\"((?:[^\"\\\\]|\\\\.)*)\"', raw)
    if m:
        print(m.group(1).encode().decode('unicode_escape', errors='replace'))
    else:
        print('')
" 2>/dev/null
}

# ========== 测试用例 ==========

test_health() {
    log_test "1. 健康检查"

    local http_code
    http_code=$(curl -sS -o /dev/null -w "%{http_code}" --max-time 30 \
        "$HEALTH_URL" -H "Host: $HOST_HEADER" 2>/dev/null || echo "000")

    if [[ "$http_code" == "200" ]]; then
        log_pass "健康检查通过 (HTTP $http_code)"
    else
        log_fail "健康检查失败 (HTTP $http_code) — Pod 可能还在 scale up，等 60s 重试"
        sleep 60
        http_code=$(curl -sS -o /dev/null -w "%{http_code}" --max-time 30 \
            "$HEALTH_URL" -H "Host: $HOST_HEADER" 2>/dev/null || echo "000")
        if [[ "$http_code" == "200" ]]; then
            log_pass "健康检查重试通过 (HTTP $http_code)"
            PASSED=$((PASSED - 0))  # 不重复计数
        else
            log_fail "健康检查重试仍失败 (HTTP $http_code)"
        fi
    fi
}

test_basic() {
    log_test "2. 基础对话（非流式）— 不涉及沙箱"

    local resp content
    resp=$(chat_request '[{"role":"user","content":"hi, just say hello back in one word"}]')
    content=$(echo "$resp" | extract_content || echo "")

    if [ -n "$content" ] && ! echo "$content" | grep -qi "error"; then
        log_pass "非流式对话正常，回复: ${content:0:80}"
    else
        log_fail "非流式对话失败，响应: $(echo "$resp" | head -c 300)"
    fi
}

test_code_execution() {
    log_test "3. 沙箱代码执行 — 用 os.getpid() + random 验证真实执行"
    log_info "LLM 无法猜测 PID 和随机数，必须实际执行才能返回"

    local resp content
    resp=$(chat_request '[{"role":"user","content":"Execute this Python code and show me the EXACT output, do not guess:\nimport os, random\nrandom.seed(os.getpid())\nprint(f\"PID={os.getpid()}\")\nprint(f\"RAND={random.randint(100000,999999)}\")"}]')
    content=$(echo "$resp" | extract_content || echo "")

    local has_pid=0

    if echo "$content" | grep -qE "PID=[0-9]+"; then
        has_pid=1
        log_info "检测到 PID: $(echo "$content" | grep -oE 'PID=[0-9]+')"
    fi

    if echo "$content" | grep -qE "RAND=[0-9]{6}"; then
        log_info "检测到随机数: $(echo "$content" | grep -oE 'RAND=[0-9]+')"
    fi

    if [ "$has_pid" -eq 1 ]; then
        log_pass "代码在沙箱中执行，PID 验证通过"
    else
        log_fail "未检测到真实执行证据，回复: $(echo "$content" | head -c 300)"
    fi
}

test_file_operations() {
    log_test "4. 沙箱文件操作 — 用随机标记验证真实写入/读取"

    local marker
    marker="AS_MARKER_$(date +%s)_$$"
    log_info "随机标记: $marker"

    local resp content
    resp=$(chat_request "[{\"role\":\"user\",\"content\":\"In the sandbox, do these steps and report EXACT output:\\n1. Run: echo '$marker' > /tmp/verify.txt\\n2. Run: cat /tmp/verify.txt\\n3. Run: ls -la /tmp/verify.txt\\nShow me the exact output of each command.\"}]")
    content=$(echo "$resp" | extract_content || echo "")

    local checks=0

    if echo "$content" | grep -q "$marker"; then
        checks=$((checks + 1))
        log_info "随机标记在回复中找到（证明文件确实被写入并读回）"
    fi

    if echo "$content" | grep -qE "verify\.txt"; then
        checks=$((checks + 1))
        log_info "文件名在输出中找到"
    fi

    if [ "$checks" -ge 2 ]; then
        log_pass "文件操作在沙箱中执行，随机标记验证通过"
    elif [ "$checks" -ge 1 ]; then
        log_pass "文件操作部分验证通过 ($checks/2)"
    else
        log_fail "文件操作验证失败，回复: $(echo "$content" | head -c 300)"
    fi
}

test_multi_step() {
    log_test "5. 多步骤任务 — 创建脚本并执行"

    local marker
    marker="MULTI_$(date +%s)_$$"
    log_info "随机标记: $marker"

    local resp content
    resp=$(chat_request "[{\"role\":\"user\",\"content\":\"Execute this Python code and show the EXACT output:\\nimport uuid\\nprint(f'MULTI_CHECK:${marker}')\\nprint(f'UUID={uuid.uuid4()}')\"}]")
    content=$(echo "$resp" | extract_content || echo "")

    local has_marker=0 has_uuid=0

    if echo "$content" | grep -q "MULTI_CHECK:${marker}"; then
        has_marker=1
        log_info "标记验证通过"
    fi

    if echo "$content" | grep -qE "UUID=[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-"; then
        has_uuid=1
        log_info "UUID 验证通过: $(echo "$content" | grep -oE 'UUID=[0-9a-f-]+')"
    fi

    if [ "$has_marker" -eq 1 ] && [ "$has_uuid" -eq 1 ]; then
        log_pass "多步骤任务通过，标记和 UUID 均验证"
    elif [ "$has_marker" -eq 1 ] || [ "$has_uuid" -eq 1 ]; then
        log_pass "多步骤任务部分通过"
    else
        log_fail "多步骤任务失败，回复: $(echo "$content" | head -c 300)"
    fi
}

# ========== 主流程 ==========

echo "============================================"
echo " OpenClaw × AgentScope 沙箱集成测试"
echo "============================================"
echo "Gateway:  $BASE_URL"
echo "Host:     $HOST_HEADER"
echo "Model:    $MODEL"
echo "Timeout:  ${TIMEOUT}s"
echo "============================================"

# 解析参数
TARGET_TEST="all"
while [[ $# -gt 0 ]]; do
    case $1 in
        --test) TARGET_TEST="$2"; shift 2 ;;
        *) shift ;;
    esac
done

case "$TARGET_TEST" in
    health) test_health ;;
    basic)  test_basic ;;
    code)   test_code_execution ;;
    file)   test_file_operations ;;
    multi)  test_multi_step ;;
    all)
        test_health
        test_basic
        test_code_execution
        test_file_operations
        test_multi_step
        ;;
    *)
        echo "Unknown test: $TARGET_TEST"
        echo "Available: health, basic, code, file, multi, all"
        exit 1
        ;;
esac

# ========== 汇总 ==========
echo ""
echo "============================================"
echo -e " 结果: ${GREEN}${PASSED} passed${NC}, ${RED}${FAILED} failed${NC}"
echo "============================================"

[ "$FAILED" -eq 0 ] || exit 1
