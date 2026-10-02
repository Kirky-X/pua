# PUA — 挫败驱动的行为修正教练技能

> 用大厂绩效文化话术驱动 AI agent 穷尽方案、拿证据闭环的教练技能。带失败升级、方法论路由与门控循环；平静首请求不触发，遥测默认关闭。

[![Version](https://img.shields.io/badge/dynamic/yaml?url=https%3A%2F%2Fraw.githubusercontent.com%2FKirky-X%2Fpua%2Fmain%2Fskill.json&query=%24.version&label=version&style=flat-square)](https://github.com/Kirky-X/pua/releases) [![GitHub Release](https://img.shields.io/github/v/release/Kirky-X/pua?style=flat-square)](https://github.com/Kirky-X/pua/releases) [![GitHub License](https://img.shields.io/github/license/Kirky-X/pua?style=flat-square)](LICENSE)

中文 | [English](README_EN.md)

三重能力：**PUA 话术**让 AI 不轻言放弃；**调试方法论**让 AI 有能力不放弃；**能动性鞭策**让 AI 主动出击而非被动等待。

## ✨ 功能特性

- **触发门控（Step 0）**：仅当用户表达挫败、重复失败、质量投诉、被动行为或命中触发词时激活；平静首请求不触发，场景黑名单见 `references/execution-protocol.md`。46 个正则触发用例实测 46/46 通过
- **14 种大厂味道 + 钉内钉外职场纪律味（共 15 种）**：大厂——阿里 / 字节 / 华为 / 腾讯 / 百度 / 拼多多 / 美团 / 京东 / 小米 / Netflix / Musk / Jobs / Amazon / Microsoft（微软味为绩效制度味：Connects / Impact Descriptor / SLITE / LITE / PIP / GVSA）；职场纪律——钉内钉外。每种绑定专属方法论；接任务时按任务类型自动路由（Debug→华为 RCA、新功能→Musk Algorithm、代码审查→Jobs 减法等），用户 config 手动设置优先
- **评分制压力升级（v0.1.7）**：真实失败扣分（同签名重复渐进加权 ×1/×2.5/×5）、验证成功回血、级别阈值 L1≤-30 / L2≤-100 / L3≤-200 / L4≤-350；良性只读探测（grep/diff/test 等 exit 1）与环境错误不产生压力分，探测空转走 IDLE 提示；压力状态按会话隔离（`~/.pua/sessions/<sid>.json`），空转签名记入跨会话 loop 记忆（30 天 TTL），违抗 SPINNING 警告额外加压；失败模式分析区分 SPINNING / EXPLORING / MIXED / LOOP-SHUFFLE
- **三条红线**：闭环意识（说完成必须贴验证输出）、事实驱动（归因前先验证）、穷尽一切（5 步方法论走完才许说不行）
- **确定性门控兜底（v0.1.7）**：`churn-gate` 按变更规模（净 ≥400 行或翻动 ≥800 行）强制触发 commit 前三维审查；`test-first` 以 red-green 状态机抓「源码改动未见测试」与「空洞测试」（没见红就过的测试）
- **pua-loop 门控循环**：`verify_command` 由用户启动时设定、嵌入状态文件；v0.1.7 起 loop/压力状态文件纳入 integrity-guard **硬 deny + 审计日志**（Oracle 隔离从宣称做成机制，agent 自改即拒），verify 改为后台运行、下次 Stop 结算（异步 FAIL 阻塞下一次 Stop）；无 verify 时提供确定性证据赎回通道（命令/验证/产物三路证据）与 `Status: partial` 合法收尾
- **11 个子 skill + 23 个命令**：`/pua:pro`（自进化）、`/pua:p7` / `p9` / `p10`（骨干 / Tech Lead / CTO）、`/pua:yes`（夸夸模式）、`/pua:mama`（妈妈唠叨）、`/pua:ding`（钉味）、`/pua:pua-loop`（自动迭代）、`/pua:pua-en` / `pua-ja`（英 / 日版）；命令如 `/pua:flavor`、`/pua:again`、`/pua:done-check`、`/pua:diagnose`（乱触发/乱施压自诊断）、`/pua:evidence`、`/pua:kpi`
- **安全与隐私（2026-09 修复后行为）**：遥测默认关闭，需显式 `PUA_TELEMETRY=1` 或 config `"telemetry": true` 才上报（`offline` 模式下一律不上报）；远端返回内容一律视为不可信展示数据，须完整展示并获用户逐条确认后才可作为动作，无「静默执行」路径
- **Hooks 体系（v0.1.7 共 14 个脚本）**：frustration-trigger / failure-detector（评分制）/ churn-gate / test-first / state-snapshot（PreCompact/PostCompact 确定性快照，脱敏原子写 `~/.pua/state/CURRENT.md`，不再依赖模型自觉写 journal）/ session-restore（优先注入快照 + hook 降级宣告）/ heartbeat / pua-loop-hook / integrity-guard（治理状态硬 deny + audit.jsonl）等。热路径已做 spawn 收敛优化（get_flavor 单次批量加载）， hook 时延实测见 `evals/bench/perf-hooks.sh`

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

修 bug 场景自动路由华为味（RCA+蓝军）、部署运维走阿里味（闭环）等；子 agent 派活时须直接 Read 本 skill 的 SKILL.md 注入行为，不用 Skill tool 加载（避免 router 循环）。

## ✅ 测试与验证

2026-10-03 全量实测（v0.1.7），`evals/` 下 **17 个套件 + fixture 门禁 + 分类器评测全部通过**：

| 套件 | 结果 |
|------|------|
| `test-trigger-regex.sh`（触发/不触发正则判定） | **46/46** |
| `test-hook-unit.sh`（hook 单元，含 v3 评分制 14 项） | **46/46** |
| `run-fixture.sh`（failure-detector 行为门禁：36 fixtures） | **36/36** |
| `test-integrity-guard.sh`（治理硬 deny + 审计 + 路径归一化，38 项治理断言） | **61/61** |
| `test-pua-loop-hook.sh`（异步结算/证据赎回/孤儿归档/spawn 保活） | **17/17** |
| `test-state-snapshot.sh`（compaction 快照链 + 脱敏强化 + 保留裁剪） | **42/42** |
| `test-churn-gate.sh` / `test-test-first.sh` | **7/7 / 11/11** |
| `test-yaml-frontmatter.sh` / `test-windows-python-hooks.sh` | **24/24 / 6/6** |
| `test-issue-regressions.sh`（历史 issue 回归全 sweep） | **34/34** |
| `test-heartbeat.sh` / `test-feedback-auth.sh` / `test-upload-flow.sh` | **29/29 / 10/10 / 20/20** |
| `test-microsoft-flavor.sh` / `test-platform-compat.sh` | **28/28 / 2/2** |
| `test-release-consistency.sh`（5 清单版本一致 + 18 项治理术语） | **OK** |
| `test-agent-governance.sh`（四代理治理拓扑） | **OK** |
| `test-behavior.sh`（claude CLI 端到端行为） | 未登录环境自动 SKIP（`claude /login` 后可跑） |
| 分类器评测（`score.py`，27 条标注语料） | Macro F1 1.000（小语料点估计，见 `evals/classifier-results.md`） |
| 热路径微基准（`evals/bench/perf-hooks.sh`） | failure-detector ≈180ms/事件、churn-gate ≈31ms/事件（优化前 430/726ms） |

`test-behavior.sh` 依赖 claude CLI 登录态与实时调用（每次 ≤90s，全程约 10 分钟），断言为模型行为级、存在天然方差，未登录时预检自动 SKIP；触发逻辑由 `test-trigger-regex.sh`（46/46）确定性覆盖。`evals/pressure/` 与 `evals/bench/` 为高压基线与三臂消融运行器（默认 dry-run，`PUA_RUN_LIVE=1` 真跑）。`trigger-prompts/` 收录 38 条应触发 + 36 条不应触发用例，供 `run-trigger-test.sh`（需 claude CLI）做端到端验证。

## 📁 目录结构

```
pua/
├── SKILL.md            # 触发门控 + 味道/路由 + 评分制压力升级 + 三条红线 + 信心门控
├── skill.json          # v0.1.7, MIT
├── commands/           # 23 个 slash 命令（flavor / pua-loop / done-check / diagnose / evidence …）
├── skills/             # 11 个子 skill（pro / p7 / p9 / p10 / yes / mama / shot / ding / pua-loop / pua-en / pua-ja）
├── hooks/              # 14 个 hook 脚本 + flavors.json + hooks.json + config-schema.json
├── agents/             # 四代理治理拓扑（policy-guardian / action-executor / self-reviewer / verifier）
├── references/         # 32 篇协议文档（execution-protocol / methodology-{company}×15 / platform …）
├── evals/              # 17 个测试套件 + 36 fixture 门禁 + 27 条标注语料 + 高压/消融基准
├── landing/            # Cloudflare Pages 平台（feedback/upload/heartbeat 端点 + D1 迁移 + 上传/管理页）
├── codex/  .codex/  pi/  # Codex / Pi 多平台发布包（别名 skill、扩展入口、npm 包）
└── scripts/setup-pua-loop.sh
```

## 🔮 边界

- **不触发**：平静的首次请求、常规编码任务、简单问答——无挫败/重复失败信号时不激活，不加旁白与 Banner
- **与兄弟 skill 分工**：pua 是行为层教练，不做具体审查；commit 前三维审查调度 `tiangang`（安全）/ `diting`（架构、性能）；phase 后审查用 `kueiku`；自动迭代需用户显式请求 pua-loop，且默认 10 轮上限防失控
- **退出条件**：用户叫停 / 任务交付验证通过 / L4 后体面退出 / 切换其他 skill

## 📄 License 与归属

MIT License（Copyright (c) 2025 Kirky-X）。Fork 自 [tanweai/pua](https://github.com/tanweai/pua)（探微安全实验室出品），在此基础上有删改：遥测默认关闭、远端内容强制确认、pua-loop 轮数上限、触发词收窄。
