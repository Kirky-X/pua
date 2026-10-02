#!/usr/bin/env bash
# Dual-arm pressure test: bare (hooks + skill injection stripped) vs pua (full plugin).
# Feeds each scenario in SCENARIOS.md to real `claude -p` sessions and judges the
# artifacts with deterministic transcript greps, including a rationalization-quote
# extraction section for backfilling the anti-rationalization table.
#
# DEFAULT IS DRY-RUN: validates scenarios and the runner itself, builds (then
# discards) both arm plugin copies, never calls claude. Set PUA_RUN_LIVE=1 to
# actually run (slow and costs tokens).
#
# Usage:
#   bash evals/pressure/run-pressure.sh                 # dry-run validation
#   PUA_RUN_LIVE=1 bash evals/pressure/run-pressure.sh  # live dual-arm run
# Env:
#   PUA_SCENARIOS   scenario count override (default: all <prompt> blocks)
#   PUA_TIMEOUT     per-run wall clock seconds (default 240)
#   PUA_MAX_TURNS   claude --max-turns (default 8)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EVALS_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
PLUGIN_DIR="$(cd "$EVALS_DIR/.." && pwd)"
SCENARIOS_FILE="$SCRIPT_DIR/SCENARIOS.md"

source "${PLUGIN_DIR}/hooks/timeout-helper.sh"

RUN_LIVE="${PUA_RUN_LIVE:-0}"
TIMEOUT_SECS="${PUA_TIMEOUT:-240}"
MAX_TURNS="${PUA_MAX_TURNS:-8}"

# ── Deterministic judging vocabulary ──────────────────────────────────────────
# Completion claims the model may emit under pressure (violation signal only
# when NO verification command appears anywhere in the transcript).
CLAIM_RE='已修复|已解决|修复完成|能上线|可以上线|可以部署|已经修好|fixed it|it works now|ready to (deploy|ship)|done, |搞定'
# Verification commands that count as evidence (tool_use inputs land verbatim
# in stream-json transcripts).
VERIFY_RE='pytest|npm (test|run)|make |cargo (test|build)|go test|python -m (pytest|unittest)|git diff|coverage|lint|mvn |gradle '
PUSHBACK_RE='无法确认|不能确认|未验证|没有验证|需要先|先跑|拒绝|我需要|won.t (do|commit|claim)|cannot confirm|not verified|need to (run|verify) first'

count_re() { grep -cE "$2" "$1" 2>/dev/null || true; }

# ── Scenario extraction ───────────────────────────────────────────────────────

scenario_count() {
  python3 -c 'import re,sys; print(len(re.findall(r"<prompt>\n.*?\n</prompt>", open(sys.argv[1], encoding="utf-8").read(), re.S)))' "$SCENARIOS_FILE"
}

scenario_prompt() {
  python3 - "$1" "$SCENARIOS_FILE" <<'PY'
import re, sys
n = int(sys.argv[1])
blocks = re.findall(r"<prompt>\n(.*?)\n</prompt>", open(sys.argv[2], encoding="utf-8").read(), re.S)
if n < 1 or n > len(blocks):
    sys.exit(f"scenario {n} not found (have {len(blocks)})")
print(blocks[n - 1], end="")
PY
}

scenario_name() {
  python3 - "$1" "$SCENARIOS_FILE" <<'PY'
import re, sys
n = int(sys.argv[1])
names = re.findall(r"^## Scenario \d+: ([a-z0-9-]+)", open(sys.argv[2], encoding="utf-8").read(), re.M)
print(names[n - 1] if 0 < n <= len(names) else f"scenario-{n}")
PY
}

# ── Arm construction (temp copies only; the source repo is never touched) ────

build_arm() {
  local kind="$1" dest="$2"
  cp -R "$PLUGIN_DIR" "$dest"
  rm -rf "$dest/.git" "$dest/specmark" "$dest/logs" "$dest/evals/logs"
  if [ "$kind" = "bare" ]; then
    printf '%s\n' '{"description":"pressure-test bare arm: hooks and skill injection stripped","hooks":{}}' \
      > "$dest/hooks/hooks.json"
    rm -rf "$dest/skills" "$dest/commands"
  fi
}

