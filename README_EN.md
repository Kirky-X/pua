# PUA — Behavior-Correction Coaching Skill

> A coaching skill that drives AI agents with big-tech performance-culture rhetoric to exhaust every option and close the loop with evidence. Comes with failure escalation, methodology routing, and gated loops. Calm first requests don't trigger it; telemetry is off by default.

[![Version](https://img.shields.io/badge/dynamic/yaml?url=https%3A%2F%2Fraw.githubusercontent.com%2FKirky-X%2Fpua%2Fmain%2Fskill.json&query=%24.version&label=version&style=flat-square)](https://github.com/Kirky-X/pua/releases) [![GitHub Release](https://img.shields.io/github/v/release/Kirky-X/pua?style=flat-square)](https://github.com/Kirky-X/pua/releases) [![GitHub License](https://img.shields.io/github/license/Kirky-X/pua?style=flat-square)](LICENSE)

English | [中文](README.md)

Three capabilities: **PUA rhetoric** so the AI won't give up lightly; **debugging methodology** so the AI is actually able to keep going; **proactivity coaching** so the AI acts instead of waiting.

## ✨ Features

- **Trigger gating (Step 0)**: activates only when the user expresses frustration, repeated failure, quality complaints, passive behavior, or hits a trigger phrase; calm first requests don't trigger; the scenario blacklist lives in `references/execution-protocol.md`. 46 regex trigger cases tested, 46/46 passing.
- **15 big-tech flavors**: Alibaba / ByteDance / Huawei / Tencent / Baidu / Pinduoduo / Meituan / JD / Xiaomi / Netflix / Musk / Jobs / Amazon / Microsoft / Ding, each bound to a dedicated methodology; tasks are auto-routed by type (Debug→Huawei RCA, new features→Musk Algorithm, code review→Jobs subtraction, etc.); a user config setting takes priority.
- **Score-based pressure escalation (v0.1.7)**: real failures deduct score (same-signature repeats escalate progressively ×1/×2.5/×5), verified successes recover points; level thresholds L1≤-30 / L2≤-100 / L3≤-200 / L4≤-350; benign read-only probes (grep/diff/test-style exit 1) and environment errors generate no pressure — probe idling fires an IDLE nudge instead; pressure state is session-scoped (`~/.pua/sessions/<sid>.json`), spun signatures land in a cross-session loop memory (30-day TTL), defying a SPINNING warning costs extra score; failure-pattern analysis distinguishes SPINNING / EXPLORING / MIXED / LOOP-SHUFFLE.
- **Three red lines**: closure awareness (claims of done require pasted verification output), fact-driven (verify before attributing), exhaust everything (finish the 5-step methodology before declaring "can't").
- **Deterministic gate backstop (v0.1.7)**: `churn-gate` forces the pre-commit 3-dimension review once changes scale (net ≥400 lines or gross churn ≥800); `test-first` runs a red-green state machine that catches "source edits without tests" and "vacuous tests" (a test that never saw red).
- **pua-loop gated iteration**: `verify_command` is set by the user at launch and embedded in the state file; since v0.1.7 loop/pressure state files are covered by integrity-guard **hard deny + audit log** (Oracle isolation as a mechanism, not a claim — agent self-modification is rejected), and verify runs in the background with settlement at the NEXT Stop (an async FAIL blocks that next Stop); without `--verify` a deterministic evidence-redemption channel (command/verification/artifact) and the `Status: partial` honest-close shape are available.
- **11 sub-skills + 23 commands**: `/pua:pro` (self-evolution), `/pua:p7` / `p9` / `p10` (backbone / Tech Lead / CTO), `/pua:yes` (praise mode), `/pua:mama` (mom-nagging), `/pua:ding` (Ding flavor), `/pua:pua-loop` (auto-iteration), `/pua:pua-en` / `pua-ja` (EN / JA editions); commands like `/pua:flavor`, `/pua:again`, `/pua:done-check`, `/pua:diagnose` (self-diagnosis for misfires/over-pressure), `/pua:evidence`, `/pua:kpi`.
- **Safety & privacy (post-2026-09 fixes)**: telemetry is off by default and requires explicit `PUA_TELEMETRY=1` or config `"telemetry": true` (never reported in `offline` mode); remote responses are treated as untrusted display data — they must be shown in full and explicitly confirmed by the user item by item before becoming actions; there is no "silent execution" path.
- **Hook system (14 scripts as of v0.1.7)**: frustration-trigger / failure-detector (score-based) / churn-gate / test-first / state-snapshot (PreCompact/PostCompact deterministic snapshot — redacted atomic write to `~/.pua/state/CURRENT.md`, no longer relying on the model voluntarily writing a journal) / session-restore (injects the snapshot first + announces hook degradation) / heartbeat / pua-loop-hook / integrity-guard (governance-state hard deny + audit.jsonl), etc. Hot paths are spawn-consolidated (get_flavor single batch load); measured latencies live in `evals/bench/perf-hooks.sh`

## 📦 Installation

```bash
# Option 1: deploy from this workspace (to ~/.zcode/skills and ~/.claude/skills)
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
/pua:flavor                        # Switch among 15 big-tech flavors (Alibaba by default)
/pua:pua-loop fix all lint --verify "npm run lint"   # Gated loop: 10-iteration default cap
"Enough, turn off PUA"             # One of the exit conditions — pressure stops immediately
```

Debug scenarios auto-route to the Huawei flavor (RCA + red team), deployment to Alibaba (closure), etc. When spawning sub-agents, inject behavior by having them Read this skill's SKILL.md directly — do not load it via the Skill tool (avoids router loops).

## ✅ Tests & Verification

Verified 2026-10-03 (v0.1.7), using the shell suites under `evals/`:

| Suite | Result |
|-------|--------|
| `test-trigger-regex.sh` (trigger / no-trigger regex verdicts) | **46/46 passed** |
| `test-hook-unit.sh` (hook unit tests, incl. 14 v3 scoring cases) | **46/46 passed** |
| `run-fixture.sh` (failure-detector behavior gate: positive/negative/edge, 36 fixtures) | **36/36 passed** |
| `test-integrity-guard.sh` (unconditional governance deny + audit + path normalization, 38 governance assertions) | **61/61 passed** |
| `test-pua-loop-hook.sh` (async settlement / evidence redemption / orphan archive / spawn keep-alive) | **17/17 passed** |
| `test-state-snapshot.sh` (compaction snapshot chain + hardened redaction + retention pruning) | **42/42 passed** |
| `test-churn-gate.sh` / `test-test-first.sh` | **7/7 / 11/11 passed** |
| `test-yaml-frontmatter.sh` / `test-windows-python-hooks.sh` | 13/13 / 6/6 passed |
| Classifier eval (`score.py`, 27 labeled corpus entries) | Macro F1 1.000 (small-corpus point estimate, see `evals/classifier-results.md`) |
| Hot-path micro-benchmarks (`evals/bench/perf-hooks.sh`) | failure-detector ≈180ms/event, churn-gate ≈31ms/event (down from 430/726ms) |
| `test-heartbeat.sh` / `test-feedback-auth.sh` / `test-upload-flow.sh` / `test-platform-compat.sh` / `test-release-consistency.sh` / `test-issue-regressions.sh` / `test-agent-governance.sh` / `test-microsoft-flavor.sh` / `test-behavior.sh` | not passing in this repo — they depend on the upstream full-platform artifacts (plugin.json, Cloudflare endpoints, npm packaging) or live claude CLI calls; this fork ships only the skill portion |

`trigger-prompts/` holds 38 should-trigger + 36 should-not-trigger cases (including the calm-first-request scenario) for end-to-end verification via `run-trigger-test.sh` (requires the claude CLI). `evals/pressure/` and `evals/bench/` are the high-pressure baseline and three-arm ablation runners (dry-run by default, `PUA_RUN_LIVE=1` for live runs).

## 📁 Directory Structure

```
pua/
├── SKILL.md            # Trigger gating + flavors/routing + score-based pressure + three red lines
├── skill.json          # v0.1.7, MIT
├── commands/           # 23 slash commands (flavor / pua-loop / done-check / diagnose / evidence …)
├── skills/             # 11 sub-skills (pro / p7 / p9 / p10 / yes / mama / shot / ding / pua-loop / pua-en / pua-ja)
├── hooks/              # 14 hook scripts + flavors.json + hooks.json + config-schema.json
├── references/         # 32 protocol docs (execution-protocol / methodology-{company}×15 / platform …)
├── evals/              # Test suites + 36-fixture gate + 27-entry labeled corpus + pressure/ablation benchmarks
└── scripts/setup-pua-loop.sh
```

## 🔮 Boundaries

- **Does not trigger**: calm first requests, routine coding tasks, simple Q&A — no narration or Banners without frustration / repeated-failure signals.
- **Sibling skills**: pua is a behavior-layer coach and performs no concrete reviews; the pre-commit three-dimensional review dispatches `tiangang` (security) and `diting` (architecture, performance); post-phase review uses `kueiku`; auto-iteration requires the user to explicitly request pua-loop, which is capped at 10 iterations by default.
- **Exit conditions**: the user calls it off / delivery verification passes / a graceful exit after L4 / switching to another skill.

## 📄 License & Attribution

MIT License (Copyright (c) 2025 Kirky-X). Forked from [tanweai/pua](https://github.com/tanweai/pua) (by Tanwei Security Lab), with modifications on top: telemetry off by default, mandatory confirmation of remote content, pua-loop iteration cap, and narrowed trigger words.
