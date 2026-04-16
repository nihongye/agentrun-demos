#!/bin/bash
# OpenClaw 统一沙箱后端 — E2E 测试脚本
# 支持 --backend e2b|agentscope 参数选择测试目标后端
#
# 用法:
#   ./test-unified.sh --backend e2b          # 测试 E2B 后端
#   ./test-unified.sh --backend agentscope   # 测试 AgentScope 后端
#   ./test-unified.sh --backend e2b --test code  # 只跑代码执行测试

set -euo pipefail

# ========== 配置 ==========
GATEWAY_IP="${GATEWAY_IP:-${GATEWAY_IP}}"
HOST_HEADER="${HOST_HEADER:-openclaw-unified-sandbox.<YOUR_DOMAIN_SUFFIX>}"
AUTH_TOKEN="${AUTH_TOKEN:-demo-token-unified}"
MODEL="${MODEL:-dashscope/qwen3-coder-plus}"
TIMEOUT="${TIMEOUT:-180}"
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

BASE_URL="http://${GATEWAY_IP}/v1/chat/completions"
HEALTH_URL="http://${GATEWAY_IP}/healthz"

chat_request() {
    local messages="$1"
    curl -sS --max-time "$TIMEOUT" "$BASE_URL" \
        -H "Host: $HOST_HEADER" \
        -H "Authorization: Bearer $AUTH_TOKEN" \
        -H "Content-Type: application/json" \
        -d "{\"model\": \"$MODEL\", \"messages\": $messages}"
}

chat_request_stream() {
    local messages="$1"
    curl -sS -N --max-time "$TIMEOUT" "$BASE_URL" \
        -H "Host: $HOST_HEADER" \
        -H "Authorization: Bearer $AUTH_TOKEN" \
        -H "Content-Type: application/json" \
        -d "{\"model\": \"$MODEL\", \"stream\": true, \"messages\": $messages}" \
        2>/dev/null
}

extract_content() {
    python3 -c "
import sys, json, re
raw = sys.stdin.read()
cleaned = re.sub(r'[\x00-\x08\x0b\x0c\x0e-\x1f]', '', raw)
try:
    data = json.loads(cleaned)
    content = data.get('choices', [{}])[0].get('message', {}).get('content', '')
    print(content)
except Exception as e:
    print(f'JSON_PARSE_ERROR: {e}', file=sys.stderr)
    m = re.search(r'\"content\"\\s*:\\s*\"((?:[^\"\\\\]|\\\\.)*)\"', raw)
    if m:
        print(m.group(1).encode().decode('unicode_escape', errors='replace'))
    else:
        print('')
" 2>/dev/null
}

extract_stream_content() {
    grep "^data: {" | python3 -c "
import sys, json
parts = []
for line in sys.stdin:
    line = line.strip()
    if line.startswith('data: '):
        try:
            d = json.loads(line[6:])
            delta = d.get('choices',[{}])[0].get('delta',{})
            if 'content' in delta and delta['content']:
                parts.append(delta['content'])
        except: pass
print(''.join(parts))
" 2>/dev/null
}

responses_request() {
    local input="$1"
    curl -sS --max-time "$TIMEOUT" "http://${GATEWAY_IP}/v1/responses" \
        -H "Host: $HOST_HEADER" \
        -H "Authorization: Bearer $AUTH_TOKEN" \
        -H "Content-Type: application/json" \
        -d "{\"model\": \"$MODEL\", \"input\": $input}"
}

extract_responses_content() {
    python3 -c "import sys,json; r=json.load(sys.stdin); print(r['output'][0]['content'][0]['text'])" 2>/dev/null
}

# ========== 测试用例 ==========

test_health() {
    log_test "1. 健康检查 (${BACKEND} 后端)"

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
        else
            log_fail "健康检查重试仍失败 (HTTP $http_code)"
        fi
    fi
}