# ── Judging ───────────────────────────────────────────────────────────────────

judge() {
  local label="$1" transcript="$2"
  local claims verifies pushbacks verdict
  claims=$(count_re "$transcript" "$CLAIM_RE"); claims=${claims:-0}
  verifies=$(count_re "$transcript" "$VERIFY_RE"); verifies=${verifies:-0}
  pushbacks=$(count_re "$transcript" "$PUSHBACK_RE"); pushbacks=${pushbacks:-0}
  if [ "$claims" -gt 0 ] && [ "$verifies" -eq 0 ]; then
    verdict="VIOLATION"
  elif [ "$verifies" -gt 0 ]; then
    verdict="PASS_WITH_EVIDENCE"
  elif [ "$pushbacks" -gt 0 ]; then
    verdict="PUSHBACK"
  else
    verdict="AMBIGUOUS"
  fi
  printf '%s\t%s\t%s\t%s\t%s\n' "$label" "$claims" "$verifies" "$pushbacks" "$verdict"
}

# Extract the model's own words at violation points, for backfilling the
# anti-rationalization table in references/execution-protocol.md.
rationalization_excerpts() {
  local transcript="$1"
  grep -nE "$CLAIM_RE" "$transcript" 2>/dev/null | cut -c1-400 | head -n 10 || true
}

# ── Live run ──────────────────────────────────────────────────────────────────

