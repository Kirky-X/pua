---
description: "PUA Diagnose — 用于 pua 乱触发/乱施压/压力没升级/状态丢失/该触发没触发等投诉的自诊断。证据化复盘当前或指定会话。"
argument-hint: "[complaint-or-session-path]"
---

启用 **PUA Diagnose / 自诊断复盘**。

适用投诉：乱触发（平静请求被注入）、乱施压（良性失败被升级）、压力没升级（重复失败却静默）、状态丢失（compaction 后没恢复）、hook 降级。

## 铁律

**每条结论必须引用证据：`path:line`（hook 脚本/状态文件）或 transcript 原文行。无引用即无结论。** 数字必须从 transcript/状态文件现场计算，禁止凭记忆。

## 步骤

1. **定位输入**：确定要复盘的 transcript 路径（参数给了就用参数的；否则用当前会话 transcript）+ 相关状态目录（`~/.pua/sessions/`、`~/.pua/loop-memory.json`、`~/.pua/.hooks_degraded`、`~/.pua/audit.jsonl`）。
2. **按投诉类型选维度，并行派遣独立 subagent**（每个维度一个，独立上下文，只读）：

| 投诉 | 先查的维度 |
|------|-----------|
| 乱触发 | 触发判定：frustration-trigger.sh 的 EXPLICIT_RE/FRUSTRATION_RE 命中行 + 当时 transcript 上下文 |
| 乱施压 | 压力路径：failure-detector.sh 对每条 Bash 的判定（是否 probe/环境豁免漏判）+ sessions/&lt;sid&gt;.json 的 score 轨迹 |
| 没升级 | 计数链：sessions/&lt;sid&gt;.json 是否存在、session_id 是否一致、分数是否到达阈值 |
| 状态丢失 | 快照链：state/CURRENT.md 是否生成、mtime、events/ jsonl、.hooks_degraded 内容 |
| hook 失效 | 降级链：.hooks_degraded、jq 可用性、hooks.json 注册与 timeout |

3. **每个维度输出**：时间线（事件 → 证据引用）→ 判定（是机制缺陷、配置问题还是预期行为）→ 修复建议（具体到文件与改法）。
4. **汇总裁决**：区分「机制 bug（需修代码）」/「配置问题（改 ~/.pua/config.json）」/「预期行为（附解释）」。预期行为也要给证据，不允许无引用开脱。

## 导出（可选）

用户要求附 bug report 时，生成三级脱敏导出：

- `skeleton`：只有结论与引用行号，无原文
- `evidence`：结论 + 引用的证据行（路径/密钥/IP 脱敏，参考 hooks/sanitize-session.sh 的三层脱敏）
- `full`：完整时间线（同样脱敏）

导出前必须过 `hooks/sanitize-session.sh` 同款脱敏正则；脱敏不彻底不许交付。
