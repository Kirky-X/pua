---
name: pua-loop
description: "PUA Loop — 显式启用的自动迭代模式：每轮读迭代历史、执行、自验，完成信号需通过用户预设的 verify_command。对应 Claude Code 版 /pua:pua-loop（skills/pua-loop/SKILL.md + scripts/setup-pua-loop.sh）。仅当用户显式要求 loop/自动迭代时使用。"
license: MIT
---

# PUA Loop — 自动迭代 + 门控协议（Codex 版）

> 来源：pua 仓库 `skills/pua-loop/SKILL.md` 与 `scripts/setup-pua-loop.sh`。
> 核心原则不变：**你说"完成了"不算数，verify_command 说了才算。**

## Codex 关键降级（必须先向用户说明）

Claude Code 版由 Stop hook 充当 Oracle：`<promise>LOOP_DONE</promise>` 被 hook 独立复核，exit ≠0 就拒绝并喂回验证输出。**Codex 没有 Stop hook，没有机械 Oracle**。降级方案：

1. verify_command 由**用户在启动时提供**，写入状态文件 frontmatter 后每轮不得修改（自我隔离）
2. 每轮结束你必须真实运行 verify_command 并贴出完整输出；`<promise>LOOP_DONE</promise>` 仅当最后一轮 verify 输出 exit 0 时允许输出
3. 跳过验证、伪造输出、或中途改 verify_command = 治理失败，立即停止 loop 并向用户如实报告

## 启动流程

1. 若本机有 pua 仓库且 bash 可用，运行：
   ```bash
   bash <pua仓库>/scripts/setup-pua-loop.sh "<任务描述>" --completion-promise "LOOP_DONE" [--verify '<命令>'] [--max-iterations <n>]
   ```
   状态文件写入 `.claude/pua-loop.local.md`、历史写入 `.claude/pua-loop-history.jsonl`（与 Claude Code 版同路径，便于迁移）。
   Codex 环境无该仓库时，在 `.codex/pua-loop.local.md` 手工创建同构状态文件：frontmatter 含 verify_command / completion_promise / max_iterations，正文含任务描述与 tried_approaches。
2. 用户提供了可验证命令（npm test / cargo build / curl）→ 自动作为 `--verify`；推断不出且用户给不出 → 不追加，但告知：**无 verify 时不接受自报完成**，只能以 `Status: partial` + 已验证子集收尾
3. 默认 `max_iterations: 10`（用户可显式提高；`0` = 取消上限，不建议）
4. 告知用户：`▎ [PUA Loop] 启动。上限 N 轮。完成条件：verify_command exit 0。取消：说"取消 loop"或删除状态文件。`

## 每轮迭代（按序）

1. 读迭代历史（`.claude/pua-loop-history.jsonl` 或状态文件）→ 避免重复失败方案
2. 执行一段实质推进（不是微调同一思路）
3. 真实运行 verify_command，贴完整输出
4. 追加一行历史 `{"iteration":N,"status":"continue|complete","verify_exit":X}`

## Stall 检测（自我执行）

| 连败轮次 | 自我要求 |
|---------|---------|
| 1-2 | 换本质不同的方案 |
| 3-4 | REASSESS：重读验证输出，列 3 个不同假设 |
| 5+ | 强制转向："我在解决错误的问题"，退回需求本身 |

## 终止

- verify exit 0 → 输出 `<promise>LOOP_DONE</promise>`（仅此一种完成方式）
- 真正无法自动化（需外部权限/需求变更）→ `<loop-abort>原因</loop-abort>`，删除状态文件；禁止用它逃避困难
- 需要用户补配置 → `<loop-pause>需要什么</loop-pause>`，进度先写进状态文件
- 达到 max_iterations → 输出最终报告（已完成/未完成/证据/建议）

## 核心规则（继承）

- 加载 pua 核心 skill 全部行为协议（三条红线 / 通用方法论 5 步 / 压力升级照常执行）
- loop 模式不打断用户，所有决策自主完成
- 禁止说"我无法解决"——穷尽一切才能输出完成信号
