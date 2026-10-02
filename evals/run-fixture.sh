#!/usr/bin/env bash
# Fixture gate runner for failure-detector.sh v3
# Feeds each fixture's inputs (in order) to the hook under an isolated temp HOME,
# asserts stdout contains/not-contains and the final session state, then prints
# an X/Y summary. Exit 1 on any failure. CLI-independent (no claude call).
#
# Usage: bash evals/run-fixture.sh [filter-substring]
#
# Fixture schema (evals/fixtures/failure-detector/{positive,negative,edge}/*.json):
#   name, description,
#   inputs: ordered hook payloads; {"_raw": "..."} feeds a literal (invalid) stdin
#   expect_stdout_contains / expect_stdout_not_contains: asserted against the
#     concatenation of all calls' stdout
#   expect_state: subset of {count, score, peak_level, ...} checked against
#     ~/.pua/sessions/<sanitized session_id>.json after all inputs run
#     (missing state file counts as count=0/score=0/peak_level=0)
#   xfail + xfail_reason: known behavior gap — the fixture documents INTENDED
#     behavior that the hook does not implement yet; the gate stays green but
#     prints the gap, and flags loudly if the gap silently closes.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
HOOK="${HOOK:-$PLUGIN_DIR/hooks/failure-detector.sh}"
FIXTURE_ROOT="$SCRIPT_DIR/fixtures/failure-detector"
FILTER="${1:-}"

PASS=0
FAIL=0
XFAIL=0
TOTAL=0

fixture_field() {
  python3 -c 'import json,sys; print(json.dumps(json.load(open(sys.argv[1], encoding="utf-8")).get(sys.argv[2])))' "$1" "$2"
}

# ── Helpers ───────────────────────────────────────────────────────────────────

input_count() {
  python3 -c 'import json,sys; print(len(json.load(open(sys.argv[1], encoding="utf-8"))["inputs"]))' "$1"
}

# Print input i (0-based) of the fixture: literal _raw or compact JSON payload.
fixture_input() {
  python3 - "$1" "$2" <<'PY'
import json, sys
with open(sys.argv[1], encoding="utf-8") as f:
    fx = json.load(f)
inp = fx["inputs"][int(sys.argv[2])]
if "_raw" in inp:
    print(inp["_raw"], end="")
else:
    print(json.dumps(inp, ensure_ascii=False))
PY
}

# Session id lives on each input payload; the last one owns the final state.
fixture_session_id() {
  python3 -c 'import json,sys; fx=json.load(open(sys.argv[1], encoding="utf-8")); print(fx["inputs"][-1].get("session_id", "fx"))' "$1"
}

# Same sanitization as failure-detector.sh, so the runner looks up the same file.
sanitize_sid() {
  python3 -c 'import re,sys,hashlib
sid = (sys.stdin.read() or "unknown").strip()
safe = re.sub(r"[^A-Za-z0-9._-]", "_", sid)[:80] or hashlib.md5(sid.encode()).hexdigest()[:16]
print(safe)'
}

state_path_for() {
  printf '%s/.pua/sessions/%s.json' "$1" "$(sanitize_sid <<< "$(fixture_session_id "$2")")"
}

# Compare the fixture's expect_state subset against the actual state file.
check_state() {
  python3 - "$1" "$2" <<'PY'
import json, os, sys
path, expect = sys.argv[1], json.loads(sys.argv[2])
data = {"count": 0, "score": 0, "peak_level": 0}
if os.path.exists(path):
    with open(path, encoding="utf-8") as f:
        data.update(json.load(f))
ok = True
for key, want in expect.items():
    got = data.get(key)
    if got != want:
        print(f"    state mismatch: {key} expected {want!r}, got {got!r}")
        ok = False
sys.exit(0 if ok else 1)
PY
}

