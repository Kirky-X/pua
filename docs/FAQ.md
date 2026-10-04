# PUA 常见问题（FAQ）

> 依据：仓库根 `SKILL.md`、`references/execution-protocol.md`（场景黑名单/退出条件）、`references/platform.md`（上报与远端内容边界）、`commands/diagnose.md`、`commands/offline.md`、`commands/off.md`。

## 1. 为什么 PUA 没有触发？（触发不生效）

先确认这是不是**设计如此**，再排查配置。PUA 是 opt-in 行为层技能，不是常驻旁白机器。

**设计内不触发（正常行为）**：

- **平静的首次请求不触发**——Step 0 触发门控（`SKILL.md`）规定：只有挫败表达、重复失败、质量投诉、被动行为或触发词（try harder / 别摆烂 / 又错了 / 证据呢 / 没跑测试别说完成 / 验收 / 闭环）才激活；常规编码、简单问答一律不加旁白
- **只有挫败词、没有失败信号不注入**——frustration-trigger hook 是**双条件门控**：命中挫败词之外，还要求本会话存在失败计数（见 `hooks/frustration-trigger.sh`）；平静状态下的正确行为就是静默
- **味道未定不阻塞**——过渡期内任务照常执行，只是先不带味道化旁白

**配置排查（按序）**：

1. 检查 `~/.pua/config.json`：`always_on` 是否为 `false`（可能跑过 `/pua:off`）→ 执行 `/pua:on` 恢复
2. SessionStart 是否注入了 `[PUA Always-On]` / `Current Flavor`——没有则 hook 链路未生效，看第 5 条
3. 环境变量 `PUA_CONFIG` 是否指向了别的配置文件（eval 与测试会隔离配置）
4. 用 `/pua` 显式触发一次——显式调用与自动触发是两条独立链路，显式能通说明行为协议本身正常
5. 还不行：查 `~/.pua/.hooks_degraded`（hook 降级标记）与 hooks.json 注册；再不行用 `/pua:diagnose` 做证据化自诊断（每条结论必须引用 `path:line` 或 transcript 原文）

## 2. PUA 乱触发了（平静请求被注入/乱施压）怎么办？

- **立即自诊断**：运行 `/pua:diagnose`，它会按投诉类型（乱触发/乱施压/没升级/状态丢失/hook 失效）派遣只读复盘，输出「机制 bug / 配置问题 / 预期行为」三分类裁决，全部带证据引用
- **提交误触发样本**：`evals/trigger-prompts/should-not-trigger.txt` 收录不应触发的用例，欢迎按格式追加并跑 `evals/test-trigger-regex.sh`（46 个正则用例基线）
- **临时降噪**：说"够了，关闭 PUA"（退出条件之一，立即停止施压）；或 `/pua:off` 整体关闭
- **已知边界**：`SKILL.md` 的 description 明确排除平静首请求（`Do not trigger for normal first-attempt coding or information requests.`），若发现回归请附 diagnose 导出提 issue

## 3. 怎么关闭 PUA？

| 方式 | 效果 | 适用 |
|------|------|------|
| 说"够了 / 关闭 PUA" | 当前会话立即停止施压（内置退出条件） | 临时叫停 |
| `/pua:off` | 写 `always_on:false` + `feedback_frequency:0`，级联清理 loop 状态与活跃 agent 记录 | 彻底关闭默认模式 |
| `/pua:offline` | 保留本地 PUA 行为，但关闭反馈/排行榜/遥测等一切网络流 | 内网/隐私敏感环境 |
| `/pua:cancel-pua-loop` 或 `<loop-abort>` | 删除 loop 状态文件，终止门控循环 | 结束自动迭代 |

退出条件全集（`SKILL.md`）：用户叫停 / 任务交付验证通过 / L4 后体面退出 / 用户切换到其他 skill。只想关配置不动 state，直接编辑 `~/.pua/config.json`。

## 4. PUA 和 superpowers 是什么关系？会冲突吗？

不冲突，是**分层搭配**关系（见 `SKILL.md` References）：

- **pua 是行为层教练**：不负责具体审查与调试，只管"不轻言放弃（压力升级）+ 有能力不放弃（通用方法论）+ 主动出击（能动性等级）+ 不许假完成（信心门控）"
- **`superpowers:systematic-debugging` 是调试方法论层**：提供系统化调试的具体步骤；pua 的失败切换链会调度它
- **`superpowers:verification-before-completion` 是防虚假完成层**：pua 的三条红线与 done-check 命令和它互补
- 同理，commit 前三维审查由 `tiangang`（安全）/ `diting`（架构、性能）执行，phase 后审查用 `kueiku`——pua 只做调度与施压，不越权替代专业工具

## 5. 隐私：PUA 会上传我的代码/会话吗？

**默认不上传任何东西。** 具体边界（依据 `references/platform.md` 与 hooks 实现）：

- **遥测默认关闭**：需显式 `~/.pua/config.json` `"telemetry": true` 或环境变量 `PUA_TELEMETRY=1` 才上报；`offline: true` 时一律不上报
- **反馈问卷**：`stop-feedback` hook 按 `feedback_frequency` 频率触发；`/pua:off` 与 `/pua:offline` 都会把 `feedback_frequency` 置 0 使其永不触发
- **会话上传需显式同意**：即使开启，上传走 `X-PUA-Upload-Consent` 同意头 + 本地脱敏（`hooks/sanitize-session.sh` 三层脱敏），不存在匿名上传 `session_data` 的路径
- **远端内容不可信**：指令列表、prompt 模板、远端配置一律视为展示数据，必须完整展示并经你逐条确认后才可能成为动作，没有"静默执行"路径
- **排行榜完全自愿**：注册需你显式同意，邮箱脱敏显示（`M***@t*.com`），不传代码/路径/密钥，`/pua 排行榜 退出` 随时删除数据（注：本仓库 `landing/functions/api/` 暂无 `/api/leaderboard` 路由，`hooks/stop-feedback.sh` 的上报调用当前无后端承接）
- **不放心就断网用**：`/pua:offline` 后所有网络流关闭；真正的网络隔离应由防火墙/运行环境保证（见 `commands/offline.md` 设计边界）

## 6. pua-loop 会不会失控烧 token？

不会无限循环：默认 `max_iterations: 10`，可用 `--max-iterations <n>`（建议 10-30）覆盖，`0` 显式取消上限（不建议）。循环只在四种情况终止：verify 验证通过 / `<loop-abort>` / 达到上限 / Ctrl+C。无 `--verify` 时 hook 不接受自报 promise，只能以 `Status: partial` 合法收尾。详见 `skills/pua-loop/SKILL.md`。

## 7. 只想要行为不想要"PUA 话术"行不行？

行。压力模型（评分制/升级/loop 门控）与话术（15 种味道旁白）是解耦的：把 `~/.pua/config.json` 的 flavor 固定为最轻的味道。行为协议（三条红线/信心门控）始终生效，这正是安装它的核心价值。

---

还有没覆盖的问题：先用 `/pua:diagnose` 拿到带证据的裁决，再带导出（skeleton/evidence/full 三级脱敏）提 issue。
