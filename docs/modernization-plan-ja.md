# Journler Modernization Plan 日本語版

この文書は、[docs/modernization-plan.md](/Users/shg/Dropbox/dev/GitHub/Jnlr/docs/modernization-plan.md:1) の日本語版です。

## この文書の扱い

- 正本は英語版 `docs/modernization-plan.md` とする
- 計画や進捗の更新は、必ず先に英語版へ反映する
- この日本語版は、その内容に追従して更新する
- 英語版と日本語版に差異がある場合は、英語版を優先する

この文書は次を追跡します。

- 現在の全体方針
- 主要な実装フェーズ
- どこまで完了し、どこが進行中で、どこが未着手か
- プロジェクトの現在の到達点

この文書は、すべての細かな作業やチャット内容を記録することを目的としません。

## 目標

Journler 2.6 のジャーナルデータを変換なしで読み書きできる現行 macOS アプリとして `Jnlr` を再構築しつつ、Journler 2.6 の機能と look and feel を可能な限り再現する。

## 固定制約

- 既存ジャーナルデータは変換ロスなく読み込めなければならない
- 既存ジャーナルデータは同じオンディスク構造へ保存し戻せなければならない
- Journler 2.6 データ互換は必須条件
- オリジナルの Journler ソースは当面参照実装として保持する
- 現行アプリの UI は Swift + AppKit 方向へ進める
- 互換層は分離し、保守的に扱う

## 現在のアーキテクチャ

### データ互換層

Status: `Completed` for the current minimal milestone

- 新しい軽量互換層として実装されている
  - [compat/probe_model.h](/Users/shg/Dropbox/dev/GitHub/Jnlr/compat/probe_model.h:1)
  - [compat/probe_model.m](/Users/shg/Dropbox/dev/GitHub/Jnlr/compat/probe_model.m:1)
- Journler 2.6 の archive クラス名、archive キー、ファイルレイアウトを踏襲している
- 新規実装である
- オリジナルの Journler モデル/runtime コードを直接リンクしていない

### アプリ UI 層

Status: `In Progress`

- 現在のアプリバンドル
  - `build/Jnlr.app`
- 現在の UI 実装
  - [modern_app/main.swift](/Users/shg/Dropbox/dev/GitHub/Jnlr/modern_app/main.swift:1)
- ビルド経路
  - [Makefile](/Users/shg/Dropbox/dev/GitHub/Jnlr/Makefile:1)
  - [tools/build_minimal_app.sh](/Users/shg/Dropbox/dev/GitHub/Jnlr/tools/build_minimal_app.sh:1)
- 現在の方向性
  - Swift + AppKit
  - 旧 Journler の nib と controller は再利用せず、参照資料として使う

### オリジナルの Journler コード

Status: `Retained as reference`

- オリジナルのアプリソースと nib は、実行中の `Jnlr.app` では使っていない
- ただし次の参照元として重要
  - 振る舞いの参照
  - データ形式の参照
  - Journler 2.6 parity を進めるための UI 参照

## 検証用サンプルジャーナル

Status: `Completed`

リポジトリには実データのサンプルジャーナル `../JnlrData/Journler/` がある。

確認された構造:

- `Journler.plist`
- `JournlerStore.dict`
- `Journler Entries/Entry <id>/`
- `Collections/*.jcol`
- `Resources/*.jresource`
- `Blogs/*.jblog`
- `Index Entries`
- `Index References`

確認されたメタデータ:

- `Version = 253`
- `PDJournalProperShutDown = 1`
- `JournlerStore.dict` の内容
  - `Entries = 6015`
  - `Collections = 85`
  - `Resources = 4433`
  - `Blogs = 1`
- `Journler Entries/` には `6036` 個の entry package directory がある
- `Resources/` には `4433` 個の `.jresource` がある

このジャーナルを主要な互換性検証用コーパスとして扱う。

## 現在の到達点サマリー

Status: `In Progress`

現在までに、次の目に見える到達点に達している。

- 互換層は現行 macOS で supplied journal を読み込める
- 互換層は store-backed loading と directory loading の差分を調停できる
- `JournlerStore.dict` が無い場合でも directory-only loading へフォールバックできる
- 互換層は単一エントリの最小 save round-trip を実行できる
- 動作する `Jnlr.app` が存在する
- 現在の `Jnlr.app` UI は Objective-C 版から Swift + AppKit 版へ移植済みである

現在確認済みの `Jnlr.app` の挙動:

- 現行 macOS でビルドできる
- headless verification 用に `--smoke-test <journal-path>` をサポートする
- supplied journal を正常に開ける
- supplied journal から `6036` entries を読み込める
- 3 ペイン UI を表示する
- 階層型 collection sidebar を表示する
- 複数カラムの entry list を表示する
- entry の title と body を表示・編集できる
- entry metadata を表示する
- 未保存変更を失う前に save / discard / cancel を確認する
- 書き込み前にバックアップを作成する
- 単一エントリ保存時に `JournlerStore.dict` を再書き込みする
- ステータス欄に現在開いている journal path を表示する