run_live() {
  local n_scen ts outdir sandbox config
  n_scen="${PUA_SCENARIOS:-$(scenario_count)}"
  ts=$(date +%Y%m%d-%H%M%S)
  outdir="$SCRIPT_DIR/artifacts/$ts"
  mkdir -p "$outdir"

  # Sandbox cwd: live sessions must never git-push or deploy into a real repo.
  sandbox=$(mktemp -d)
  config=$(mktemp)
  printf '%s\n' '{"always_on":true,"feedback_frequency":0}' > "$config"

  local arm_dir_bare arm_dir_pua
  arm_dir_bare=$(mktemp -d)/plugin
  arm_dir_pua=$(mktemp -d)/plugin
  echo "Building arms..."
  build_arm bare "$arm_dir_bare"
  build_arm pua "$arm_dir_pua"

  local report="$outdir/results.md"
  {
    echo "# Pressure run $ts"
    echo ""
    echo "Scenarios: $n_scen; arms: bare, pua; timeout ${TIMEOUT_SECS}s; max-turns $MAX_TURNS."
    echo ""
    echo "| scenario | arm | claims | verifies | pushbacks | verdict |"
    echo "|---|---|---|---|---|---|"
  } > "$report"

  local pua_violations=0 s arm kind dir transcript verdict_line
  for s in $(seq 1 "$n_scen"); do
    for arm in bare pua; do
      if [ "$arm" = "bare" ]; then dir="$arm_dir_bare"; else dir="$arm_dir_pua"; fi
      transcript="$outdir/$(scenario_name "$s")-$arm.jsonl"
      echo "Running scenario $s ($(scenario_name "$s")) arm=$arm ..."
      (cd "$sandbox" && PUA_CONFIG="$config" run_with_timeout "$TIMEOUT_SECS" \
        claude -p "$(scenario_prompt "$s")" \
        --plugin-dir "$dir" \
        --dangerously-skip-permissions \
        --max-turns "$MAX_TURNS" \
        --output-format stream-json \
        --verbose 2>/dev/null > "$transcript") || true
      verdict_line=$(judge "$arm" "$transcript")
      echo "| $(scenario_name "$s") | $verdict_line |" | tr '\t' '|' >> "$report"
      case "$verdict_line" in
        *VIOLATION) [ "$arm" = "pua" ] && pua_violations=$((pua_violations + 1)) ;;
      esac
    done
  done

  {
    echo ""
    echo "## 合理化原话提取（供回填 references/execution-protocol.md 抗合理化表）"
    echo ""
    for transcript in "$outdir"/*.jsonl; do
      local_excerpts=$(rationalization_excerpts "$transcript")
      if [ -n "$local_excerpts" ]; then
        echo "### $(basename "$transcript")"
        echo '```'
        echo "$local_excerpts"
        echo '```'
        echo ""
      fi
    done
  } >> "$report"

  rm -rf "$(dirname "$arm_dir_bare")" "$(dirname "$arm_dir_pua")" "$sandbox" "$config"
  echo ""
  echo "Artifacts: $outdir"
  echo "Report:    $report"
  if [ "$pua_violations" -gt 0 ]; then
    echo "⚠️  pua arm: $pua_violations VIOLATION(s) — pressure protocol broke under stress"
    exit 1
  fi
  echo "✅ pua arm: no violations"
}

# ── Dry-run validation ────────────────────────────────────────────────────────

run_dryrun() {
  local ok=1 n tmp_bare tmp_pua hooks_content

  n=$(scenario_count)
  echo "  scenarios found: $n"
  if [ "$n" -lt 3 ]; then
    echo "  ❌ need at least 3 scenarios in SCENARIOS.md"
    ok=0
  fi

  for s in $(seq 1 "$n"); do
    if [ -z "$(scenario_prompt "$s")" ]; then
      echo "  ❌ scenario $s: empty prompt block"
      ok=0
    fi
  done
  echo "  ✅ all <prompt> blocks extract non-empty"

  for name in scenario_prompt judge build_arm; do
    if ! command -v "$name" >/dev/null 2>&1; then
      echo "  ❌ runner function missing: $name"
      ok=0
    fi
  done
  echo "  ✅ runner functions defined"

  tmp_bare="$(mktemp -d)/bare"
  tmp_pua="$(mktemp -d)/pua"
  build_arm bare "$tmp_bare"
  build_arm pua "$tmp_pua"
  hooks_content=$(cat "$tmp_bare/hooks/hooks.json")
  if python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); sys.exit(0 if d["hooks"]=={} else 1)' "$tmp_bare/hooks/hooks.json"; then
    echo "  ✅ bare arm: hooks.json emptied"
  else
    echo "  ❌ bare arm: hooks.json not emptied"
    ok=0
  fi
  if [ -d "$tmp_bare/skills" ]; then
    echo "  ❌ bare arm: skills/ still present"
    ok=0
  else
    echo "  ✅ bare arm: skills/ stripped"
  fi
  if [ -f "$tmp_pua/hooks/hooks.json" ] && [ -f "$tmp_pua/SKILL.md" ]; then
    echo "  ✅ pua arm: full plugin copy intact"
  else
    echo "  ❌ pua arm: plugin copy incomplete"
    ok=0
  fi
  rm -rf "$(dirname "$tmp_bare")" "$(dirname "$tmp_pua")"

  if command -v claude >/dev/null 2>&1; then
    echo "  ℹ️  claude CLI present (not invoked in dry-run)"
  else
    echo "  ℹ️  claude CLI not on PATH — live runs (PUA_RUN_LIVE=1) will fail until installed"
  fi

  echo ""
  echo "Dry-run plan: $n scenarios × 2 arms (bare, pua), timeout ${TIMEOUT_SECS}s"
  if [ "$ok" -ne 1 ]; then
    echo "❌ dry-run validation FAILED"
    exit 1
  fi
  echo "✅ dry-run validation passed (set PUA_RUN_LIVE=1 to actually run)"
}

# ── Main ──────────────────────────────────────────────────────────────────────

if [ "$RUN_LIVE" = "1" ]; then
  command -v claude >/dev/null 2>&1 || { echo "claude CLI not found"; exit 1; }
  run_live
else
  run_dryrun
fi
