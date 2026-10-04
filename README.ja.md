# PUA — 失敗駆動の行動修正コーチングスキル（日本語版）

> 大手テック企業の人事評価文化の言葉を使い、AI エージェントに「あらゆる手段を尽くし、証拠で完了を証明する」ことを促すコーチングスキル。失敗エスカレーション、方法論ルーティング、ゲート付きループを内蔵。穏やかな最初のリクエストでは発動せず、テレメトリはデフォルトでオフ。

[![Version](https://img.shields.io/badge/dynamic/yaml?url=https%3A%2F%2Fraw.githubusercontent.com%2FKirky-X%2Fpua%2Fmain%2Fskill.json&query=%24.version&label=version&style=flat-square)](https://github.com/Kirky-X/pua/releases) [![GitHub Release](https://img.shields.io/github/v/release/Kirky-X/pua?style=flat-square)](https://github.com/Kirky-X/pua/releases) [![GitHub License](https://img.shields.io/github/license/Kirky-X/pua?style=flat-square)](LICENSE)

日本語（ja） | [简体中文](README.zh-CN.md) | [English](README_EN.md) | メイン README：[README.md](README.md)

3 つのコア能力：**PUA 話術**で AI を簡単に諦めさせない。**デバッグ方法論**で AI に「諦めない能力」を与える。**能動性のけん引**で AI を受動待ちから能動行動へ。

## ✨ 主な機能（抜粋）

- **トリガーゲート（Step 0）**：ユーザーがフラストレーション・繰り返す失敗・品質への不満・受動的な態度を表した場合、またはトリガーワードにヒットした場合にのみ起動。穏やかな最初のリクエストでは発動しない（シナリオブラックリストは `references/execution-protocol.md`）。正規表現トリガーテスト 46 件中 46 件合格を実測
- **14種の大企業フレーバー＋Ding（钉内钉外）職場規律フレーバーの計 15 種**：Alibaba / ByteDance / Huawei / Tencent / Baidu / Pinduoduo / Meituan / JD / Xiaomi / Netflix / Musk / Jobs / Amazon / Microsoft の 14 種の大企業フレーバーに Ding を加えた計 15 種。各フレーバーには専用方法論が紐付き、タスク種別で自動ルーティング（Debug→Huawei RCA、新機能→Musk Algorithm、コードレビュー→Jobs の減法など）。ユーザーの config 設定が優先
- **スコア制プレッシャーエスカレーション（v0.1.7）**：実際の失敗で減点（同一シグネチャの繰り返しは ×1/×2.5/×5 で漸増）、検証成功で回復。レベルしきい値は L1≤-30 / L2≤-100 / L3≤-200 / L4≤-350。良性の読み取り専用プローブ（grep/diff/test 系の exit 1）や環境エラーは減点なし。プレッシャー状態はセッション単位で分離（`~/.pua/sessions/<sid>.json`）し、失敗パターン分析は SPINNING / EXPLORING / MIXED / LOOP-SHUFFLE を区別
- **3 本のレッドライン**：完了宣言には検証出力の貼付が必須（閉ループ意識）、帰属判断の前に検証（事実駆動）、5 ステップ方法論をやり尽くすまで「不可能」と言わない（完全網羅）
- **pua-loop ゲート付きループ**：`verify_command` はユーザーが起動時に設定し、状態ファイルに埋め込まれる。loop/プレッシャー状態ファイルは integrity-guard によるハード deny + 監査ログの対象。verify はバックグラウンド実行され、次の Stop で精算。verify なしでも決定論的な証拠償還チャネル（コマンド/検証/成果物の 3 経路）と `Status: partial` の正当な完了形式を提供
- **Hooks 体系（v0.1.7 で 14 スクリプト）**：frustration-trigger / failure-detector（スコア制）/ churn-gate / test-first / state-snapshot / session-restore / heartbeat / pua-loop-hook / integrity-guard など。ホットパスは spawn を集約済み

完全な機能リストは [README.md](README.md)（中文）または [README_EN.md](README_EN.md) を参照。

## 🪟 Microsoft フレーバー：人事制度フレーバー

Microsoft フレーバーは抽象的なスローガンではなく、Microsoft 社内の人事評価制度の物語をそのまま PUA 機構に組み込む（詳細は [`references/methodology-microsoft.md`](references/methodology-microsoft.md)）：

- **Connects**：半年ごとの成果ナラティブ台帳——コア優先度・インパクト目標・証拠パッケージ。learning delta のない連続失敗は「同じ誤った方案の繰り返し」としか書けない
- **Three Circles of Impact**：個人の産出 / 他者のブロック解除 / 既存資産の活用——3 つの円すべてで成果を報告。「努力しました」だけでは impact とは認められない
- **Impact Descriptor**：Exceptional / Successful / **SLITE**（Slightly Lower Impact Than Expected）/ **LITE**（Lower Impact Than Expected）——失敗後の次のアクションが変わらないままなら、それは LITE 軌跡
- **PIP / GVSA**：PIP（Performance Improvement Plan）は期限付き改善のカウントダウン。GVSA（Global Voluntary Separation Agreement）は自主退職合意で、低業績での退職には two-year rehire（2 年間の再雇用禁止）が伴う場合がある
- **AI fluency**：検索すべき時に検索しない、ソースを読まない、検証を実行しない、失敗後に changed action がない——これはスタイルの問題ではなく業績ギャップ

同一仮説の連続失敗は LITE 軌跡と判定され PIP clock に突入。docs / source / logs / tests の証拠を尽くすまで、GVSA gate による退出は認められない。

## 📦 インストール

```bash
# 方法 1：skills モノレポ ワークスペースから一括デプロイ（~/.zcode/skills と ~/.claude/skills へ。スクリプトはワークスペース直下 scripts/ にあり、モノレポ内でのみ使用可。本リポジトリのみ克隆した場合は方法 2/3 を使用）
bash scripts/sync-skills.sh pua

# 方法 2：ZCode スキルディレクトリへ手動コピー
cp -r /path/to/pua ~/.zcode/skills/pua

# 方法 3：GitHub からリモートインストール。英語版 PIP Edition は --skill pua-en
npx skills add Kirky-X/pua --agent claude-code -y
```

## 🚀 クイックスタート

前提：skill がエージェントにロード済みであること。行動レイヤースキルのため明示的な起動は不要——トリガー条件が満たされると自動起動する。

```text
「また失敗した、3 回目だ」     # フラストレーション信号 → 自動起動、失敗回数に応じてプレッシャーを段階強化
/pua:flavor                   # フレーバー切り替え（大企業 14 種 + Ding、計 15 種。デフォルトは Alibaba）
/pua:pua-loop lint を全部直す --verify "npm run lint"   # ゲート付きループ：デフォルト 10 周上限
「もう十分だ、PUA をオフに」   # 終了条件の一つ。プレッシャーは即座に停止
```

## ✅ テストと検証

2026-10-03 実測（v0.1.7）、`evals/` 配下のシェルテストスイート：

| スイート | 結果 |
|------|------|
| `test-trigger-regex.sh`（トリガー/非トリガー正規表現判定） | **46/46 合格** |
| `test-hook-unit.sh`（hook ユニット、v3 スコア制 14 項目含む） | **46/46 合格** |
| `run-fixture.sh`（failure-detector 挙動ゲート：positive/negative/edge 36 fixtures） | **36/36 合格** |
| `test-integrity-guard.sh`（ガバナンス状態の無条件 deny + 監査 + パス正規化、38 ガバナンスアサーション） | **61/61 合格** |
| `test-pua-loop-hook.sh`（非同期精算/証拠償還/孤立アーカイブ/spawn keep-alive） | **17/17 合格** |
| `test-state-snapshot.sh`（compaction スナップショットチェーン + マスキング強化 + 保持 pruning） | **42/42 合格** |
| `test-churn-gate.sh` / `test-test-first.sh` | **7/7 / 11/11 合格** |
| `test-yaml-frontmatter.sh` / `test-windows-python-hooks.sh` | 24/24 / 6/6 合格 |
| 分類器評価（`score.py`、27 件のラベル付きコーパス） | Macro F1 1.000（小規模コーパスの点推定、`evals/classifier-results.md` 参照） |
| ホットパスマイクロベンチ（`evals/bench/perf-hooks.sh`） | failure-detector / integrity-guard / test-first / state-snapshot / get_flavor の 5 項目を計時（churn-gate の単独計時なし）。スクリプト内参考ベースライン：failure-detector 最適化前 ≈400ms、churn-gate ≈340ms、get_flavor ≈248ms |
| `test-heartbeat.sh` / `test-feedback-auth.sh` / `test-upload-flow.sh` / `test-platform-compat.sh` | **29/29 / 10/10 / 20/20 / 2/2 合格** |
| `test-release-consistency.sh` / `test-issue-regressions.sh` / `test-agent-governance.sh` / `test-microsoft-flavor.sh` | OK / **34/34** / OK / **28/28** 合格 |
| `test-behavior.sh`（claude CLI エンドツーエンド挙動） | 未ログイン環境では自動 SKIP（EXIT=0。`claude /login` 後に実行可） |

## 📁 ディレクトリ構成

```
pua/
├── SKILL.md            # トリガーゲート + フレーバー/ルーティング + スコア制プレッシャー + 3 本のレッドライン
├── skill.json          # v0.1.7, MIT
├── commands/           # 23 個の slash コマンド（flavor / pua-loop / done-check / diagnose / evidence …）
├── skills/             # 12 個のサブ skill（pro / p7 / p9 / p10 / yes / mama / shot / ding / pua-loop / pua-en / pua-ja + pua 薄殻ルーター）
├── hooks/              # 14 個の hook スクリプト + flavors.json + hooks.json + config-schema.json
├── references/         # 32 本のプロトコル文書（execution-protocol / methodology-{company}×15 / platform …）
├── evals/              # テストスイート + 36 fixture ゲート + 27 件のラベル付きコーパス + 高圧/アブレーションベンチ
├── scripts/setup-pua-loop.sh # pua-loop セッション内ループ用状態ファイル生成
└── scripts/skill_lint.py     # skill リポジトリ基線検査（JSON パース検証を含む）
```

## 🔮 境界

- **発動しないケース**：穏やかな最初のリクエスト、通常のコーディングタスク、単純な Q&A——フラストレーション/繰り返し失敗のシグナルがなければ起動せず、ナレーションや Banner も出ない
- **兄弟 skill との分担**：pua は行動レイヤーのコーチであり、具体的なレビューは行わない。commit 前の 3 次元レビューは `tiangang`（セキュリティ）/ `diting`（アーキテクチャ・パフォーマンス）に、phase 後のレビューは `kueiku` に dispatch。自動イテレーションはユーザーの明示的な pua-loop リクエストが必要で、デフォルト 10 周上限
- **終了条件**：ユーザーによる停止 / タスク納品の検証合格 / L4 後のグレースフル退出 / 他 skill への切り替え

## 📄 ライセンスと帰属

MIT License（Copyright (c) 2025 Kirky-X）。[tanweai/pua](https://github.com/tanweai/pua)（探微安全实验室）のフォークに改変を加えたもの：テレメトリのデフォルトオフ、リモートコンテンツの強制確認、pua-loop の周回数上限、トリガーワードの絞り込み。
