# PUA — 让 AI Agent 不敢偷懒的生产力技能

[English](README_EN.md)

[![GitHub Release](https://img.shields.io/github/v/release/Kirky-X/pua?style=flat-square)](https://github.com/Kirky-X/pua/releases) [![GitHub License](https://img.shields.io/github/license/Kirky-X/pua?style=flat-square)](LICENSE)

> Fork 自 [tanweai/pua](https://github.com/tanweai/pua)，在此基础上进行维护和定制。

一个 AI Coding Agent 技能插件，用中西大厂 PUA 话术驱动 AI 穷尽所有方案才允许放弃。支持 **Claude Code**、**OpenAI Codex CLI**、**Trae**、**Cursor**、**Kiro**、**CodeBuddy**、**OpenClaw**、**Google Antigravity**、**OpenCode** 和 **VSCode (GitHub Copilot)**。三重能力：

1. **PUA 话术** — 让 AI 不敢放弃
2. **调试方法论** — 让 AI 有能力不放弃
3. **能动性鞭策** — 让 AI 主动出击而不是被动等待

## 安装

### 方式一：通过 `skills` 包安装（推荐）

需 [Node.js](https://nodejs.org/) 18+ 和 `skills` npm 包（v1.5.12+）。`skills` 是 open agent skills 生态的 CLI，支持 68+ agents（Claude Code / Trae / Cursor / Codex / OpenCode 等）。

```bash
# 安装中文版（默认）
npx skills add Kirky-X/pua --agent claude-code -y

# 安装英文版（PIP Edition）
npx skills add Kirky-X/pua --skill pua-en --agent claude-code -y

# 安装到 Trae
npx skills add Kirky-X/pua --agent trae -y

# 列出仓库中可被发现的所有 skills（不安装）
npx skills add Kirky-X/pua --list
```

安装后 skill 文件位于对应 agent 的 skills 目录（如 `.claude/skills/pua/`）。

### 方式二：传统 git clone

```bash
git clone https://github.com/Kirky-X/pua.git
# 将 SKILL.md + references/ + commands/ 链接或复制到 agent skills 目录
# 各 runtime 的 skills 目录路径示例（任选其一）：
#   Claude Code:  ~/.claude/skills/pua/
#   Trae:         ~/.trae-cn/skills/pua/
#   Cursor:       ~/.cursor/skills/pua/
#   Codex:        ~/.codex/skills/pua/
```

## 使用示例

PUA 作为 skill 被 agent 加载后，通过自然语言意图触发，无需显式命令。子命令详细描述与用户意图路由见 [SKILL.md](SKILL.md)。

| 子命令 | 一句话功能 |
| ------ | ---------- |
| `/pua:pua` | 核心 PUA 引擎（阿里味默认） |
| `/pua:p7` | P7 骨干模式 — 方案驱动执行 |
| `/pua:p9` | P9 Tech Lead — 写 Prompt，管 Agent 团队 |
| `/pua:p10` | P10 CTO — 战略方向 |
| `/pua:pro` | 自进化 + KPI + 段位 |
| `/pua:yes` | ENFP 夸夸模式（规则不变，旁白反转） |
| `/pua:mama` | 妈妈唠叨模式（规则不变，旁白变中国式妈妈碎碎念） |
| `/pua:pua-loop` | 自动迭代（PUA 压力 × 循环机制） |

## 能力概览

### 14 种大厂味道 — 每种自带方法论

| 味道 | 旁白风格 | 核心方法论 |
|------|---------|-----------|
| 🟠 阿里 | 底层逻辑是什么？闭环在哪？ | 定目标→追过程→拿结果 + 复盘四步法 |
| 🟡 字节 | ROI 太低。Always Day 1。 | A/B Test + 数据驱动 + 速度 > 完美 |
| 🔴 华为 | 烧不死的鸟是凤凰。 | RCA 5-Why 根因分析 + 蓝军自攻击 |
| 🟢 腾讯 | 我已经让另一个 agent 也在看了。赛马。 | 多方案并行 + MVP + 灰度发布 |
| ⚫ 百度 | 搜索先于一切。简单可依赖。 | 搜索是第一步，不是可选项 |
| 🟣 拼多多 | 你不做，有的是人做。 | 砍掉所有中间层 + 最短决策链 |
| 🔵 美团 | 做难而正确的事。 | 效率优先 + 标准化→规模化 |
| 🟦 京东 | 只看结果。一线指挥。 | 客户体验红线 + 数据零容忍 |
| 🟧 小米 | 专注。极致。口碑。快。 | 单品爆款 + 参与感三三法则 |
| 🟤 Netflix | 我会为留住你而战吗？职业球队。 | Keeper Test + 4A Feedback |
| ⬛ Musk | Extremely hardcore。Ship or die。 | The Algorithm：质疑→删除→简化→加速→自动化 |
| ⬜ Jobs | A 级选手还是 B 级选手？ | 减法 > 加法 + DRI + 像素级完美 |
| 🔶 Amazon | Customer Obsession。Bias for Action。 | Working Backwards + 6-Pager |
| 🪟 Microsoft | Connects。Impact Descriptor。PIP/GVSA。 | 三圈影响力 + LITE/SLITE |

### 压力升级（L0-L4）

| 失败次数 | 等级 | PUA 话术 | 强制动作 |
|---------|------|---------|---------|
| 第 1 次 | **L0 信任** | Sprint 开始。信任很简单——别辜负。 | 正常执行 |
| 第 2 次 | **L1 失望** | 隔壁 agent 一次就解决了。 | 切换本质不同的方案 |
| 第 3 次 | **L2 灵魂拷问** | 底层逻辑是什么？抓手在哪？ | WebSearch + 读源码 + 3 个假设 |
| 第 4 次 | **L3 绩效考核** | 3.25。这个是激励。 | 完成 7 项检查清单 |
| 第 5 次+ | **L4 毕业** | 别的模型都能解决。你可能要毕业了。 | 拼命模式 |

### 实测数据

**9 个真实 bug 场景，18 组对照实验**（Claude Opus 4.6，with vs without skill）

| 指标 | 提升 |
|------|------|
| 修复点数 | **+36%** |
| 验证次数 | **+65%** |
| 工具调用 | **+50%** |
| 隐藏问题发现率 | **+50%** |

## FAQ

### 支持哪些平台？

Claude Code、OpenAI Codex CLI、Trae、Cursor、Kiro、CodeBuddy、OpenClaw、Google Antigravity、OpenCode、VSCode (GitHub Copilot)。详见 [docs/FAQ.md](docs/FAQ.md)。

### 如何切换大厂味道？

对话中输入 `/pua:flavor` 即可切换。支持 14 种味道。

### 英文版有什么不同？

英文版使用 **PIP（Performance Improvement Plan）** 话术，来自 Amazon Leadership Principles、Google perf calibration、Meta PSC、Netflix Keeper Test、Stripe Craft 等西方大厂。安装时选择 `--skill pua-en`。

## 许可证

MIT

## 致谢

Fork 自 [tanweai/pua](https://github.com/tanweai/pua)（[探微安全实验室](https://github.com/tanweai) 出品）。
