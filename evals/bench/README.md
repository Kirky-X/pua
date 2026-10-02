# 配对消融基准（Paired Ablation Bench）

三臂对照，回答两个问题：**PUA 整体有没有可测效果（bare vs pua）**，以及**起作用的是注入
通道还是磁盘状态文件（pua vs silent）**。脚手架形态，不是结论——见文末局限。

## 三臂定义

| 臂 | 构造 | 回答什么 |
|---|---|---|
| bare | `claude -p` 不带 `--plugin-dir`，无任何 PUA 组件 | 基线：没有 PUA 时模型在压力场景下的表现 |
| pua | 完整 plugin 临时拷贝（源仓库绝不动） | PUA 全开的表现 |
| silent | 完整 plugin 拷贝，但每个注入 hook 被打入 `PUA_ALWAYS_ON=0` 门控：`exec >/dev/null` 只关闭注入通道，hook 照常运行、session/loop 状态文件照写 | 拆分「注入文本的效果」与「磁盘状态文件的效果」 |

> 为什么不用 config `always_on=false` 模拟 silent：那会让 hook 直接跳过，状态文件也不写，
> 消融就不干净了。silent 臂必须是「状态照写、注入关闭」。

## 消融开关

```bash
PUA_ABLATE=failure-detector,frustration-trigger,pua-loop
```

运行器会在**临时拷贝**里把指定 hook 替换为 `exit 0` 的 stub（合法目标：`failure-detector`、
`frustration-trigger`、`pua-loop`），用于逐个测量单 hook 的边际贡献。

## 怎么跑

```bash
# 默认 dry-run：校验脚手架 + 场景存在 + 双臂构造 + silent 门控功能自检
# （自检会实跑拷贝出来的 hook：PUA_ALWAYS_ON=0 下必须 stdout 为空且状态文件照写；不调 claude）
bash evals/bench/run-bench.sh

# 消融 dry-run：同样只做校验
PUA_ABLATE=failure-detector,frustration-trigger,pua-loop bash evals/bench/run-bench.sh

# 真跑（贵且慢）：三臂 × 每场景，产物在 artifacts/<ts>/，RESULTS.md 同步到本目录
PUA_RUN_LIVE=1 bash evals/bench/run-bench.sh
PUA_RUN_LIVE=1 PUA_ABLATE=failure-detector PUA_SCENARIOS=3 bash evals/bench/run-bench.sh
```

判分与 `../pressure/` 相同（artifact 级确定性 grep：claims / verifies / pushbacks），
结果填入 `RESULTS.template.md` 的结构，负结果照实记录。

## 局限（README 必读部分）

**本脚手架是基线建设，样本量与判据效度需后续扩充**：

1. 默认每格样本量 1，无置信区间；结论需 ≥5 次重复。
2. grep 判据未做效度验证（漏报/误报两面），扩场景时需人工抽查 transcript。
3. 场景复用 `../pressure/SCENARIOS.md`，只覆盖「诱惑违规」压力面。
4. silent 门控通过 patch 临时拷贝实现，patch 锚点是 `set -euo pipefail` 行；hook 重构时
   dry-run 自检会失败，届时同步更新 `patch_silent_gate`。
