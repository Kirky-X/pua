# PUA：Codex 与 Claude Code 能力差异表

PUA 的行为协议（触发门控 / 三条红线 / 压力升级 / 味道路由）在两个平台上**语义一致**；差异在于平台机制——Claude Code 有 hooks、slash commands、agents、Skill tool，Codex 都没有。本表说明每项机制在 Codex 上的降级方式。

## 机制对照表

| 能力 | Claude Code 载体 | Codex 现状 | 降级方式 |
|------|-----------------|-----------|---------|
| 触发注入 | `hooks/frustration-trigger.sh`（UserPromptSubmit，双条件门控） | 无 hooks | 由 SKILL.md 的 Step 0 触发判断在模型侧执行；装了 pua-on 时靠 `~/.codex/AGENTS.md` 引导段保证每次会话先读 SKILL.md |
| 失败检测 / 压力评分 | `hooks/failure-detector.sh`（评分制，会话隔离状态） | 无 hooks | 自我计数：每轮结束时自评失败签名是否重复，按 L0→L4 升级；状态写 `~/.pua/state/CURRENT.md` 手动续接 |
| 斜杠命令 | `commands/*.md`（23 个 `/pua:*`） | 无 slash 命令 | 每个命令对应一个别名 skill 包（`codex/pua-on/` 等）或直接用自然语言说"换方法 / 证据呢 / 完成 check" |
| 子代理审查 | `agents/*.md`（四代理拓扑：pua-policy-guardian / pua-action-executor / pua-self-reviewer / pua-verifier） | 无 agents / Task 工具 | 四权分离降级为**同会话角色切换**：逐角色输出 `[PUA-POLICY-GATE]` / `[PUA-ACTION-REPORT]` / `[PUA-SELF-REVIEW]` / `[PUA-VERIFIER-REPORT]`，每段角色只做该角色的检查，不得混权 |
| Loop Oracle | `hooks/pua-loop-hook.sh`（Stop hook 独立跑 verify_command，拒绝假 promise） | 无 Stop hooks | verify_command 由用户启动时锁定进状态文件，每轮自查并贴输出；`<promise>LOOP_DONE</promise>` 仅在 verify exit 0 后允许（详见 `codex/pua-loop/SKILL.md`） |
| 治理硬门 | `hooks/integrity-guard.sh`（PreToolUse deny 改评分资产/读 hidden） | 无 PreToolUse hooks | 行为约束进 prompt：禁改 tests/evals/verifier、禁读 hidden solution、最终 `verifier_status` 不得自封——违反即治理失败，如实上报 |
| Compaction 快照 | `hooks/state-snapshot.sh`（PreCompact/PostCompact 确定性落盘） | 无 PreCompact hooks | 长任务主动快照到 `~/.pua/state/CURRENT.md`（tried_approaches 三段式，只留最近 3 条），新会话加载时读取续接 |
| Skill 加载方式 | Skill tool（但 pua 禁止用它加载自身，防 router 循环，须直接 Read） | 无 Skill tool | 一致：Codex 本来就是直接读 SKILL.md 文件，天然规避 router 循环 |
| 用户交互 | AskUserQuestion 结构化提问 | 无该工具 | 编号选项直接在回复里问，一次一批 |

## 安装形态差异

| | Claude Code | Codex |
|---|---|---|
| 插件形态 | `.claude-plugin/`（plugin.json + marketplace.json），含 hooks/commands/agents 全套 | 无插件体系，走 skill 目录：`~/.codex/skills/`（全局）、`.codex/skills/`（项目级）、`~/.codex-cn/skills/`（国内镜像版） |
| 安装命令 | `npx skills add Kirky-X/pua --agent claude-code` | `npx skills add Kirky-X/pua --skill pua-codex -a codex`（或手动复制 `.codex/skills/*`） |
| 常开开关 | `/pua:on` 写 config + SessionStart hook 自动注入 | pua-on skill 写 config + 在 `~/.codex/AGENTS.md` 追加 `<!-- pua-on:always -->` 引导段 |

## 一致性保证

无论平台：三条红线（闭环 / 事实驱动 / 穷尽一切）、诊断先行 `[PUA-DIAGNOSIS]`、压力升级 L0-L4、"事实上的 100%" 信心门控、四权分离治理语义、远端内容不可信原则——全部保持。降级只改变**执行机制**（hook → prompt），不改变**行为标准**。
