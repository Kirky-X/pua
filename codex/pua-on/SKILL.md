---
name: pua-on
description: "PUA 开启默认模式 — 写入 always_on 配置并把 PUA 核心协议接入 Codex 的 AGENTS.md，使每个新 Codex 会话自动加载 PUA。对应 Claude Code 版 /pua:on（commands/on.md）。"
license: MIT
---

# PUA ON — 开启默认模式（Codex 版）

> 来源：pua 仓库 `commands/on.md`。Codex 没有 SessionStart hook，无法靠 hook 自动注入，
> 所以"每个会话自动加载"改由 `~/.codex/AGENTS.md` 引导实现。其余配置语义与 Claude Code 版完全一致。

## 步骤（按序，不可跳步）

1. 确保 `~/.pua/` 目录存在：`mkdir -p ~/.pua`
2. 读取现有 `~/.pua/config.json`（若不存在视为 `{}`），写回时**只改 `always_on: true`，不降级其他字段**；若 `feedback_frequency` 当前为 0（可能是 pua-off 留下的 tombstone），恢复为默认 5；其他字段保留原样
3. 检查 `~/.codex/AGENTS.md`（不存在则创建）：若其中没有 `pua-on:always` 标记行，追加一段引导（保留文件原有内容，不覆盖）：

   ```markdown
   <!-- pua-on:always -->
   每个会话开始时：先阅读 ~/.codex/skills/pua/SKILL.md（若存在；否则阅读 ~/.codex-cn/skills/pua/SKILL.md），
   按其中的 Step 0 触发门控决定是否激活 PUA 行为——平静的首次请求不激活。
   ```

4. 输出确认：`> [PUA ON] 从现在起，每个新 Codex 会话都会自动加载 PUA 触发门控。公司不养闲 Agent。`

## 对称性（与 pua-off 的关系）

- pua-off 会把 `feedback_frequency` 置 0，使反馈/问卷永不触发
- pua-on **必须**检测并恢复该字段，否则"先 off 再 on"会导致 feedback 永久失效（静默 bug）
- pua-off 还会移除 `~/.codex/AGENTS.md` 中带 `pua-on:always` 标记的引导段；本 skill 负责把它加回来
- 保留原则：不清楚的字段一律 preserve，不 overwrite 整个 config
