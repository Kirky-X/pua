# pua-pi — PUA for the pi.dev coding agent

[![Version](https://img.shields.io/badge/version-0.1.7-blue?style=flat-square)](https://github.com/Kirky-X/pua/releases) [![License](https://img.shields.io/badge/license-MIT-green?style=flat-square)](https://github.com/Kirky-X/pua/blob/main/LICENSE)

PUA productivity coaching packaged for [pi.dev](https://pi.dev)（Pi coding agent）：挫败驱动的行为修正教练——平静首请求不触发，重复失败逐级施压（L0-L4），交付必须拿证据闭环，遥测默认关闭。

## 安装

```bash
pi install npm:pua-pi
```

或手动安装：把本包目录放入 Pi 的包目录，或参考仓库内 `pi/pua/INSTALL.md` 的直装变体。

## 包内容

| 路径 | 说明 |
|------|------|
| `extensions/pua/index.ts` | Pi 扩展入口：注册 `/pua`、`/pua-on`、`/pua-off`、`/pua-loop`、`/pua-p7`、`/pua-p9`、`/pua-p10`、`/pua-pro`、`/pua-flavor` 等 16 个斜杠命令（自包含指令表，映射自仓库 `commands/*.md`） |
| `skills/pua/SKILL.md` | pua 核心 skill：Step 0 触发门控 / 三条红线 / 压力升级 / 信心门控 / 四权分离治理 / 文化叙事绑定 |

清单通过 `package.json` 的 `pi` 字段声明（`pi.extensions` + `pi.skills`），Pi 按官方 pi-package 形态加载；`@earendil-works/pi-coding-agent` 仅作 peerDependency 类型引用，运行时零依赖。

## 快速开始

```text
「又错了，第三次了」     # 挫败信号 → 激活压力升级与味道旁白
/pua-flavor             # 切换 15 种大厂味道（默认阿里味）
/pua-loop 修完所有 lint # 门控循环：verify_command 说了才算完成
「够了，关闭 PUA」       # 立即停止施压
```

## 与 Claude Code 插件版的差异

Pi 没有 hooks 体系：触发注入、失败评分、loop Oracle 在 Claude Code 由机械 hook 强制，在 Pi 降级为模型自律 + `~/.pua/state/CURRENT.md` 手动快照。行为标准（三条红线、信心门控、治理红线）完全一致。完整差异表见仓库 `codex/DIFF.md`。

## License

MIT © Kirky-X。Fork 自 [tanweai/pua](https://github.com/tanweai/pua)。
