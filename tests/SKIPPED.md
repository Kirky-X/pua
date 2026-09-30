# pua tests/SKIPPED.md — 冒烟套件未覆盖项及原因

范围口径：本套件只覆盖 `scripts/`（即 `setup-pua-loop.sh`）。
hooks/ 与 evals/ 不在本次范围——hooks 已有独立的 shell 测试套件
`evals/test-*.sh`（17 个），由各仓自身维护。

## 未覆盖路径及原因

| 未覆盖路径 | 位置 | 原因 |
| --- | --- | --- |
| PUA loop 真实运行（hook 拦截 → promise 校验 → 迭代推进） | `hooks/pua-loop-hook.sh` + Claude 会话 | 需要 Claude Code 会话与 hook 机制联动，无法离线冒烟；hook 逻辑归 `evals/` 测试 |
| `--max-iterations 0`（显式无限循环）的运行时停机行为 | hook 侧 | 停机判定在 hook，不在本脚本；脚本侧仅确认该值原样写入状态文件 |
| `session-restore.sh` / `stop-feedback.sh` 等 hook 行为 | `hooks/*.sh` | 不属 scripts/ 范围，见 evals/ |
| 状态文件被 hook 消费后的语义（promise 拒绝计数、stall 检测） | hook 读取 frontmatter | 同上，需要会话联动 |
| 复杂 verify 命令的 YAML 转义（含双引号/反斜杠） | `setup-pua-loop.sh` `${VERIFY_COMMAND//\"/}` | 已知边界：verify 命令含双引号时 frontmatter 生成的是非法 YAML（引号只被剥离、未转义）。属脚本边界而非套件缺口；当前用法（`npm test`、`cargo test` 等简单命令）不受影响，如需支持复杂命令应先在脚本侧修转义 |

## 已覆盖（供对照）

`--help`、五类参数错误显性 exit 1、状态文件命名（cwd md5 前 8 位）、
frontmatter 关键字段、legacy 副本一致性、两份 history jsonl 初始化、
重复运行覆盖语义、session_id 环境变量注入 —— 见
`tests/test_setup_pua_loop.py`（HOME/cwd 双沙箱，真实运行脚本）。