## フェーズ別ステータス

### Phase 1: Data compatibility core

Status: `Completed`

目標:

- 現行 macOS 上で Journler 2.6 データを読み込めるようにする
- 現在テストできている範囲で、ファイル/archive 互換を保つ

完了済み:

- sample journal の監査
- keyed archive 互換の実装
- store-backed loading の実装
- directory fallback の実装
- supplied journal で `6036` entries に到達
- sample entry body loading の確認
- 最小 single-entry save round-trip の確認

### Phase 2: Minimal working app shell

Status: `Completed`

目標:

- 互換層の上に起動可能な macOS app を持つ

完了済み:

- 旧 Xcode project に依存しない app bundle 作成
- open journal flow
- reload flow
- 基本的な status display
- 編集可能な entry detail panel
- unsaved-change prompts
- 互換層と接続された save

### Phase 3: Swift + AppKit UI migration

Status: `Completed` for the current equivalent UI

目標:

- 新しいアプリ UI 実装を Objective-C から Swift + AppKit へ移す

完了済み:

- Swift entry point の追加
- Objective-C 互換層の Swift からのブリッジ
- 現在の 3 ペイン app shell の Swift 化
- sidebar、table、detail view、save flow、smoke-test path の移植

注記:

- このフェーズで意味する parity は「現在の新アプリ UI に対する等価移植」であり、まだ Journler 2.6 parity ではない

### Phase 4: Journler 2.6 UI and interaction parity

Status: `In Progress`

目標:

- Journler 2.6 の look and feel を段階的に再現する
- Journler 2.6 の主要ワークフローを段階的に再現する

完了済み:

- 3 ペインの情報設計を確立
- 階層型 collection sidebar を確立
- 複数カラム entry list を確立
- 基本 metadata display を確立
- date sorting を確立

主要な残作業:

- toolbar parity
- search / filter UI
- calendar pane
- resource pane
- より豊富な contextual menus と worktool behavior
- inspector / info panels
- 複数ウィンドウモード
- より厳密な look-and-feel 調整

### Phase 5: Xcode project and Interface Builder workflow

Status: `Planned`

目標:

- Xcode ベースのビルドを可能にする
- 必要であれば、新アプリ UI を xib/nib ベースで編集できるようにする

予定作業:

- `Jnlr` 用の新しい Xcode project を作る
- 互換層を新 project に接続したまま保つ
- どの view をコード生成のままにし、どの view を xib 化するかを決める
- オリジナルの Journler nib は runtime asset としてではなく、参照資料として使う

### Phase 6: Broader Journler 2.6 feature restoration

Status: `Planned`

目標:

- 現在の shell を超えて、Journler 2.6 の主要ワークフローをさらに戻す

想定スコープ:

- より豊富な search behavior
- smart folders
- resource browsing and actions
- より多くの metadata / inspector flow
- 追加の menu commands と keyboard behavior
- より広い save coverage

### Phase 7: Deferred legacy integrations

Status: `Deferred`

当面の対象外:

- auto update
- mail sending
- blog publishing
- Address Book integration
- AppleScript parity
- core restoration を超える高度検索 UI
- media capture and recording
- legacy WebKit dependent features

## 現在の UI 方針

現在の UI 方針は次の通り。

- 古い Journler UI 実装を直接復活させない
- 古い nib を runtime UI asset として直接再利用しない
- 新しい UI 層は Swift + AppKit で実装する
- オリジナル Journler 2.6 のコードと nib は design / behavior の参照として使う
- 時間をかけて Journler 2.6 の見た目と操作感に近づける

含意:

- 現在のアプリはオリジナル UI の直接移植ではない
- 新しいアプリとして実装しつつ、Journler 2.6 の振る舞いと外観へ収束させていく

## 現在の最上位優先事項

優先順:

1. 互換性の安全性を守る
2. 新しい Swift + AppKit アプリを安定させる
3. メインウィンドウを Journler 2.6 parity へ寄せる
4. UI 構造が整った時点で Xcode 管理 project へ移る
5. その後に広い legacy 機能群を戻す

## 次の主要ステップ

次の主要ステップ:

1. Journler 2.6 parity の第1マイルストーンを具体的な UI 単位で定義する
2. 新しい Xcode project を導入するタイミングを決める
3. 次の UI ステップを次のいずれにするか決める
   - toolbar と search/filter
   - calendar pane
   - resource pane
4. 方針やフェーズ状態が変わったら、この文書を更新する

## この文書の対象外

この文書は詳細な日次ログにはしない。

ここに記録しないもの:

- 細かなリファクタ
- すべての warning
- 一時的な実験
- チャット内で実行したすべてのコマンド

ここに記録するもの:

- 全体方針の変更
- 完了した主要マイルストーン
- フェーズ状態の変更
- 主要な未解決ギャップ
