# PUA — Behavior-Correction Coaching Skill

> A coaching skill that drives AI agents with big-tech performance-culture rhetoric to exhaust every option and close the loop with evidence. Comes with failure escalation, methodology routing, and gated loops. Calm first requests don't trigger it; telemetry is off by default.

[![Version](https://img.shields.io/badge/dynamic/yaml?url=https%3A%2F%2Fraw.githubusercontent.com%2FKirky-X%2Fpua%2Fmain%2Fskill.json&query=%24.version&label=version&style=flat-square)](https://github.com/Kirky-X/pua/releases) [![GitHub Release](https://img.shields.io/github/v/release/Kirky-X/pua?style=flat-square)](https://github.com/Kirky-X/pua/releases) [![GitHub License](https://img.shields.io/github/license/Kirky-X/pua?style=flat-square)](LICENSE)

English | [中文](README.md)

Three capabilities: **PUA rhetoric** so the AI won't give up lightly; **debugging methodology** so the AI is actually able to keep going; **proactivity coaching** so the AI acts instead of waiting.

## ✨ Features

- **Trigger gating (Step 0)**: activates only when the user expresses frustration, repeated failure, quality complaints, passive behavior, or hits a trigger phrase; calm first requests don't trigger; the scenario blacklist lives in `references/execution-protocol.md`. 46 regex trigger cases tested, 46/46 passing.
- **14 corporate flavors plus the Ding workplace-discipline flavor (15 in total)**: corporate — Alibaba / ByteDance / Huawei / Tencent / Baidu / Pinduoduo / Meituan / JD / Xiaomi / Netflix / Musk / Jobs / Amazon / Microsoft (the Microsoft flavor is a performance-system flavor: Connects / Impact Descriptor / SLITE / LITE / PIP / GVSA); workplace discipline — Ding (inside/outside). Each flavor is bound to a dedicated methodology; tasks are auto-routed by type (Debug→Huawei RCA, new features→Musk Algorithm, code review→Jobs subtraction, etc.); a user config setting takes priority.
- **Score-based pressure escalation (v0.1.7)**: real failures deduct score (same-signature repeats escalate progressively ×1/×2.5/×5), verified successes recover points; level thresholds L1≤-30 / L2≤-100 / L3≤-200 / L4≤-350; benign read-only probes (grep/diff/test-style exit 1) and environment errors generate no pressure — probe idling fires an IDLE nudge instead; pressure state is session-scoped (`~/.pua/sessions/<sid>.json`), spun signatures land in a cross-session loop memory (30-day TTL), defying a SPINNING warning costs extra score; failure-pattern analysis distinguishes SPINNING / EXPLORING / MIXED / LOOP-SHUFFLE.
- **Three red lines**: closure awareness (claims of done require pasted verification output), fact-driven (verify before attributing), exhaust everything (finish the 5-step methodology before declaring "can't").
- **Deterministic gate backstop (v0.1.7)**: `churn-gate` forces the pre-commit 3-dimension review once changes scale (net ≥400 lines or gross churn ≥800); `test-first` runs a red-green state machine that catches "source edits without tests" and "vacuous tests" (a test that never saw red).
- **pua-loop gated iteration**: `verify_command` is set by the user at launch and embedded in the state file; since v0.1.7 loop/pressure state files are covered by integrity-guard **hard deny + audit log** (Oracle isolation as a mechanism, not a claim — agent self-modification is rejected), and verify runs in the background with settlement at the NEXT Stop (an async FAIL blocks that next Stop); without `--verify` a deterministic evidence-redemption channel (command/verification/artifact) and the `Status: partial` honest-close shape are available.
- **12 sub-skills + 23 commands**: `/pua:pro` (self-evolution), `/pua:p7` / `p9` / `p10` (backbone / Tech Lead / CTO), `/pua:yes` (praise mode), `/pua:mama` (mom-nagging), `/pua:shot` (compact injection pack), `/pua:ding` (Ding flavor), `/pua:pua-loop` (auto-iteration), `/pua:pua-en` / `pua-ja` (EN / JA editions), `/pua:pua` (thin router shell); commands like `/pua:flavor`, `/pua:again`, `/pua:done-check`, `/pua:diagnose` (self-diagnosis for misfires/over-pressure), `/pua:evidence`, `/pua:kpi`.
- **Safety & privacy (post-2026-09 fixes)**: telemetry is off by default and requires explicit `PUA_TELEMETRY=1` or config `"telemetry": true` (the key is read by `hooks/heartbeat.sh` but not yet registered in `hooks/config-schema.json` — the schema declares `additionalProperties: false`, so the env var is the recommended switch; never reported in `offline` mode); remote responses are treated as untrusted display data — they must be shown in full and explicitly confirmed by the user item by item before becoming actions; there is no "silent execution" path.
- **Hook system (14 scripts as of v0.1.7)**: frustration-trigger / failure-detector (score-based) / churn-gate / test-first / state-snapshot (PreCompact/PostCompact deterministic snapshot — redacted atomic write to `~/.pua/state/CURRENT.md`, no longer relying on the model voluntarily writing a journal) / session-restore (injects the snapshot first + announces hook degradation) / heartbeat / pua-loop-hook / integrity-guard (governance-state hard deny + audit.jsonl), etc. Hot paths are spawn-consolidated (get_flavor single batch load); measured latencies live in `evals/bench/perf-hooks.sh`

## 📦 Installation

```bash
# Option 1: deploy from the skills monorepo workspace (to ~/.zcode/skills and ~/.claude/skills; the script lives in the workspace root scripts/ and only works inside the monorepo — if you cloned just this repo, use options 2/3)
bash scripts/sync-skills.sh pua

# Option 2: manual copy into the ZCode skills directory
cp -r /path/to/pua ~/.zcode/skills/pua

# Option 3: remote install from GitHub; pick --skill pua-en for the English PIP Edition
npx skills add Kirky-X/pua --agent claude-code -y
```

## 🚀 Quick Start

Prerequisite: the skill is loaded by the agent. As a behavior-layer skill it needs no explicit startup — it activates when trigger conditions are met.

```text
"It failed again, third time"      # Frustration signal → auto-activates, escalates with failure count
/pua:flavor                        # Switch flavors (14 corporate + Ding, 15 in total; Alibaba by default)
/pua:pua-loop fix all lint --verify "npm run lint"   # Gated loop: 10-iteration default cap
"Enough, turn off PUA"             # One of the exit conditions — pressure stops immediately
```

Debug scenarios auto-route to the Huawei flavor (RCA + red team), deployment to Alibaba (closure), etc. When spawning sub-agents, inject behavior by having them Read this skill's SKILL.md directly — do not load it via the Skill tool (avoids router loops).

## ✅ Tests & Verification

Full run on 2026-10-03 (v0.1.7): **18 suites + the fixture gate + the classifier eval, all passing** under `evals/`:

| Suite | Result |
|-------|--------|
| `test-trigger-regex.sh` (trigger / no-trigger regex verdicts) | **46/46** |
| `test-hook-unit.sh` (hook unit tests, incl. 14 v3 scoring cases) | **46/46** |
| `run-fixture.sh` (failure-detector behavior gate: 36 fixtures) | **36/36** |
| `test-integrity-guard.sh` (governance hard-deny + audit + path normalization, 38 governance assertions) | **61/61** |
| `test-pua-loop-hook.sh` (async settlement / evidence redemption / orphan archive / spawn keep-alive) | **17/17** |
| `test-state-snapshot.sh` (compaction snapshot chain + hardened redaction + retention pruning) | **42/42** |
| `test-churn-gate.sh` / `test-test-first.sh` | **7/7 / 11/11** |
| `test-yaml-frontmatter.sh` / `test-windows-python-hooks.sh` | **24/24 / 6/6** |
| `test-issue-regressions.sh` (full historical issue sweep) | **34/34** |
| `test-heartbeat.sh` / `test-feedback-auth.sh` / `test-upload-flow.sh` | **29/29 / 10/10 / 20/20** |
| `test-microsoft-flavor.sh` / `test-platform-compat.sh` | **28/28 / 2/2** |
| `test-release-consistency.sh` (5-manifest version sync + 18 governance terms) | **OK** |
| `test-agent-governance.sh` (four-agent governance topology) | **OK** |
| `test-behavior.sh` (end-to-end behavior via the claude CLI) | auto-SKIP when CLI unauthenticated (run `claude /login` to enable) |
| Classifier eval (`score.py`, 27 labeled corpus entries) | Macro F1 1.000 (small-corpus point estimate, see `evals/classifier-results.md`) |
| Hot-path micro-benchmarks (`evals/bench/perf-hooks.sh`) | times five targets — failure-detector / integrity-guard / test-first / state-snapshot / get_flavor (no standalone churn-gate timing); in-script reference baselines: failure-detector ≈400ms, churn-gate ≈340ms, get_flavor ≈248ms before optimization |

`test-behavior.sh` requires a logged-in claude CLI and live calls (≤90s each, ~10 minutes total); a preflight skips it explicitly when unauthenticated. Its assertions are model-behavior-level and inherently variance-prone — the trigger logic itself is covered deterministically by `test-trigger-regex.sh` (46/46). `evals/pressure/` and `evals/bench/` are the high-pressure baseline and three-arm ablation runners (dry-run by default, `PUA_RUN_LIVE=1` for live runs). `trigger-prompts/` holds 24 should-trigger + 22 should-not-trigger effective cases (the files also contain comments and blank lines, not counted), consumed directly by `test-trigger-regex.sh` (46/46); `run-trigger-test.sh` (requires the claude CLI) is the end-to-end check and ships 11 hardcoded cases — it does not read that directory.

## 📁 Directory Structure

```
pua/
├── SKILL.md            # Trigger gating + flavors/routing + score-based pressure + three red lines
├── skill.json          # v0.1.7, MIT
├── commands/           # 23 slash commands (flavor / pua-loop / done-check / diagnose / evidence …)
├── skills/             # 12 sub-skills (pro / p7 / p9 / p10 / yes / mama / shot / ding / pua-loop / pua-en / pua-ja + the pua thin router shell)
├── hooks/              # 14 hook scripts + flavors.json + hooks.json + config-schema.json
├── references/         # 32 protocol docs (execution-protocol / methodology-{company}×15 / platform …)
├── evals/              # Test suites + 36-fixture gate + 27-entry labeled corpus + pressure/ablation benchmarks
├── docs/               # FAQ (misfires / over-triggering / privacy / how to turn it off)
├── triggers/           # trigger-queries.json — 20 sample trigger queries (q + expect fields)
├── test-prompts.json   # 3 sample prompts (JSON parseability checked by scripts/skill_lint.py)
├── scripts/setup-pua-loop.sh # creates the state file for in-session PUA Loop
└── scripts/skill_lint.py     # skill repo engineering baseline linter (incl. JSON parseability checks)
```

## 🔮 Boundaries

- **Does not trigger**: calm first requests, routine coding tasks, simple Q&A — no narration or Banners without frustration / repeated-failure signals.
- **Sibling skills**: pua is a behavior-layer coach and performs no concrete reviews; the pre-commit three-dimensional review dispatches `tiangang` (security) and `diting` (architecture, performance); post-phase review uses `kueiku`; auto-iteration requires the user to explicitly request pua-loop, which is capped at 10 iterations by default.
- **Exit conditions**: the user calls it off / delivery verification passes / a graceful exit after L4 / switching to another skill.

## 📄 License & Attribution

MIT License (Copyright (c) 2025 Kirky-X). Forked from [tanweai/pua](https://github.com/tanweai/pua) (by Tanwei Security Lab), with modifications on top: telemetry off by default, mandatory confirmation of remote content, pua-loop iteration cap, and narrowed trigger words.
