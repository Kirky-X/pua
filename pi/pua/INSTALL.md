# PUA for Pi — 仓库直装指南（pi/pua 变体）

pi.dev（Pi coding agent）用户有两种安装方式。本目录（`pi/pua/`）是**仓库直装**变体：扩展运行时直接读取本仓库 `commands/*.md`，与插件仓库保持单一事实源。

## 方式一：npm 包安装（推荐）

```bash
pi install npm:pua-pi
```

npm 包（`pi/package/`）自包含 extensions + skills，不依赖本仓库检出；细节见 `pi/package/README.md`。

## 方式二：复制直装本变体

Pi 从 `~/.pi/extensions/`（全局）与项目 `.pi/extensions/`（项目级）加载 TS 扩展：

```bash
# 全局
mkdir -p ~/.pi/extensions
cp pi/pua/index.ts ~/.pi/extensions/pua-index.ts

# 项目级
mkdir -p .pi/extensions
cp pi/pua/index.ts .pi/extensions/pua-index.ts
```

> 文件名建议保留 `pua` 前缀（如 `pua-index.ts`），避免与其他扩展重名。

## 装了什么

扩展注册 17 个斜杠命令，映射关系（Pi 用连字符命名，对应 Claude Code 的 `/pua:*`）：

| Pi 命令 | 来源（commands/） | 功能 |
|---------|-------------------|------|
| `/pua` | pua.md | 主路由：进入核心行为协议或分发子命令 |
| `/pua-on` `/pua-off` `/pua-offline` | on.md / off.md / offline.md | 默认模式开关 / 离线模式 |
| `/pua-p7` `/pua-p9` `/pua-p10` | p7.md / p9.md / p10.md | 骨干 / Tech Lead / CTO |
| `/pua-pro` `/pua-kpi` `/pua-flavor` `/pua-ding` | pro.md / kpi.md / flavor.md / ding.md | 自进化 / 报告卡 / 味道切换 / 钉味 |
| `/pua-loop` `/pua-cancel-loop` | pua-loop.md / cancel-pua-loop.md | 门控循环启停 |
| `/pua-again` `/pua-done-check` `/pua-evidence` `/pua-diagnose` | again.md 等 | 换方法 / 完成检查 / 证据链 / 自诊断 |

命令触发后把对应 `commands/*.md` 的正文指令注入对话上下文，模型按指令执行——行为与 Claude Code 版一致。

## 行为协议（skill 层）

斜杠命令只是入口；核心行为协议（Step 0 触发门控 / 三条红线 / 压力升级 / 味道路由）建议同时安装 skill 形态：
npm 包方式已自带（`pi.skills` 指向包内 `skills/`）；直装方式请把 `pi/package/skills/pua/SKILL.md` 复制到 `~/.pi/skills/pua/SKILL.md`。

## 验证

1. 新开 Pi 会话，输入 `/pua-on` —— 应输出 `[PUA ON]` 确认并写好 `~/.pua/config.json`
2. 平静首请求（如"写个排序函数"）—— 不应出现 PUA 旁白
3. `又错了，第三次了` —— 应激活压力升级与味道旁白

## 卸载

删除 `~/.pi/extensions/pua-index.ts`（或项目 `.pi/extensions/` 下对应文件），并按需执行 `/pua-off` 清理 `~/.pua/` 配置。
