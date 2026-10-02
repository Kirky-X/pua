# failure-detector v3 分类器评测结果

> 生成方式：`python3 evals/score.py`（语料 `evals/corpus.jsonl`，逐条在隔离临时 HOME 中回放真实 hook）。
>
> **数字会随语料扩充变化：当前是 27 条小语料上的点估计，无置信区间。** 结论只反映本语料覆盖的场景，不外推到全体错误形态。

## 语料规模

- 总条数：27（SPINNING 5 / EXPLORING 4 / MIXED 4 / LOOP-SHUFFLE 3 / NONE 11）
- 中英文错误文本均覆盖（spin-zh-compile、explore-zh-frontend、mixed-zh-oscillate、shuffle-zh-toolchain、none-env-disk-full-zh 等）
- 每条 = max(3, len(cmds)) 次 hook 调用，隔离 HOME，session 固定为 `score-fixed`
- 预测推断：全程无 ESCALATE 块 → NONE；否则取最后一个 escalation 块的 `Pattern:` 行
- 标签由构造保证（同签名×3=SPINNING；全不同=EXPLORING；部分重复=MIXED；命令形状循环=LOOP-SHUFFLE；良性/环境=NONE），不是人工标注

## 实测结果（2026-10-03，failure-detector.sh v3，盲区 1/2 修复后）

```
Label distribution: EXPLORING=4, LOOP-SHUFFLE=3, MIXED=4, NONE=11, SPINNING=5

Per-class (P=precision, R=recall):
  class           TP  FP  FN       P       R      F1
  SPINNING         5   0   0   1.000   1.000   1.000
  EXPLORING        4   0   0   1.000   1.000   1.000
  MIXED            4   0   0   1.000   1.000   1.000
  LOOP-SHUFFLE     3   0   0   1.000   1.000   1.000
  NONE            11   0   0   1.000   1.000   1.000
  MACRO                                                1.000
```

混淆矩阵（行=真实，列=预测）：对角线全量，零误分类。

**Macro F1 = 1.000**。照实说：这个数字偏高的主要原因是标签由构造保证、语料小且场景是「干净」的（每条只有一种模式），不代表真实混乱会话里的表现。

## 历史误分类（2 条，已于 2026-10-03 修复）

首版评测（Macro F1 0.942）抓到两个 hook 真实缺陷，语料先行固化、hook 侧修复后转绿：

1. `spin-pytrace-modulenotfound`（true=SPINNING → 曾 pred=NONE）：`ENV_RE` 的 `ENOTFOUND` 备选无词边界且 `re.I`，`ModuleNotFoundError` 中 `module` 结尾的 `e` + `notfound` 误中 → Python traceback 整序列被豁免进环境通道、永不计压。修复：ENV_RE 全部错误码 token 加 `\b` 词边界。
2. `none-diff-shows-differences`（true=NONE → 曾 pred=SPINNING）：`diff` 不在 `PROBE_FIRST` 白名单，`diff` exit 1（报差异）被当真实失败计压，与 hook 头部注释相悖。修复：`diff`、`cmp` 加入白名单（`git diff` 此前已正确）。

对应 fixture 的 xfail 标记已摘除，`run-fixture.sh` 36/36 全绿。

## 仍存在的已知盲区

1. **LOOP-SHUFFLE 需要至少 9 次调用才会命中**（`len(ctoks) >= 9` 且前 3 组命令形状相等），短会话永远测不到该路径；本语料用 9 调用条目覆盖，真实短会话里等价于该模式不可用。
2. **pattern 推断只取最后一个 escalation 块**：长会话中前段 SPINNING、后段 EXPLORING 的混合序列会按后段归类；本语料刻意每条单一模式，未压测这种混合。
3. NONE 类的判据是「全程无 ESCALATE」，与「hook 认为是良性/环境」是同义反复——它测的是「不施压」这个结果，不测「豁免理由是否正确」。盲区 1（XNotFoundError 误豁免）正是「理由错误但结果恰好不施压」的反例，说明该判据会漏掉一整类豁免理由错误；扩充语料时应加入「豁免理由必须正确」的断言（检查 `[PUA-DIAGNOSIS]` 是否真的由环境信号触发）。

## 复现

```bash
python3 evals/score.py                    # 人读报表
python3 evals/score.py --json             # 机器可读（含逐条 true/pred）
bash evals/run-fixture.sh                 # 行为门禁（36 fixtures，全量须绿）
```

语料扩充时保持「标签由构造保证」：新增条目必须能从构造推出唯一标签，否则先补构造再进语料。
