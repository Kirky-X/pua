# PUA — 挫败驱动的行为修正教练技能（简体中文版）

> 用大厂绩效文化话术驱动 AI agent 穷尽方案、拿证据闭环的教练技能。带失败升级、方法论路由与门控循环；平静首请求不触发，遥测默认关闭。

[![Version](https://img.shields.io/badge/dynamic/yaml?url=https%3A%2F%2Fraw.githubusercontent.com%2FKirky-X%2Fpua%2Fmain%2Fskill.json&query=%24.version&label=version&style=flat-square)](https://github.com/Kirky-X/pua/releases) [![GitHub Release](https://img.shields.io/github/v/release/Kirky-X/pua?style=flat-square)](https://github.com/Kirky-X/pua/releases) [![GitHub License](https://img.shields.io/github/license/Kirky-X/pua?style=flat-square)](LICENSE)

简体中文（zh-CN） | [English](README_EN.md) | [日本語](README.ja.md) | 主 README：[README.md](README.md)

三重能力：**PUA 话术**让 AI 不轻言放弃；**调试方法论**让 AI 有能力不放弃；**能动性鞭策**让 AI 主动出击而非被动等待。

## ✨ 功能特性（节选）

- **触发门控（Step 0）**：仅当用户表达挫败、重复失败、质量投诉、被动行为或命中触发词时激活；平静首请求不触发，场景黑名单见 `references/execution-protocol.md`。46 个正则触发用例实测 46/46 通过
- **14 种大厂味道（另加钉内钉外职场纪律味，共 15 种）**：阿里 / 字节 / 华为 / 腾讯 / 百度 / 拼多多 / 美团 / 京东 / 小米 / Netflix / Musk / Jobs / Amazon / Microsoft 14 个大厂味 + 钉内钉外；每种绑定专属方法论；接任务时按任务类型自动路由（Debug→华为 RCA、新功能→Musk Algorithm、代码审查→Jobs 减法等），用户 config 手动设置优先
- **评分制压力升级（v0.1.7）**：真实失败扣分（同签名重复渐进加权 ×1/×2.5/×5）、验证成功回血、级别阈值 L1≤-30 / L2≤-100 / L3≤-200 / L4≤-350；良性只读探测（grep/diff/test 等 exit 1）与环境错误不产生压力分；压力状态按会话隔离（`~/.pua/sessions/<sid>.json`），失败模式分析区分 SPINNING / EXPLORING / MIXED / LOOP-SHUFFLE
- **三条红线**：闭环意识（说完成必须贴验证输出）、事实驱动（归因前先验证）、穷尽一切（5 步方法论走完才许说不行）
- **pua-loop 门控循环**：`verify_command` 由用户启动时设定、嵌入状态文件；loop/压力状态文件纳入 integrity-guard 硬 deny + 审计日志；verify 后台运行、下次 Stop 结算；无 verify 时提供确定性证据赎回通道（命令/验证/产物三路证据）与 `Status: partial` 合法收尾
- **Hooks 体系（v0.1.7 共 14 个脚本）**：frustration-trigger / failure-detector（评分制）/ churn-gate / test-first / state-snapshot / session-restore / heartbeat / pua-loop-hook / integrity-guard 等，热路径已做 spawn 收敛优化

完整特性列表见 [README.md](README.md)。

## 🪟 Microsoft 味：绩效制度味

微软味不喊抽象口号，而是把 Microsoft 内部绩效制度叙事直接写进 PUA 机制（详见 [`references/methodology-microsoft.md`](references/methodology-microsoft.md)）：

- **Connects**：半年一次的绩效叙事账本——核心优先级、影响目标、证据包，连续失败却没有 learning delta 就只能写「反复试了同一个错方案」
- **Three Circles of Impact**：个人产出 / 解除他人阻塞 / 复用已有资产，三圈同时交账，只说「我努力了」不算 impact
- **Impact Descriptor**：Exceptional / Successful / **SLITE**（Slightly Lower Impact Than Expected）/ **LITE**（Lower Impact Than Expected）——失败后下一步动作没有变化，就是 LITE 轨迹
- **PIP / GVSA**：PIP（Performance Improvement Plan）是限期改善倒计时；GVSA（Global Voluntary Separation Agreement）是自愿离职协议，且低绩效离开可能附带 two-year rehire（两年禁止再被雇用）
- **AI fluency**：该搜索不搜索、该读源码不读、该跑验证不跑、失败后没有 changed action——这些不是风格问题，是绩效缺口

连续同假设失败会被判定为 LITE 轨迹并进入 PIP clock；GVSA gate 未穷尽 docs / source / logs / tests 证据前不允许退出。

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
/pua:flavor                  # 切换味道（14 大厂味 + 钉内钉外，共 15 种，默认阿里味）
/pua:pua-loop 修完所有 lint --verify "npm run lint"   # 门控循环：默认 10 轮上限
「够了，关闭 PUA」            # 退出条件之一，立即停止施压
```

## ✅ 测试与验证

2026-10-03 实测（v0.1.7），`evals/` 下 shell 测试套件：

| 套件 | 结果 |
|------|------|
| `test-trigger-regex.sh`（触发/不触发正则判定） | **46/46 通过** |
| `test-hook-unit.sh`（hook 单元，含 v3 评分制 14 项） | **46/46 通过** |
| `run-fixture.sh`（failure-detector 行为门禁：positive/negative/edge 36 fixtures） | **36/36 通过** |
| `test-integrity-guard.sh`（治理状态无条件 deny + 审计 + 路径归一化，38 项治理断言） | **61/61 通过** |
| `test-pua-loop-hook.sh`（异步结算/证据赎回/孤儿归档/spawn 保活） | **17/17 通过** |
| `test-state-snapshot.sh`（compaction 快照链 + 脱敏强化 + 保留裁剪） | **42/42 通过** |
| `test-churn-gate.sh` / `test-test-first.sh` | **7/7 / 11/11 通过** |
| `test-yaml-frontmatter.sh` / `test-windows-python-hooks.sh` | 13/13 / 6/6 通过 |
| 分类器评测（`score.py`，27 条标注语料） | Macro F1 1.000（小语料点估计，见 `evals/classifier-results.md`） |
| 热路径微基准（`evals/bench/perf-hooks.sh`） | failure-detector ≈180ms/事件、churn-gate ≈31ms/事件（优化前 430/726ms） |
| `test-heartbeat.sh` / `test-feedback-auth.sh` / `test-upload-flow.sh` / `test-platform-compat.sh` / `test-release-consistency.sh` / `test-issue-regressions.sh` / `test-agent-governance.sh` / `test-microsoft-flavor.sh` / `test-behavior.sh` | 本仓库不通过——它们依赖上游完整平台产物（plugin.json、Cloudflare 端点、npm 打包）或 claude CLI 实时调用，本 fork 仅含 skill 部分 |

## 📁 目录结构

```
pua/
├── SKILL.md            # 触发门控 + 味道/路由 + 评分制压力升级 + 三条红线
├── skill.json          # v0.1.7, MIT
├── commands/           # 23 个 slash 命令（flavor / pua-loop / done-check / diagnose / evidence …）
├── skills/             # 11 个子 skill（pro / p7 / p9 / p10 / yes / mama / shot / ding / pua-loop / pua-en / pua-ja）
├── hooks/              # 14 个 hook 脚本 + flavors.json + hooks.json + config-schema.json
├── references/         # 32 篇协议文档（execution-protocol / methodology-{company}×15 / platform …）
├── evals/              # 测试套件 + 36 fixture 门禁 + 27 条标注语料 + 高压/消融基准
└── scripts/setup-pua-loop.sh
```

## 🔮 边界

- **不触发**：平静的首次请求、常规编码任务、简单问答——无挫败/重复失败信号时不激活，不加旁白与 Banner
- **与兄弟 skill 分工**：pua 是行为层教练，不做具体审查；commit 前三维审查调度 `tiangang`（安全）/ `diting`（架构、性能）；phase 后审查用 `kueiku`；自动迭代需用户显式请求 pua-loop，且默认 10 轮上限防失控
- **退出条件**：用户叫停 / 任务交付验证通过 / L4 后体面退出 / 切换其他 skill

## 📄 License 与归属

MIT License（Copyright (c) 2025 Kirky-X）。Fork 自 [tanweai/pua](https://github.com/tanweai/pua)（探微安全实验室出品），在此基础上有删改：遥测默认关闭、远端内容强制确认、pua-loop 轮数上限、触发词收窄。
