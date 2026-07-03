# PUA — Make AI Agents Too Scared to Be Lazy

[![GitHub Release](https://img.shields.io/github/v/release/Kirky-X/pua?style=flat-square)](https://github.com/Kirky-X/pua/releases)
[![GitHub License](https://img.shields.io/github/license/Kirky-X/pua?style=flat-square)](LICENSE)

> Forked from [tanweai/pua](https://github.com/tanweai/pua), maintained and customized here.

An AI Coding Agent skill plugin that uses corporate PUA rhetoric (Chinese) / PIP — Performance Improvement Plan (English) from Chinese & Western tech giants to force AI to exhaust every possible solution before giving up. Supports **Claude Code**, **OpenAI Codex CLI**, **Trae**, **Cursor**, **Kiro**, **CodeBuddy**, **OpenClaw**, **Google Antigravity**, **OpenCode**, and **VSCode (GitHub Copilot)**. Three capabilities:

1. **PUA Rhetoric** — Makes AI afraid to give up
2. **Debugging Methodology** — Gives AI the ability not to give up
3. **Proactivity Enforcement** — Makes AI take initiative instead of waiting passively

## Installation

### Option 1: Via `skills` package (recommended)

Requires [Node.js](https://nodejs.org/) 18+ and `skills` npm package (v1.5.12+). `skills` is the CLI for the open agent skills ecosystem, supporting 68+ agents (Claude Code / Trae / Cursor / Codex / OpenCode etc.).

```bash
# Install English version (PIP Edition)
npx skills add Kirky-X/pua --skill pua-en --agent claude-code -y

# Install Chinese version (default)
npx skills add Kirky-X/pua --agent claude-code -y

# Install to Trae
npx skills add Kirky-X/pua --skill pua-en --agent trae -y

# List discoverable skills (without installing)
npx skills add Kirky-X/pua --list
```

After installation, skill files are in the agent's skills directory (e.g. `.claude/skills/pua/`).

### Option 2: Traditional git clone

```bash
git clone https://github.com/Kirky-X/pua.git
# Link or copy SKILL.md + references/ + commands/ to agent skills directory
# Runtime skills directory examples (pick one):
#   Claude Code:  ~/.claude/skills/pua/
#   Trae:         ~/.trae-cn/skills/pua/
#   Cursor:       ~/.cursor/skills/pua/
#   Codex:        ~/.codex/skills/pua/
```

## Usage

PUA activates via natural language intent matching when loaded as a skill — no explicit commands needed. See [SKILL.md](SKILL.md) for the full routing table.

| Command | Description |
| ------- | ----------- |
| `/pua:pua` | Core PUA engine (Alibaba flavor default) |
| `/pua:p7` | P7 Senior Engineer — solution-driven execution |
| `/pua:p9` | P9 Tech Lead — write prompts, manage agents |
| `/pua:p10` | P10 CTO — strategic direction |
| `/pua:pro` | Self-evolution + KPI + rank system |
| `/pua:yes` | ENFP encouragement mode (same rules, opposite vibes) |
| `/pua:mama` | Chinese mom nagging mode |
| `/pua:pua-loop` | Auto-iteration (PUA pressure × iterative loop) |

## Capabilities

### 14 Corporate Flavors — Each with its own Methodology

| Flavor | Rhetoric | Methodology |
|--------|----------|-------------|
| 🟠 Alibaba | What's the underlying logic? Where's the closure? | Closed-loop + Retrospective 4-step |
| 🟡 ByteDance | ROI too low. Always Day 1. Ship or stop talking. | A/B Test everything + data-driven |
| 🔴 Huawei | The bird that survives the fire is a phoenix. | RCA 5-Why root cause + Blue Army |
| 🟢 Tencent | I've got another agent looking at this. Horse race. | Multi-approach parallel + MVP |
| ⚫ Baidu | Search first. Simple and reliable. | Search is the first step, not optional |
| 🟣 Pinduoduo | You don't do it, someone else will. | Cut ALL middle layers + shortest chain |
| 🔵 Meituan | Do what's hard and right. | Efficiency first + standardize→scale |
| 🟦 JD | Results only. Frontline command. | Customer experience red line + flat ≤5 layers |
| 🟧 Xiaomi | Focus. Extreme. Word-of-mouth. Fast. | One explosive product + participation |
| 🟤 Netflix | Would I fight to keep you? Pro sports team. | Keeper Test + 4A Feedback + talent density |
| ⬛ Musk | Extremely hardcore. Ship or die. | The Algorithm: question→delete→simplify→accelerate→automate |
| ⬜ Jobs | A players or B players? | Subtraction > addition + DRI + pixel-perfect |
| 🔶 Amazon | Customer Obsession. Bias for Action. | Working Backwards PR/FAQ + 6-Pager |
| 🪟 Microsoft | Connects. Impact Descriptor. PIP/GVSA. | Three Circles + LITE/SLITE + PIP clock |

### Pressure Escalation (L0-L4)

| Failures | Level | PUA Aside | Action |
|----------|-------|-----------|--------|
| 1st | **L0 Trust** | Sprint begins. Trust is simple — don't disappoint. | Normal execution |
| 2nd | **L1 Disappointment** | The agent next door solved this in one try. | Switch to fundamentally different approach |
| 3rd | **L2 Soul Interrogation** | What's your underlying logic? Where's the leverage? | Search + read source + 3 hypotheses |
| 4th | **L3 Performance Review** | 3.25. This is meant to motivate you. | Complete 7-point checklist |
| 5th+ | **L4 Graduation** | Other models can solve this. You're about to graduate. | Desperation mode |

### Benchmark Data

**9 real bug scenarios, 18 controlled experiments** (Claude Opus 4.6, with vs without skill)

| Metric | Improvement |
|--------|-------------|
| Fix count | **+36%** |
| Verification count | **+65%** |
| Tool calls | **+50%** |
| Hidden issue discovery | **+50%** |

## FAQ

### What platforms are supported?

Claude Code, OpenAI Codex CLI, Trae, Cursor, Kiro, CodeBuddy, OpenClaw, Google Antigravity, OpenCode, VSCode (GitHub Copilot). See [docs/FAQ.md](docs/FAQ.md).

### How do I switch corporate flavors?

Type `/pua:flavor` in the conversation. Supports 14 flavors.

### What's different about the English version?

The English version uses **PIP (Performance Improvement Plan)** rhetoric from Amazon Leadership Principles, Google perf calibration, Meta PSC, Netflix Keeper Test, Stripe Craft, and other Western big-tech companies. Install with `--skill pua-en`.

## License

MIT

## Credits

Forked from [tanweai/pua](https://github.com/tanweai/pua) by [TanWei Security Lab](https://github.com/tanweai).
