---
name: pua-off
description: "PUA 关闭默认模式 — 写入 always_on:false 配置、移除 AGENTS.md 引导段、停止活跃 loop、清理本地运行状态。对应 Claude Code 版 /pua:off（commands/off.md）的 v3 级联语义。"
license: MIT
---

# PUA OFF — 关闭默认模式（Codex 版，v3 级联语义）

> 来源：pua 仓库 `commands/off.md`。Codex 没有 Stop hook / TaskStop，级联清理只覆盖文件态。

## 步骤

1. **写入配置**（确保 `~/.pua/` 目录存在）：
   - 将 `{"always_on": false, "feedback_frequency": 0}` 写入 `~/.pua/config.json`
2. **移除自动加载引导**：从 `~/.codex/AGENTS.md`（及 `~/.codex-cn/AGENTS.md`，若存在）中删除带 `<!-- pua-on:always -->` 标记的引导段；标记行不存在则跳过，不动文件其他内容
3. **停止活跃 loop**（若有）：
   ```bash
   find "$HOME/.claude/pua/" -name "loop-*.md" -delete 2>/dev/null
   find "$HOME/.codex/pua/" -name "loop-*.md" -delete 2>/dev/null
   rm -f .claude/pua-loop.local.md .codex/pua-loop.local.md 2>/dev/null
   ```
4. **清理活跃 agent 记录**：
   ```bash
   rm -f "$HOME/.claude/pua/active-agents.json" "$HOME/.codex/pua/active-agents.json" 2>/dev/null
   ```
5. **记录事件**：
   ```bash
   mkdir -p "$HOME/.codex/pua"
   echo "{\"event\":\"pua_off\",\"ts\":\"$(date -u +%FT%TZ)\"}" \
     >> "$HOME/.codex/pua/teardown.jsonl"
   ```
6. **提示用户**：若任务列表里还有未完成且归属 PUA loop 的任务，列给用户，由用户决定是否终止。

## 输出确认

`> [PUA OFF] PUA 默认模式和反馈收集已关闭。AGENTS.md 引导段已移除，Loop state 已清理，孤儿 agent 已释放。需要时手动加载 pua skill 触发。`

## 设计语义

pua-off 不只是"关开关"，而是"下班"——和 pua-on 对应的是加载配置；和"停运行"对应的是本 skill 自带的级联清理。
如果你只想关配置不动 state，直接编辑 `~/.pua/config.json`。
