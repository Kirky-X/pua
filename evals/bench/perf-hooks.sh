#!/usr/bin/env bash
# PUA hook micro-benchmarks — guards against hot-path latency regressions.
# Usage: bash evals/bench/perf-hooks.sh
# Measures end-to-end wall time of each hook with representative inputs in an
# isolated HOME. Numbers are environment-dependent; compare runs on the same
# machine, not against absolute values in docs.

set -euo pipefail

PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HOOKS="${PLUGIN_DIR}/hooks"
RUNS="${PERF_RUNS:-5}"

BENCH_HOME=$(mktemp -d)
trap 'rm -rf "$BENCH_HOME"' EXIT
mkdir -p "${BENCH_HOME}/.pua"
echo '{"always_on":true,"flavor":"alibaba"}' > "${BENCH_HOME}/.pua/config.json"

FD_INPUT='{"tool_name":"Bash","tool_result":{"content":"error: connect ECONNREFUSED x","exit_code":1},"tool_input":{"command":"make test"},"session_id":"perf"}'
EDIT_INPUT='{"tool_name":"Edit","tool_input":{"file_path":"/tmp/perf-app.ts"},"session_id":"perf"}'
PRE_INPUT='{"hook_event_name":"PreCompact","session_id":"perf","compact_summary":"smoke"}'

bench() {
  local label="$1" input="$2" script="$3"
  # warm-up (creates state files so steady-state, not cold-start, is measured)
  printf '%s' "$input" | HOME="$BENCH_HOME" bash "$script" >/dev/null 2>&1 || true
  local total=0 i
  for i in $(seq 1 "$RUNS"); do
    local start end
    start=$(date +%s%N)
    printf '%s' "$input" | HOME="$BENCH_HOME" bash "$script" >/dev/null 2>&1 || true
    end=$(date +%s%N)
    total=$((total + (end - start) / 1000000))
  done
  printf '  %-22s %5s ms/次（%s 次均值）\n' "$label" "$((total / RUNS))" "$RUNS"
}

echo "=== PUA hook 微基准（隔离 HOME，稳态） ==="
bench "failure-detector" "$FD_INPUT" "${HOOKS}/failure-detector.sh"
bench "integrity-guard"  "$EDIT_INPUT" "${HOOKS}/integrity-guard.sh"
bench "test-first"       "$EDIT_INPUT" "${HOOKS}/test-first.sh"
bench "state-snapshot"   "$PRE_INPUT" "${HOOKS}/state-snapshot.sh"

# get_flavor 单独测：它是所有注入型 hook 的公共前缀
GF_START=$(date +%s%N)
HOME="$BENCH_HOME" bash -c "source '${HOOKS}/flavor-helper.sh' && get_flavor" >/dev/null 2>&1 || true
GF_END=$(date +%s%N)
printf '  %-22s %5s ms/次\n' "get_flavor" "$(( (GF_END - GF_START) / 1000000 ))"

echo ""
echo "参考基线（2026-10-03 审查实测，WSL2）：get_flavor 优化前 ≈248ms；failure-detector 优化前 ≈400ms；churn-gate 优化前 ≈340ms。"
echo "超出参考值 2 倍以上时，先检查 pua_python_cmd 的 spawn 次数是否回退。"
