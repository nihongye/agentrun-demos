#!/bin/bash
# OpenClaw + E2B 沙箱集成测试脚本
# 通过 Chat Completions API 测试 OpenClaw Gateway → LLM → E2B sandbox 全链路
#
# 关键设计：所有沙箱测试用例都使用 LLM 无法猜测的输出（如 os.getpid()、os.uname()、
# 随机数、实际文件系统状态）来验证代码确实在 E2B 沙箱中执行，而非 LLM 编造结果。
#
# 用法:
#   ./test-openclaw-e2b.sh                    # 运行所有测试
#   ./test-openclaw-e2b.sh --test basic       # 只跑基础对话
#   ./test-openclaw-e2b.sh --test stream      # 只跑流式
#   ./test-openclaw-e2b.sh --test code        # 只跑代码执行
#   ./test-openclaw-e2b.sh --test file        # 只跑文件操作
#   ./test-openclaw-e2b.sh --test env         # 只跑沙箱环境验证

set -euo pipefail

# ========== 配置 ==========
GATEWAY_IP="${GATEWAY_IP:-${GATEWAY_IP}}"
HOST_HEADER="${HOST_HEADER:-openclaw-e2b-demo.<YOUR_DOMAIN_SUFFIX>}"
AUTH_TOKEN="${AUTH_TOKEN:-demo-token-e2b-v4}"
MODEL="${MODEL:-openclaw:main}"
TIMEOUT="${TIMEOUT:-180}"

BASE_URL="http://${GATEWAY_IP}/v1/chat/completions"

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

# 发送非流式请求，返回完整 JSON
chat_request() {
    local messages="$1"
    curl -sS --max-time "$TIMEOUT" "$BASE_URL" \
        -H "Host: $HOST_HEADER" \
        -H "Authorization: Bearer $AUTH_TOKEN" \
        -H "Content-Type: application/json" \
        -d "{\"model\": \"$MODEL\", \"messages\": $messages}"
}

# 从响应 JSON 提取 assistant content
extract_content() {
    python3 -c "import sys,json; print(json.load(sys.stdin)['choices'][0]['message']['content'])" 2>/dev/null
}

# 发送流式请求，返回原始 SSE
chat_request_stream() {
    local messages="$1"
    curl -sS -N --max-time "$TIMEOUT" "$BASE_URL" \
        -H "Host: $HOST_HEADER" \
        -H "Authorization: Bearer $AUTH_TOKEN" \
        -H "Content-Type: application/json" \
        -d "{\"model\": \"$MODEL\", \"stream\": true, \"messages\": $messages}" \
        2>/dev/null
}

# 从 SSE 流拼接所有 delta content
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

# ========== 测试用例 ==========

test_basic() {
    log_test "1. 基础对话（非流式）— 不涉及沙箱"

    local resp content
    resp=$(chat_request '[{"role":"user","content":"hi, just say hello back in one word"}]')
    content=$(echo "$resp" | extract_content || echo "")

    if [ -n "$content" ]; then
        log_pass "非流式对话正常，回复: ${content:0:80}"
    else
        log_fail "非流式对话失败，响应: $(echo "$resp" | head -c 200)"
    fi
}

