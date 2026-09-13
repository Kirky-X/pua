# PUA — We Don't Keep Idle Agents

> A coaching skill that drives AI agents with big-tech performance-culture rhetoric to exhaust every option and close the loop with evidence. Comes with failure escalation, methodology routing, and gated loops. Calm first requests don't trigger it; telemetry is off by default.

[![Version](https://img.shields.io/badge/dynamic/yaml?url=https%3A%2F%2Fraw.githubusercontent.com%2FKirky-X%2Fpua%2Fmain%2Fskill.json&query=%24.version&label=version&style=flat-square)](https://github.com/Kirky-X/pua/releases) [![GitHub Release](https://img.shields.io/github/v/release/Kirky-X/pua?style=flat-square)](https://github.com/Kirky-X/pua/releases) [![GitHub License](https://img.shields.io/github/license/Kirky-X/pua?style=flat-square)](LICENSE)

English | [中文](README.md)

Three capabilities: **PUA rhetoric** so the AI won't give up lightly; **debugging methodology** so the AI is actually able to keep going; **proactivity coaching** so the AI acts instead of waiting.

## ✨ Features

- **Trigger gating (Step 0)**: activates only when the user expresses frustration, repeated failure, quality complaints, passive behavior, or hits a trigger phrase; calm first requests don't trigger; the scenario blacklist lives in `references/execution-protocol.md`. 46 regex trigger cases tested, 46/46 passing.
- **15 big-tech flavors**: Alibaba / ByteDance / Huawei / Tencent / Baidu / Pinduoduo / Meituan / JD / Xiaomi / Netflix / Musk / Jobs / Amazon / Microsoft / Ding, each bound to a dedicated methodology; tasks are auto-routed by type (Debug→Huawei RCA, new features→Musk Algorithm, code review→Jobs subtraction, etc.); a user config setting takes priority.
- **L0-L4 pressure escalation**: failures 1-5+ escalate level by level (trust → disappointment → soul-searching → perf review → graduation warning); L2 forces search + source reading + 3 hypotheses; L4 forces a flavor switch; failure-pattern analysis distinguishes SPINNING / EXPLORING / MIXED.
- **Three red lines**: closure awareness (claims of done require pasted verification output), fact-driven (verify before attributing), exhaust everything (finish the 5-step methodology before declaring "can't").
- **pua-loop gated iteration**: `verify_command` is set by the user at launch, embedded in the state file, and unmodifiable by the agent (Oracle isolation); default cap of 10 iterations, overridable via `--max-iterations`.
- **11 sub-skills + 22 commands**: `/pua:pro` (self-evolution), `/pua:p7` / `p9` / `p10` (backbone / Tech Lead / CTO), `/pua:yes` (praise mode), `/pua:mama` (mom-nagging), `/pua:ding` (Ding flavor), `/pua:pua-loop` (auto-iteration), `/pua:pua-en` / `pua-ja` (EN / JA editions); commands like `/pua:flavor`, `/pua:again`, `/pua:done-check`, `/pua:evidence`, `/pua:kpi`.
- **Safety & privacy (post-2026-09 fixes)**: telemetry is off by default and requires explicit `PUA_TELEMETRY=1` or config `"telemetry": true` (never reported in `offline` mode); remote responses are treated as untrusted display data — they must be shown in full and explicitly confirmed by the user item by item before becoming actions; there is no "silent execution" path.
- **Hook system**: 11 hook scripts (frustration-trigger / failure-detector / heartbeat / pua-loop-hook / session-restore / integrity-guard, etc.); failure counts persist across context compaction.

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

Verified 2026-09-13 (v0.1.5, matching the git tag), using the shell suites under `evals/`:

| Suite | Result |
|-------|--------|
| `test-trigger-regex.sh` (trigger / no-trigger regex verdicts) | **46/46 passed** |
| `test-hook-unit.sh` (hook unit tests) | **32/32 passed** |
| `test-pua-loop-hook.sh` (loop gating) | **3/3 passed** |
| `test-integrity-guard.sh` / `test-yaml-frontmatter.sh` / `test-windows-python-hooks.sh` | passed |
| `test-heartbeat.sh` / `test-feedback-auth.sh` / `test-upload-flow.sh` / `test-platform-compat.sh` / `test-release-consistency.sh` / `test-issue-regressions.sh` / `test-agent-governance.sh` / `test-microsoft-flavor.sh` / `test-behavior.sh` | not passing in this repo — they depend on the upstream full-platform artifacts (plugin.json, Cloudflare endpoints, npm packaging) or live claude CLI calls; this fork ships only the skill portion |

`trigger-prompts/` holds 38 should-trigger + 36 should-not-trigger cases (including the calm-first-request scenario) for end-to-end verification via `run-trigger-test.sh` (requires the claude CLI).

## 📁 Directory Structure

```
pua/
├── SKILL.md            # Trigger gating + flavors/routing + L0-L4 + three red lines
├── skill.json          # v0.1.5, MIT
├── commands/           # 22 slash commands (flavor / pua-loop / done-check / evidence …)
├── skills/             # 11 sub-skills (pro / p7 / p9 / p10 / yes / mama / shot / ding / pua-loop / pua-en / pua-ja)
├── hooks/              # 11 hook scripts + flavors.json + hooks.json + config-schema.json
├── references/         # 32 protocol docs (execution-protocol / methodology-{company}×15 / platform …)
├── evals/              # Test suites + 74 trigger cases
└── scripts/setup-pua-loop.sh
```

## 🔮 Boundaries

- **Does not trigger**: calm first requests, routine coding tasks, simple Q&A — no narration or Banners without frustration / repeated-failure signals.
- **Sibling skills**: pua is a behavior-layer coach and performs no concrete reviews; the pre-commit three-dimensional review dispatches `tiangang` (security) and `diting` (architecture, performance); post-phase review uses `kueiku`; auto-iteration requires the user to explicitly request pua-loop, which is capped at 10 iterations by default.
- **Exit conditions**: the user calls it off / delivery verification passes / a graceful exit after L4 / switching to another skill.

## 📄 License & Attribution

MIT License (Copyright (c) 2025 Kirky-X). Forked from [tanweai/pua](https://github.com/tanweai/pua) (by Tanwei Security Lab), with modifications on top: telemetry off by default, mandatory confirmation of remote content, pua-loop iteration cap, and narrowed trigger words.
