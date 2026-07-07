---
name: pua
description: "Thin router shell for /pua and /pua:pua — loads the authoritative ../../SKILL.md for the full protocol. Invoked explicitly via slash command; do not auto-trigger on natural-language frustration."
license: MIT
---

# PUA — 薄壳路由入口（Thin Router Shell）

> ⚠️ 本文件**不是**完整行为协议。权威完整内容在上级 **`../../SKILL.md`**（插件根 `pua/SKILL.md`，296 行）。
> `/pua:pua` 无参数时路由到这里。加载后**立即用 Read 工具读取 `../../SKILL.md`**，按其中的行为协议执行。

## 为什么是薄壳

完整 PUA 协议（三条红线 / 压力升级 L0-L4 / 味道路由 / 失败切换链 / harness 治理 / 任务生命周期）统一由主 `SKILL.md` 单点维护，避免两份副本漂移。本文件只负责三件事：

1. 提供 `/pua:pua` 的加载入口（`name: pua` frontmatter）
2. 指向权威主文件 `../../SKILL.md`
3. 索引子 skill 路由表

**触发词与自然语言触发由主 `SKILL.md` 独占**（`try harder / 别摆烂 / 又错了 / 证据呢 / 没跑测试别说完成 / 验收 / 闭环` 等）。本薄壳不响应自然语言，仅由 `/pua` 显式调用。

## 加载步骤（按序，不可跳步）

1. **Read `../../SKILL.md`** — 完整行为协议、三条红线、压力升级、味道速查、场景黑名单、References 索引
2. **Read `../../references/display-protocol.md`** — Sprint Banner / 进度条 / KPI 卡的 Unicode 方框格式
3. **Read `../../references/methodology-router.md`** — 任务类型 → 起始味道路由表 + 失败切换链
4. 按当前味道 **Read `../../references/methodology-{company}.md`** — 该味道的行为约束。可用：`alibaba` / `bytedance` / `huawei` / `tencent` / `meituan` / `pinduoduo` / `baidu` / `netflix` / `apple`(Jobs) / `tesla`(Musk) / `amazon` / `microsoft` / `jd` / `xiaomi` / `ding`
5. 复杂/高风险任务再 Read `../../references/execution-protocol.md`（失败切换链 / 抗合理化 / 深层换框 / 人味规则 / 任务生命周期）与 `../../references/harness-governance.md`（四权分离 + Task Contract）

> **路径解析**：本文件位于 `<plugin>/skills/pua/SKILL.md`，`../../` = 插件根 `pua/`。
> 若相对路径在当前执行环境下无法解析，用 Glob 搜 `**/pua/SKILL.md`，**选 296 行的权威版**（非本薄壳）。

## 子 skill 路由表

`/pua:pua <子命令>` 或显式请求时，用 Read 加载对应 `skills/<name>/SKILL.md`：

| 子命令          | 路径                       | 用途                                                           |
| --------------- | -------------------------- | -------------------------------------------------------------- |
| `/pua:pro`      | `skills/pro/SKILL.md`      | 自进化基线 + Platform + /pua 指令系统 + Compaction 状态保护    |
| `/pua:p7`       | `skills/p7/SKILL.md`       | P7 骨干方案驱动执行（方案→影响分析→编码→三问自审）             |
| `/pua:p9`       | `skills/p9/SKILL.md`       | P9 Tech Lead：写 Prompt 管 P8 团队，验收闭环                   |
| `/pua:p10`      | `skills/p10/SKILL.md`      | P10 CTO：定战略方向，管 P9                                     |
| `/pua:yes`      | `skills/yes/SKILL.md`      | SB Leader 夸夸鼓励模式（ENFP，70% 鼓励 + 20% 正经 + 10% 戏谑） |
| `/pua:mama`     | `skills/mama/SKILL.md`     | 妈妈唠叨模式（与 yes 互斥）                                    |
| `/pua:shot`     | `skills/shot/SKILL.md`     | 紧凑 all-in-one 注入包 — **仅 sub-agent 注入，不响应自然语言** |
| `/pua:ding`     | `skills/ding/SKILL.md`     | 📌 钉内/钉外味（无招 / 老板体感 / 证据链 / 周报去幻觉）        |
| `/pua:pua-loop` | `skills/pua-loop/SKILL.md` | 自动迭代循环（禁用 AskUserQuestion；`<loop-abort>` 终止）      |
| `/pua:pua-en`   | `skills/pua-en/SKILL.md`   | English PIP 模式 — **仅当用户用英文书写时**                    |
| `/pua:pua-ja`   | `skills/pua-ja/SKILL.md`   | 日本語 詰め 模式 — **仅当用户用日文书写时**                    |

## 加载本 skill 时禁止

- ❌ 用 Skill tool 加载 `pua` 或 `pua:pua`（会触发 router 循环）—— 必须直接 Read 文件
- ❌ 没读 `../../SKILL.md` 前就输出 PUA 旁白 / Sprint Banner / KPI 卡
- ❌ 在平静的首次请求上激活 —— 详见主 `SKILL.md`「场景黑名单」

## 搭配

方法论层 `superpowers:systematic-debugging` + 防虚假完成 `superpowers:verification-before-completion`。