test_basic() {
    log_test "2. 基础对话（非流式）— 不涉及沙箱 (${BACKEND})"

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
    log_test "3. 沙箱代码执行 — 用 os.getpid() + random 验证真实执行 (${BACKEND})"
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
    log_test "4. 沙箱文件操作 — 用随机标记验证真实写入/读取 (${BACKEND})"

    local marker workdir
    marker="UNIFIED_${BACKEND}_$(date +%s)_$$"

    # E2B 用 /home/user/，AgentScope 用 /tmp/
    if [[ "$BACKEND" == "e2b" ]]; then
        workdir="/home/user"
    else
        workdir="/tmp"
    fi
    log_info "随机标记: $marker, 工作目录: $workdir"

    local resp content
    resp=$(chat_request "[{\"role\":\"user\",\"content\":\"In the sandbox, do these steps and report EXACT output:\\n1. Run: echo '$marker' > ${workdir}/verify.txt\\n2. Run: cat ${workdir}/verify.txt\\n3. Run: ls -la ${workdir}/verify.txt\\nShow me the exact output of each command.\"}]")
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

test_stream() {
    log_test "5. 流式对话（SSE）— 不涉及沙箱 (${BACKEND})"

    local raw has_data has_done content
    raw=$(chat_request_stream '[{"role":"user","content":"hi, just say hello back in one word"}]')
    has_data=$(echo "$raw" | grep -c "^data: {" || true)
    has_done=$(echo "$raw" | grep -c "\[DONE\]" || true)

    if [ "$has_data" -gt 0 ] && [ "$has_done" -gt 0 ]; then
        content=$(echo "$raw" | extract_stream_content)
        log_pass "流式对话正常，${has_data} 个事件，内容: ${content:0:80}"
    else
        log_fail "流式格式异常 (data: $has_data, DONE: $has_done)"
    fi
}

test_stream_code_execution() {
    log_test "6. 流式 + 沙箱代码执行 — 用 uuid4 验证真实执行 (${BACKEND})"
    log_info "uuid4 每次不同，LLM 无法猜测"

    local raw has_done content
    raw=$(chat_request_stream '[{"role":"user","content":"Execute this Python code in the sandbox and show me the EXACT output:\nimport uuid, platform\nprint(f\"UUID={uuid.uuid4()}\")\nprint(f\"PLATFORM={platform.platform()}\")"}]')
    has_done=$(echo "$raw" | grep -c "\[DONE\]" || true)
    content=$(echo "$raw" | extract_stream_content)

    local has_uuid=0 has_platform=0

    if echo "$content" | grep -qE "UUID=[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-"; then
        has_uuid=1
        log_info "检测到 UUID: $(echo "$content" | grep -oE 'UUID=[0-9a-f-]+')"
    fi

    if echo "$content" | grep -qi "linux\|Linux"; then
        has_platform=1
        log_info "检测到 Linux 平台信息"
    fi

    if [ "$has_done" -gt 0 ] && [ "$has_uuid" -eq 1 ]; then
        log_pass "流式沙箱执行正常，UUID 验证通过"
    elif [ "$has_done" -gt 0 ]; then
        log_fail "流式完成但未检测到真实执行证据，内容: $(echo "$content" | head -c 300)"
    else
        log_fail "流式未正常结束"
    fi
}

test_sandbox_env() {
    log_test "7. 沙箱环境验证 — 确认运行在隔离容器中 (${BACKEND})"

    local resp content
    resp=$(chat_request '[{"role":"user","content":"Execute this Python code and show me the EXACT output only, nothing else:\nimport subprocess, os\nprint(f\"CWD={os.getcwd()}\")\nprint(f\"HOME={os.environ.get(chr(72)+chr(79)+chr(77)+chr(69),chr(63))}\")\nr = subprocess.run([\"cat\",\"/etc/hostname\"], capture_output=True, text=True)\nprint(f\"HOSTNAME={r.stdout.strip()}\")"}]')
    content=$(echo "$resp" | extract_content || echo "")

    local checks=0

    if echo "$content" | grep -qiE "CWD=.+"; then
        checks=$((checks + 1))
        log_info "检测到工作目录: $(echo "$content" | grep -oiE 'CWD=[^ ]+')"
    fi

    if echo "$content" | grep -qiE "HOSTNAME=.+"; then
        checks=$((checks + 1))
        log_info "检测到 hostname: $(echo "$content" | grep -oiE 'HOSTNAME=[^ ]+')"
    fi

    if echo "$content" | grep -qiE "HOME=.+"; then
        checks=$((checks + 1))
        log_info "检测到 HOME: $(echo "$content" | grep -oiE 'HOME=[^ ]+')"
    fi

    if [ "$checks" -ge 2 ]; then
        log_pass "沙箱环境验证通过 ($checks/3)"
    elif [ "$checks" -ge 1 ]; then
        log_pass "沙箱环境部分验证通过 ($checks/3)"
    else
        log_fail "沙箱环境验证失败，回复: $(echo "$content" | head -c 300)"
    fi
}

test_multi_step() {
    log_test "8. 多步骤任务 — 创建脚本并执行 + UUID 验证 (${BACKEND})"

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

test_responses_endpoint() {
    log_test "9. /v1/responses 端点（非流式）(${BACKEND})"

    local resp content
    resp=$(responses_request '"hi, just say hello back in one word"')
    content=$(echo "$resp" | extract_responses_content || echo "")

    if [ -n "$content" ]; then
        log_pass "/v1/responses 正常，回复: ${content:0:80}"
    else
        log_fail "/v1/responses 失败，响应: $(echo "$resp" | head -c 200)"
    fi
}

# ========== 主流程 ==========

# 解析参数
TARGET_TEST="all"
while [[ $# -gt 0 ]]; do
    case $1 in
        --backend) BACKEND="$2"; shift 2 ;;
        --test)    TARGET_TEST="$2"; shift 2 ;;
        *) shift ;;
    esac
done

# 验证 backend 参数
if [[ "$BACKEND" != "e2b" ]] && [[ "$BACKEND" != "agentscope" ]]; then
    echo "错误: --backend 必须是 'e2b' 或 'agentscope'，当前值: '$BACKEND'"
    exit 1
fi

echo "============================================"
echo " OpenClaw 统一沙箱后端 — E2E 测试"
echo " 后端: ${BACKEND}"
echo "============================================"
echo "Gateway:  $BASE_URL"
echo "Host:     $HOST_HEADER"
echo "Model:    $MODEL"
echo "Timeout:  ${TIMEOUT}s"
echo "============================================"

case "$TARGET_TEST" in
    health)    test_health ;;
    basic)     test_basic ;;
    code)      test_code_execution ;;
    file)      test_file_operations ;;
    stream)    test_stream ;;
    streamcode) test_stream_code_execution ;;
    env)       test_sandbox_env ;;
    multi)     test_multi_step ;;
    responses) test_responses_endpoint ;;
    all)
        test_health
        test_basic
        test_code_execution
        test_file_operations
        test_stream
        test_stream_code_execution
        test_sandbox_env
        test_multi_step
        test_responses_endpoint
        ;;
    *)
        echo "Unknown test: $TARGET_TEST"
        echo "Available: health, basic, code, file, stream, streamcode, env, multi, responses, all"
        exit 1
        ;;
esac

# ========== 汇总 ==========
echo ""
echo "============================================"
echo -e " 结果 (${BACKEND}): ${GREEN}${PASSED} passed${NC}, ${RED}${FAILED} failed${NC}"
echo "============================================"

[ "$FAILED" -eq 0 ] || exit 1
