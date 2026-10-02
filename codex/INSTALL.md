# PUA for Codex — 安装指南

PUA 在 Codex（OpenAI Codex CLI / 国内镜像版）上以 **skill 包**形态运行。两条安装路径任选其一；装完建议按第 3 节做冒烟验证。

## 1. 方式一：skills CLI 一键安装（推荐）

使用 [`skills` CLI](https://github.com/vercel-labs/skills)（`npx skills add`），从 GitHub 仓库直接把 skill 包装进 Codex：

```bash
# Codex 专用治理版（推荐，含 Codex 无 hooks 的降级协议）
npx skills add Kirky-X/pua --skill pua-codex -a codex -y

# 中文主协议 + 英文 PIP 版（按需追加）
npx skills add Kirky-X/pua --skill pua -a codex -y
npx skills add Kirky-X/pua --skill pua-en -a codex -y

# 斜杠别名包（pua-on / pua-off / pua-p7 / pua-p9 / pua-p10 / pua-pro / pua-loop）
npx skills add Kirky-X/pua --skill pua-on -a codex -y
```

- `-a codex` 指定目标 agent，skill 会装入 `~/.codex/skills/<skill-name>/SKILL.md`
- 若你使用国内镜像版 Codex（`codex-cn`），加 `-a codex-cn` 或手动复制到 `~/.codex-cn/skills/`
- 不确定支持哪些 agent 时先跑 `npx skills add Kirky-X/pua --help` 查看列表

## 2. 方式二：手动安装（marketplace/CLI 不可用时）

```bash
git clone https://github.com/Kirky-X/pua.git
# 全局（对所有项目生效）
mkdir -p ~/.codex/skills
cp -r pua/.codex/skills/pua pua/.codex/skills/pua-en pua/.codex/skills/pua-codex ~/.codex/skills/
cp -r pua/codex/pua-on pua/codex/pua-off pua/codex/pua-p7 pua/codex/pua-p9 pua/codex/pua-p10 pua/codex/pua-pro pua/codex/pua-loop ~/.codex/skills/
# 国内镜像版目录
mkdir -p ~/.codex-cn/skills
cp -r pua/.codex/skills/* ~/.codex-cn/skills/

# 项目级（只对当前仓库生效）
mkdir -p .codex/skills
cp -r /path/to/pua/.codex/skills/* .codex/skills/
```

不想装 skill 包的最轻量方式：把 `codex/pua.md`（主提示词包）粘进 `~/.codex/AGENTS.md`——但注意这只是规则粘贴，不构成 skill 包，建议优先用上面的 SKILL.md pack。

## 3. 冒烟验证

1. 新开 Codex 会话，问一句平静的首次请求（如"帮我写个排序函数"）——**不应**出现 PUA 旁白（Step 0 触发门控：平静首请求不触发）
2. 再说一句 `又错了，第三次了，再试试`——应激活 PUA：输出带味道旁白，卡壳时输出 `[PUA-DIAGNOSIS]` 三段
3. 需要每次会话自动加载时，运行 pua-on skill（会把引导段写进 `~/.codex/AGENTS.md`，标记 `<!-- pua-on:always -->`）

## 4. 与完整插件版的差异

Codex 没有 hooks / slash commands / subagent 体系，hook 类能力（failure-detector、pua-loop Oracle、integrity-guard）按 `codex/DIFF.md` 的降级表处理。能力边界详见 `DIFF.md`。