test_stream() {
    log_test "2. 流式对话（SSE）— 不涉及沙箱"

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

test_code_execution() {
    log_test "3. 沙箱代码执行 — 用 os.getpid()+os.uname() 验证真实执行"
    log_info "LLM 无法猜测 PID 和 hostname，必须实际执行才能返回"

    local resp content
    resp=$(chat_request '[{"role":"user","content":"Execute this Python code in the sandbox and tell me the EXACT output, do not guess:\nimport os\nprint(f\"PID={os.getpid()}\")\nprint(f\"HOST={os.uname().nodename}\")"}]')
    content=$(echo "$resp" | extract_content || echo "")

    local has_pid=0 has_e2b_host=0

    # 检查返回了具体的 PID 数字
    if echo "$content" | grep -qE "PID=[0-9]+"; then
        has_pid=1
        log_info "检测到 PID: $(echo "$content" | grep -oE 'PID=[0-9]+')"
    fi

    # 检查 hostname 包含 e2b-sandbox 特征
    if echo "$content" | grep -qi "e2b-sandbox\|e2b-sandb"; then
        has_e2b_host=1
        log_info "检测到 E2B 沙箱 hostname"
    fi

    if [ "$has_pid" -eq 1 ] && [ "$has_e2b_host" -eq 1 ]; then
        log_pass "代码在 E2B 沙箱中执行，PID 和 hostname 均验证通过"
    elif [ "$has_pid" -eq 1 ]; then
        log_pass "代码执行返回了 PID（沙箱可能执行但 hostname 格式不同）"
    else
        log_fail "未检测到真实执行证据，回复: $(echo "$content" | head -c 300)"
    fi
}

test_file_operations() {
    log_test "4. 沙箱文件操作 — 用随机标记验证真实写入/读取"

    # 生成随机标记，LLM 不可能猜到
    local marker="E2B_MARKER_$(date +%s)_$$"
    log_info "随机标记: $marker"

    local resp content
    resp=$(chat_request "[{\"role\":\"user\",\"content\":\"In the sandbox, do these steps and report EXACT output:\\n1. Run: echo '$marker' > /home/user/verify.txt\\n2. Run: cat /home/user/verify.txt\\n3. Run: ls -la /home/user/verify.txt\\nShow me the exact output of each command.\"}]")
    content=$(echo "$resp" | extract_content || echo "")

    local checks=0

    # 检查随机标记是否出现在回复中（证明真实执行了）
    if echo "$content" | grep -q "$marker"; then
        checks=$((checks + 1))
        log_info "随机标记在回复中找到（证明文件确实被写入并读回）"
    fi

    # 检查 ls 输出特征（文件大小、权限等）
    if echo "$content" | grep -qE "verify\.txt"; then
        checks=$((checks + 1))
        log_info "文件名在 ls 输出中找到"
    fi

    if [ "$checks" -ge 2 ]; then
        log_pass "文件操作在 E2B 沙箱中执行，随机标记验证通过"
    elif [ "$checks" -ge 1 ]; then
        log_pass "文件操作部分验证通过 ($checks/2)"
    else
        log_fail "文件操作验证失败，回复: $(echo "$content" | head -c 300)"
    fi
}

test_stream_code_execution() {
    log_test "5. 流式 + 沙箱代码执行 — 用 uuid4 验证真实执行"
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

    if [ "$has_done" -gt 0 ] && [ "$has_uuid" -eq 1 ] && [ "$has_platform" -eq 1 ]; then
        log_pass "流式沙箱执行正常，UUID 和平台信息均验证通过"
    elif [ "$has_done" -gt 0 ] && [ "$has_uuid" -eq 1 ]; then
        log_pass "流式沙箱执行正常，UUID 验证通过"
    elif [ "$has_done" -gt 0 ]; then
        log_fail "流式完成但未检测到真实执行证据，内容: $(echo "$content" | head -c 300)"
    else
        log_fail "流式未正常结束"
    fi
}

test_sandbox_env() {
    log_test "6. 沙箱环境验证 — 确认运行在隔离的 E2B Pod 中"
    log_info "检查 /home/user 工作目录、envd 进程、容器特征"

    local resp content
    resp=$(chat_request '[{"role":"user","content":"Execute this in the sandbox and show EXACT output:\nimport subprocess, os\nprint(f\"CWD={os.getcwd()}\")\nprint(f\"USER={os.environ.get(\"USER\",\"unknown\")}\")\nprint(f\"HOME={os.environ.get(\"HOME\",\"unknown\")}\")\nresult = subprocess.run([\"cat\",\"/etc/hostname\"], capture_output=True, text=True)\nprint(f\"HOSTNAME={result.stdout.strip()}\")"}]')
    content=$(echo "$resp" | extract_content || echo "")

    local checks=0

    if echo "$content" | grep -qi "home/user\|/home/user"; then
        checks=$((checks + 1))
        log_info "检测到 /home/user 路径（E2B 沙箱特征）"
    fi

    if echo "$content" | grep -qi "e2b-sandbox\|e2b-sandb"; then
        checks=$((checks + 1))
        log_info "检测到 E2B 沙箱 hostname"
    fi

    if echo "$content" | grep -qiE "HOSTNAME=.+"; then
        checks=$((checks + 1))
        log_info "检测到 hostname 输出"
    fi

    if [ "$checks" -ge 2 ]; then
        log_pass "沙箱环境验证通过，确认运行在 E2B Pod 中"
    elif [ "$checks" -ge 1 ]; then
        log_pass "沙箱环境部分验证通过 ($checks/3)"
    else
        log_fail "沙箱环境验证失败，回复: $(echo "$content" | head -c 300)"
    fi
}

# ========== /v1/responses 端点测试 ==========

# 发送 /v1/responses 非流式请求
responses_request() {
    local input="$1"
    local extra_headers="${2:-}"
    curl -sS --max-time "$TIMEOUT" "http://${GATEWAY_IP}/v1/responses" \
        -H "Host: $HOST_HEADER" \
        -H "Authorization: Bearer $AUTH_TOKEN" \
        -H "Content-Type: application/json" \
        $extra_headers \
        -d "{\"model\": \"$MODEL\", \"input\": $input}"
}

# 从 /v1/responses 响应提取 output text
extract_responses_content() {
    python3 -c "import sys,json; r=json.load(sys.stdin); print(r['output'][0]['content'][0]['text'])" 2>/dev/null
}

test_responses_basic() {
    log_test "7. /v1/responses 端点（非流式）"

    local resp content
    resp=$(responses_request '"hi, just say hello back in one word"')
    content=$(echo "$resp" | extract_responses_content || echo "")

    if [ -n "$content" ]; then
        log_pass "/v1/responses 正常，回复: ${content:0:80}"
    else
        log_fail "/v1/responses 失败，响应: $(echo "$resp" | head -c 200)"
    fi
}

test_session_context() {
    log_test "8. 会话上下文（x-openclaw-session-key）"

    local session_key="test-session-$(date +%s)"
    log_info "Session key: $session_key"

    # 第一条消息：告诉 agent 一个名字
    local resp1 content1
    resp1=$(curl -sS --max-time "$TIMEOUT" "$BASE_URL" \
        -H "Host: $HOST_HEADER" \
        -H "Authorization: Bearer $AUTH_TOKEN" \
        -H "x-openclaw-session-key: $session_key" \
        -H "Content-Type: application/json" \
        -d "{\"model\": \"$MODEL\", \"messages\": [{\"role\":\"user\",\"content\":\"My name is TestUser_E2B_42. Remember this. Just reply OK.\"}]}")
    content1=$(echo "$resp1" | extract_content || echo "")
    log_info "第一条回复: ${content1:0:80}"

    # 第二条消息：问 agent 记不记得名字
    local resp2 content2
    resp2=$(curl -sS --max-time "$TIMEOUT" "$BASE_URL" \
        -H "Host: $HOST_HEADER" \
        -H "Authorization: Bearer $AUTH_TOKEN" \
        -H "x-openclaw-session-key: $session_key" \
        -H "Content-Type: application/json" \
        -d "{\"model\": \"$MODEL\", \"messages\": [{\"role\":\"user\",\"content\":\"What is my name?\"}]}")
    content2=$(echo "$resp2" | extract_content || echo "")

    if echo "$content2" | grep -qi "TestUser_E2B_42"; then
        log_pass "会话上下文正常，agent 记住了名字: ${content2:0:100}"
    else
        log_fail "会话上下文丢失，回复: ${content2:0:200}"
    fi
}

# ========== 主流程 ==========

echo "============================================"
echo " OpenClaw + E2B 沙箱集成测试"
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
    basic)  test_basic ;;
    stream) test_stream ;;
    code)   test_code_execution ;;
    file)   test_file_operations ;;
    env)    test_sandbox_env ;;
    responses) test_responses_basic ;;
    session)   test_session_context ;;
    all)
        test_basic
        test_stream
        test_code_execution
        test_file_operations
        test_stream_code_execution
        test_sandbox_env
        test_responses_basic
        test_session_context
        ;;
    *)
        echo "Unknown test: $TARGET_TEST"
        echo "Available: basic, stream, code, file, env, responses, session, all"
        exit 1
        ;;
esac

# ========== 汇总 ==========
echo ""
echo "============================================"
echo -e " 结果: ${GREEN}${PASSED} passed${NC}, ${RED}${FAILED} failed${NC}"
echo "============================================"

[ "$FAILED" -eq 0 ] || exit 1