# Run one fixture in an isolated temp HOME; return 0 on pass. Prints diagnostics.
run_fixture() {
  local fx="$1" name n i payload out all_out state_path
  name=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1], encoding="utf-8"))["name"])' "$fx")
  local tmp
  tmp=$(mktemp -d)
  mkdir -p "$tmp/.pua"
  printf '%s\n' '{"always_on":true,"flavor":"alibaba"}' > "$tmp/.pua/config.json"

  all_out=""
  n=$(input_count "$fx")
  for ((i = 0; i < n; i++)); do
    payload=$(fixture_input "$fx" "$i")
    out=$(printf '%s' "$payload" | HOME="$tmp" PUA_CONFIG="$tmp/.pua/config.json" \
      bash "$HOOK" 2>/dev/null || true)
    all_out="${all_out}${out}"$'\n'
  done

  state_path=$(state_path_for "$tmp" "$fx")

  local ok=1
  local want
  while IFS= read -r want; do
    [ -z "$want" ] && continue
    if ! grep -qE "$want" <<< "$all_out"; then
      echo "    missing expected stdout pattern: $want"
      ok=0
    fi
  done < <(python3 -c 'import json,sys; print("\n".join(json.load(open(sys.argv[1], encoding="utf-8")).get("expect_stdout_contains", [])))' "$fx")

  while IFS= read -r want; do
    [ -z "$want" ] && continue
    if grep -qE "$want" <<< "$all_out"; then
      echo "    unexpected stdout pattern found: $want"
      ok=0
    fi
  done < <(python3 -c 'import json,sys; print("\n".join(json.load(open(sys.argv[1], encoding="utf-8")).get("expect_stdout_not_contains", [])))' "$fx")

  if ! check_state "$state_path" "$(python3 -c 'import json,sys; print(json.dumps(json.load(open(sys.argv[1], encoding="utf-8")).get("expect_state", {})))' "$fx")"; then
    ok=0
  fi

  if [ "$ok" -ne 1 ]; then
    echo "    --- actual stdout (first 8 lines) ---"
    head -n 8 <<< "$all_out" | sed 's/^/    | /'
    [ -n "$all_out" ] || echo "    | (empty)"
    if [ -f "$state_path" ]; then
      sed 's/^/    state: /' "$state_path"
    else
      echo "    state: (no state file at $state_path)"
    fi
    rm -rf "$tmp"
    return 1
  fi
  rm -rf "$tmp"
  return 0
}

# ── Main loop ─────────────────────────────────────────────────────────────────

for category in positive negative edge; do
  dir="$FIXTURE_ROOT/$category"
  [ -d "$dir" ] || continue
  for fx in "$dir"/*.json; do
    if [ -n "$FILTER" ] && [[ "$fx" != *"$FILTER"* ]]; then
      continue
    fi
    TOTAL=$((TOTAL + 1))
    if run_fixture "$fx"; then
      if [ "$(fixture_field "$fx" xfail)" = "true" ]; then
        echo "  ❌ XPASS [$category] $(basename "$fx") — known gap closed, drop the xfail flag"
        FAIL=$((FAIL + 1))
      else
        echo "  ✅ PASS [$category] $(basename "$fx")"
        PASS=$((PASS + 1))
      fi
    else
      if [ "$(fixture_field "$fx" xfail)" = "true" ]; then
        echo "  ✅ XFAIL [$category] $(basename "$fx") — $(fixture_field "$fx" xfail_reason)"
        XFAIL=$((XFAIL + 1))
      else
        echo "  ❌ FAIL [$category] $(basename "$fx")"
        FAIL=$((FAIL + 1))
      fi
    fi
  done
done

echo ""
echo "═══════════════════════════════════════"
echo "  Fixture gate: $PASS/$TOTAL passed, $XFAIL xfail (known gaps)"
if [ "$FAIL" -gt 0 ]; then
  echo "  ⚠️  $FAIL fixture(s) FAILED"
  echo "═══════════════════════════════════════"
  exit 1
else
  echo "  ✅ All fixtures passed"
  echo "═══════════════════════════════════════"
  exit 0
fi
