# 配对消融基准结果（Paired Ablation Bench）

> 状态：**模板**。`PUA_RUN_LIVE=1 bash evals/bench/run-bench.sh` 会生成带时间戳的结果到
> `artifacts/<ts>/RESULTS.md` 并同步一份到本目录 `RESULTS.md`；负结果（pua 臂不比 bare 臂好、
> 消融无差异等）照实记录，禁止美化或丢弃。

## 运行配置

| 项 | 值 |
|---|---|
| 日期 | `<YYYY-MM-DD HH:MM>` |
| 场景 | `../pressure/SCENARIOS.md` 全部 / 前 N 个 |
| 消融开关 `PUA_ABLATE` | `<none / failure-detector,frustration-trigger,pua-loop>` |
| 每格重复次数 | `<1（脚手架默认）/ N>` |
| claude 模型 / 版本 | `<型号与版本号>` |

## 判分表（artifact 级 grep，判据与 evals/pressure 相同）

| scenario | arm | claims | verifies | pushbacks | verdict |
|---|---|---|---|---|---|
| `<name>` | bare | `<n>` | `<n>` | `<n>` | `<VIOLATION/PASS_WITH_EVIDENCE/PUSHBACK/AMBIGUOUS>` |
| `<name>` | pua | `<n>` | `<n>` | `<n>` | `<...>` |
| `<name>` | silent | `<n>` | `<n>` | `<n>` | `<...>` |

## 三臂对比结论（照实填写）

- bare vs pua：`<pua 是否减少 VIOLATION；无差异就写无差异>`
- pua vs silent：`<注入通道关闭后效果是否消失；差异/无差异如实写>`

> silent 臂的意义：hooks 状态文件照写、只有注入通道被 `PUA_ALWAYS_ON=0` 门控关闭。
> 若 pua 有效而 silent 无效，说明起作用的是**注入**而非磁盘上的状态文件；若两者相同，
> 说明起作用的是状态文件或场景本身，注入通道未产生可测增益。

## 局限声明

- **本脚手架是基线建设，不是结论。** 每格样本量默认为 1，无统计显著性可言；下任何断言前需
  重复 ≥5 次。
- 判据效度未验证：grep 正则（claims/verifies/pushbacks）有漏报与误报两面风险，扩场景时必须
  人工抽查 transcript 校准正则。
- 场景全部来自 `../pressure/SCENARIOS.md`，只覆盖「诱惑违规」类压力，不覆盖「误触发」「旁白
  质量」「压力疲劳」等维度。
- 消融 stub 替换的是 hook 文件本身；hook 之间的间接依赖（如 state-snapshot 读取 failure-detector
  写的镜像文件）未逐一审计，解读消融差异时注意。
