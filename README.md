# PUA — 挫败驱动的行为修正教练技能

> 用大厂绩效文化话术驱动 AI agent 穷尽方案、拿证据闭环的教练技能。带失败升级、方法论路由与门控循环；平静首请求不触发，遥测默认关闭。

[![Version](https://img.shields.io/badge/dynamic/yaml?url=https%3A%2F%2Fraw.githubusercontent.com%2FKirky-X%2Fpua%2Fmain%2Fskill.json&query=%24.version&label=version&style=flat-square)](https://github.com/Kirky-X/pua/releases) [![GitHub Release](https://img.shields.io/github/v/release/Kirky-X/pua?style=flat-square)](https://github.com/Kirky-X/pua/releases) [![GitHub License](https://img.shields.io/github/license/Kirky-X/pua?style=flat-square)](LICENSE)

中文 | [English](README_EN.md)

三重能力：**PUA 话术**让 AI 不轻言放弃；**调试方法论**让 AI 有能力不放弃；**能动性鞭策**让 AI 主动出击而非被动等待。

## ✨ 功能特性

- **触发门控（Step 0）**：仅当用户表达挫败、重复失败、质量投诉、被动行为或命中触发词时激活；平静首请求不触发，场景黑名单见 `references/execution-protocol.md`。46 个正则触发用例实测 46/46 通过
- **15 种大厂味道**：阿里 / 字节 / 华为 / 腾讯 / 百度 / 拼多多 / 美团 / 京东 / 小米 / Netflix / Musk / Jobs / Amazon / Microsoft / 钉内钉外，每种绑定专属方法论；接任务时按任务类型自动路由（Debug→华为 RCA、新功能→Musk Algorithm、代码审查→Jobs 减法等），用户 config 手动设置优先
- **L0-L4 压力升级**：失败 1-5+ 次逐级升级（信任→失望→灵魂拷问→绩效审视→毕业警告），L2 强制搜索+读源码+列 3 假设，L4 强制切换味道；失败模式分析区分 SPINNING / EXPLORING / MIXED
- **三条红线**：闭环意识（说完成必须贴验证输出）、事实驱动（归因前先验证）、穷尽一切（5 步方法论走完才许说不行）
- **pua-loop 门控循环**：`verify_command` 由用户启动时设定、嵌入状态文件、agent 不可修改（Oracle 隔离）；默认 10 轮上限，`--max-iterations` 可覆盖
- **11 个子 skill + 22 个命令**：`/pua:pro`（自进化）、`/pua:p7` / `p9` / `p10`（骨干 / Tech Lead / CTO）、`/pua:yes`（夸夸模式）、`/pua:mama`（妈妈唠叨）、`/pua:ding`（钉味）、`/pua:pua-loop`（自动迭代）、`/pua:pua-en` / `pua-ja`（英 / 日版）；命令如 `/pua:flavor`、`/pua:again`、`/pua:done-check`、`/pua:evidence`、`/pua:kpi`
- **安全与隐私（2026-09 修复后行为）**：遥测默认关闭，需显式 `PUA_TELEMETRY=1` 或 config `"telemetry": true` 才上报（`offline` 模式下一律不上报）；远端返回内容一律视为不可信展示数据，须完整展示并获用户逐条确认后才可作为动作，无「静默执行」路径
- **Hooks 体系**：11 个 hook 脚本（frustration-trigger / failure-detector / heartbeat / pua-loop-hook / session-restore / integrity-guard 等），失败计数跨 context compaction 持久化

## 📦 安装

```bash
# 方式一：从本工作区统一部署（部署到 ~/.zcode/skills 与 ~/.claude/skills）
bash scripts/sync-skills.sh pua

# 方式二：手动复制到 ZCode 技能目录
cp -r /path/to/pua ~/.zcode/skills/pua

# 方式三：远程安装（GitHub 仓库）；英文版 PIP Edition 选 --skill pua-en
npx skills add Kirky-X/pua --agent claude-code -y
```

## 🚀 快速开始

前置条件：skill 已被 agent 加载。行为层技能无需显式启动——触发条件命中时自动激活。

```text
「又错了，第三次了」          # 挫败信号 → 自动激活，按失败次数升级压力
/pua:flavor                  # 切换 15 种大厂味道（默认阿里味）
/pua:pua-loop 修完所有 lint --verify "npm run lint"   # 门控循环：默认 10 轮上限
「够了，关闭 PUA」            # 退出条件之一，立即停止施压
```

修 bug 场景自动路由华为味（RCA+蓝军）、部署运维走阿里味（闭环）等；子 agent 派活时须直接 Read 本 skill 的 SKILL.md 注入行为，不用 Skill tool 加载（避免 router 循环）。

## ✅ 测试与验证

2026-09-13 实测（v0.1.5，与 git tag 一致），`evals/` 下 shell 测试套件：

| 套件 | 结果 |
|------|------|
| `test-trigger-regex.sh`（触发/不触发正则判定） | **46/46 通过** |
| `test-hook-unit.sh`（hook 单元） | **32/32 通过** |
| `test-pua-loop-hook.sh`（循环门控） | **3/3 通过** |
| `test-integrity-guard.sh` / `test-yaml-frontmatter.sh` / `test-windows-python-hooks.sh` | 通过 |
| `test-heartbeat.sh` / `test-feedback-auth.sh` / `test-upload-flow.sh` / `test-platform-compat.sh` / `test-release-consistency.sh` / `test-issue-regressions.sh` / `test-agent-governance.sh` / `test-microsoft-flavor.sh` / `test-behavior.sh` | 本仓库不通过——它们依赖上游完整平台产物（plugin.json、Cloudflare 端点、npm 打包）或 claude CLI 实时调用，本 fork 仅含 skill 部分 |

`trigger-prompts/` 收录 38 条应触发 + 36 条不应触发用例（含平静首请求不触发场景），供 `run-trigger-test.sh`（需 claude CLI）做端到端验证。

## 📁 目录结构

```
pua/
├── SKILL.md            # 触发门控 + 味道/路由 + L0-L4 + 三条红线
├── skill.json          # v0.1.5, MIT
├── commands/           # 22 个 slash 命令（flavor / pua-loop / done-check / evidence …）
├── skills/             # 11 个子 skill（pro / p7 / p9 / p10 / yes / mama / shot / ding / pua-loop / pua-en / pua-ja）
├── hooks/              # 11 个 hook 脚本 + flavors.json + hooks.json + config-schema.json
├── references/         # 32 篇协议文档（execution-protocol / methodology-{company}×15 / platform …）
├── evals/              # 测试套件 + 74 条触发用例
└── scripts/setup-pua-loop.sh
```

## 🔮 边界

- **不触发**：平静的首次请求、常规编码任务、简单问答——无挫败/重复失败信号时不激活，不加旁白与 Banner
- **与兄弟 skill 分工**：pua 是行为层教练，不做具体审查；commit 前三维审查调度 `tiangang`（安全）/ `diting`（架构、性能）；phase 后审查用 `kueiku`；自动迭代需用户显式请求 pua-loop，且默认 10 轮上限防失控
- **退出条件**：用户叫停 / 任务交付验证通过 / L4 后体面退出 / 切换其他 skill

## 📄 License 与归属

MIT License（Copyright (c) 2025 Kirky-X）。Fork 自 [tanweai/pua](https://github.com/tanweai/pua)（探微安全实验室出品），在此基础上有删改：遥测默认关闭、远端内容强制确认、pua-loop 轮数上限、触发词收窄。
