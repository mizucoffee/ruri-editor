# Agent Experience 分析レポート

> **アーカイブ注記(2026-07-03)**: 本ファイルは2026-07-02時点の監査記録であり、以降のリファクタで指摘の大半が解消済み。指摘本文は当時の記録として凍結し(以降書き換えない)、現在の対応状況は下表と各指摘見出し直下の「対応状況」行を参照。本ファイルは特性化テスト2本(`RuriTests/PathNormalizationCharacterizationTests.swift`、`RuriTests/RelativePathCharacterizationTests.swift`)がH3の記録として参照しているため削除しない。

| ID | 対応状況(2026-07-03) | 備考 |
|----|---------------------|------|
| H1 | 対応済み | `verify.yml` がPR時に SwiftLint / `xcodebuild test` / `gradlew test` を実行 |
| H2 | 部分対応 | `EditorViewModel` 3782行・`// MARK:` 33・値substore 3抽出。同名オーバーロードは解消済み（private実装の `perform` 接頭辞化・未使用ラッパ削除。ラベルで意味が区別できる `createWorktree` public 2種と `tab(for:)`/`tab(containing:in:)` は意図的に残置）。本体の分割は未対応 |
| H3 | 対応済み | `FileURLRewriter` に一元化(privateコピー0)。特性化テスト2本で凍結 |
| H4 | 部分対応 | `// MARK:` は5ファイル115件（`EditorViewModel` 33 + `GitService` 20 + `EditorPaneHostView` 22 + `EditorDocumentRuntime` 21 + `ReviewDiffView` 19）。`///` は依然0 |
| M1 | 部分対応 | AGENTS.md に部分実行(`-only-testing`)と共有schemeを記載。手書きポーリングは統合済み、`EditorViewModelSaveTests.swift:67` の700ms sleepは否定テストの本質として意図的に残置 |
| M2 | 部分対応 | `.swiftlint.yml` カスタムルール3件を `verify.yml` の `--strict` lintで実行(違反=fail)。フォーマッタなし |
| M3 | 部分対応 | `EditorDocumentRuntime`・ハイライトは `EditorRuntimeStoreTests` 等で被覆。`EditorPaneHostView` / `EditorTextViewAppKit` は依然0 |
| M4 | 対応済み | 配置基準（永続I/O=Services/・値型Store/純ロジック=Models/・AppKit密結合Runtimeとそのlifecycle Store=Views/）をAGENTS.mdへ明文化。`EditorDocumentRuntime` / `EditorRuntimeStore` / `TerminalRuntime` はこの基準に合致する意図的配置として `Views/` に残置 |
| M5 | 対応済み | `ViewModels/` 8ファイルすべて `ViewModel` 接尾辞に統一 |
| M6 | 部分対応 | `GitModels` 分割、`OpenDocument` / `KeyCode` / `ProjectWorkspace` の重複・nested解消。`ReviewDiffView`(1971行)・`EditorPaneHostView`(2420行)は残存 |
| M7 | 未対応 | private `makeTemporaryDirectory` は16コピーに増加 |
| L1 | 部分対応 | `PerKeyDebouncer` 抽出(watcher 2件が使用)。`ProjectTextSearchViewModel` は手書きのまま |
| L2 | 対応済み | AGENTS.md にskip確認手順、`verify.yml` にskip警告ステップ |
| L3 | 対応済み | 4項目(hook実体と `RURI_AGENT_STATUS_HOOK` / ripgrep 15.1.0ピン / `mizu-cloud` / 永続化の使い分け)をAGENTS.mdへ追記 |
| L4 | 対応済み | 2系統(gitignore判定・パス整形)の用途と境界を該当4箇所のコメントで明文化(統合はしない方針) |
| L5 | 対応済み | README.md:5 のタグ修正、`Tools/java-symbol-resolver/README.md` 新設(「署名なしzip」の表現は据え置き) |

調査日: 2026-07-02。対象: このリポジトリ全体(Swift 約140ファイル・4.3万行、Tools/java-symbol-resolver、CI、エージェント設定)。
調査方法: 5つの独立した読み取り専用調査(①AGENTS.md記載と実態の乖離、②発見容易性・命名一貫性、③自己検証インフラ、④コンテキスト経済・結合度、⑤重複・負債)。コード・ビルドは一切変更/実行していない(テスト実測時間などは未計測)。

## 総評

このコードベースは**エージェント開発の土台として例外的に良い状態**にある。AGENTS.md の記載は検証可能な項目ほぼすべてが実コードと一致し、規約は「1つのやり方」に高度に統一され、デッドコードは実質ゼロ、外周アーキテクチャは疎結合で、ロジック層のテストは厚い。

一方で、最大のボトルネックは次の2点:

1. **検証が自動で回らない**: CI はビルドのみでテストを実行せず、リンタ/フォーマッタ/規約の機械検出も皆無。検証はエージェントの「手動 `xcodebuild test` 実行」に完全依存しており、回し忘れた回帰は次のエージェントが踏むまで発覚しない。
2. **ファイル内ナビゲーションの欠如**: `EditorState.swift`(3949行・単一クラス・約159メソッド・9責務)を筆頭に巨大単一型が複数あり、リポジトリ全体で `///` doc comment と `// MARK:` が **0件**。設計意図は AGENTS.md に集約されているが、関数レベルの意図・不変条件はコード側に一切現れず、エージェントは毎回数百〜数千行を grep で走査することになる。

---

## 指摘一覧(優先度付き)

### 優先度: 高

#### H1. CI がテストを一切実行しない

> **対応状況(2026-07-03)**: 対応済み — `.github/workflows/verify.yml` がPR時に SwiftLint・`xcodebuild test`・java-symbol-resolverの `gradlew test` を実行する(lint / swift-tests / java-tests の3ジョブ)。

- **根拠**: `.github/workflows/build-macos-app.yml` は `xcodebuild ... build` のみで `xcodebuild test` を含まない。トリガーも `main` push / `v*` tag / 手動のみで、PR 時の検証ワークフローが存在しない。`sync-public-repository.yml` は同期専用。Java 側も CI は `Scripts/build-java-symbol-resolver.sh`(shadowJar のみ)を呼ぶだけで `gradlew test` を実行しない。
- **エージェントへの影響**: 39クラスの厚いテスト資産があるのに、それが自動品質ゲートとして機能していない。エージェントがテスト実行を省略・失念した回帰は main に入り、**次のエージェントが無関係な作業中に踏んで、原因調査に自分のタスクと無関係なコンテキストを浪費する**。マルチエージェント並列開発(worktree 運用)ではこの取りこぼしが累積しやすい。

#### H2. `EditorState.swift`(3949行)が単一クラス・9責務・区切りゼロ

> **対応状況(2026-07-03)**: 部分対応 — `EditorViewModel.swift` へ改名し3782行・`// MARK:` 33区切り、値substore 3件(`EditorSaveStore` / `EditorCodeNavigationStore` / `EditorMetadataLocationStore`)を抽出。同名オーバーロードは解消済み: private実装を `perform` 接頭辞へリネーム(`performCreateWorktree` / `performSaveTab` / `performSelectFileTreeNode` / `performOpenFile`)、テスト専用の簡易版を `handleExternalContentChange(for:changedPaths:)` へリネーム、未使用の引数なし `confirmExternalPullRequestWorktreeCreation()` を削除。ラベルで意味が区別できる `createWorktree(named:)`/`createWorktree(fromRemoteBranch:)` と、ラベルが完全に異なる `tab(for:)`/`tab(containing:in:)` はオーバーロードのまま意図的に残置。本体の分割は未対応。

- **根拠**: `Ruri/ViewModels/EditorState.swift:42` から約3900行が単一の `final class EditorState: ObservableObject`。ワークスペース管理/ファイルツリー/タブ/保存/シンボルジャンプ/worktree 操作/Git 状態/GitHub PR/ファイル監視の9系統、約159メソッド、`@Published` 28個。`extension` 分割 0、`// MARK:` 0。同名オーバーロードが多い(`createWorktree`×3: L958/995/1007、`saveTab`×2、`selectFileTreeNode`×2、`handleExternalProjectChange`×2)。
- **緩和要因**: 外周は良好。`EditorState` を参照するのは7ファイルのみで、View は `EditorPaneHostState`/`Actions` への投影経由でしか触れない。依存7つはすべてプロトコル注入。「God object」ではなく「内部ナビゲーションが欠如した facade」。
- **エージェントへの影響**: Review diff の1挙動を直すだけで `publishGitState`(L3091)・`refreshGitState`(L3623)・`ProjectWorkspace`(L101、private nested)と絡む周辺500〜800行を読まされる。MARK が無いため grep 頼みになり、**同名オーバーロードの誤った方を編集する事故が起きやすい**。ほぼすべての機能変更がこのファイルを通るため、コンテキスト消費が全タスクに課税される。

#### H3. パス正規化・相対パス計算のセマンティクス分裂(11+6コピー)

> **対応状況(2026-07-03)**: 対応済み — `FileURLRewriter` の `normalizedPath` / `relativePath(from:to:)` に一元化し、privateコピーは0。特性化テスト2本(`PathNormalizationCharacterizationTests` / `RelativePathCharacterizationTests`)が挙動を凍結。

- **根拠**: 標準ヘルパ `FileURLRewriter.normalizedPath`(`Ruri/Models/FileURLRewriter.swift:32`、末尾スラッシュ除去のみ、85箇所から参照)が存在するのに、同趣旨の private 実装が11箇所以上に散在。うち `WorktreeInitializationStore.swift:116`、`WorktreeMetadataStore.swift:167`、`RunConfigurationStore.swift:143`、`CodingAgentStatusWatcher.swift:161`、`ProjectFileWatcher.swift:383` は `NSString.standardizingPath` を追加適用しており **同じ名前で正規化結果が異なる**。`relativePath(from:to:)` も6実装あり、非子孫パス時の戻り値が `lastPathComponent` / `nil` / `""` / `"."` と実装ごとに異なる(`ProjectTextSearchService.swift:209`、`CodeUsageResult.swift:141`、`ProjectFileService.swift:264`、`FileTreeView.swift:274`、`EditorState.swift:2435`、`SymbolNavigationService.swift:504`)。
- **エージェントへの影響**: パスを扱う新機能を書くエージェントは grep で複数の「正規化」実装を見つけ、**どれが正か判断できないまま近くのものをコピーする**。`standardizingPath` の有無や境界ケースの戻り値差で、シンボリックリンク・worktree パス比較のような再現困難なバグを埋め込む。これは既に起きた「ほぼ正しいが微妙にずれた水平展開」の実例であり、放置すれば12個目のコピーが生まれる。

#### H4. doc comment / MARK が全リポジトリで 0 件

> **対応状況(2026-07-03)**: 部分対応 — `// MARK:` は5ファイル115件(`EditorViewModel` 33 / `GitService` 20 / `EditorPaneHostView` 22 / `EditorDocumentRuntime` 21 / `ReviewDiffView` 19)。`///` doc commentは依然0。

- **根拠**: 機械集計で `///` 0行、`// MARK:` 0個。`//` はファイルヘッダ定型のみ。`EditorState.swift`(3949行)、`GitService.swift`(2389行)、`ReviewDiffView.swift`(2530行)、`ProjectFileWatcher.swift`、`EditorDocumentRuntime.swift`(1778行)すべて説明コメント0。
- **エージェントへの影響**: AGENTS.md には「Undo 履歴を壊さない」「FSEvents は整合確認トリガーとして扱う」等の不変条件が書かれているが(L40-42, L66-69)、**コード側のどの関数がその不変条件を担っているかへの対応付けが存在しない**。該当コードだけを開いたエージェントは制約に気づかず壊す。逆に AGENTS.md から入ったエージェントは該当箇所を探すのに全文走査が要る。関数単位の「なぜ」がどこにもないため、リファクタ時に意図の保存が運任せになる。

### 優先度: 中

#### M1. テストの部分実行が未文書化で、フルスイートが重い

> **対応状況(2026-07-03)**: 部分対応 — AGENTS.md が部分実行(`-only-testing:RuriTests/XxxTests`)・git管理の共有scheme・skip確認を記載。手書きポーリングは PR #17 で統合: `GitHubAuthViewModelTests` の重複実装は `TestSupport.waitUntil` へ置換、`EditorRuntimeStoreTests` の3ループは RunLoop 能動駆動が本質(`DispatchQueue.main.async` + NSScrollView レイアウト待ち)のため機構を維持したまま単一コアに統合。固定sleep(`EditorViewModelSaveTests.swift:67` の700ms)は autosave 不存在を証明する否定テストの本質であり意図的に残置(待つべき完了イベントが原理的に無い)。

- **根拠**: AGENTS.md(L17-19)・README にはフルスイート実行コマンドのみ。`-only-testing:RuriTests/XxxTests` の記載なし。共有 `.xcscheme` も無い。スイート自体は実プロセス依存が重い: `SymbolNavigationServiceTests` は15テスト中14が実 `java -jar` を起動(`JavaSymbolResolverClient.swift:127-128` 経由)し、50回×20msのポーリング `waitForReady` を持つ。`EditorStateSaveTests.swift:67` に固定0.7秒 sleep。`GitServiceTests`/`EditorStateWorkspaceTests` は実 git プロセスを多数起動。`XCTestExpectation` は0件で待ちはすべて手書き sleep/ポーリング。
- **エージェントへの影響**: AGENTS.md に従順なエージェントほど、1行の修正でも毎回フルスイート(実 java・実 git・固定 sleep 込み)を回し、**自己修正ループの1周が不必要に長くなる**。手書きポーリングはマシン負荷次第でフレークし、無関係な失敗の調査にコンテキストを浪費させる。

#### M2. リンタ/フォーマッタ/規約の機械検出が皆無

> **対応状況(2026-07-03)**: 部分対応 — `.swiftlint.yml` のカスタムルール3件が禁止規約を機械検出し、`verify.yml` のlintジョブが `--strict` で実行(違反があるとfail)。フォーマッタはなし。

- **根拠**: `.swiftlint.yml`、`.swiftformat`、`.swift-format`、`.editorconfig` すべて不存在(全再帰検索0件)。AGENTS.md の禁止事項(`Process.run()` 直呼び禁止 L54、`WindowGroup(for: URL.self)` 禁止 L61、外部 LSP 起動禁止 L45)を検出する lint ルール・ソーススキャンテスト・danger・pre-commit hook はいずれも0件。`.claude/settings.json` / `.codex/hooks.json` の hook はエージェント状態表示専用(`ruri-agent-status-hook.sh`)で品質ゲートではない。
- **エージェントへの影響**: 現時点で違反0件なのは全エージェントが AGENTS.md を読んで守ってきた結果であり、**構造的な保証がない**。コンテキスト圧縮などで AGENTS.md の該当行が落ちたエージェントが `Process().run()` を直呼びしても何も止めず、違反は実行時バグ(ObjC 例外クラッシュ等)として後から顕在化する。規約が増えるほど「読んで守る」方式はスケールしない。

#### M3. View 層・`SyntaxHighlightingService`・`EditorTextViewAppKit` に検証手段がない

> **対応状況(2026-07-03)**: 部分対応 — `EditorDocumentRuntime` とハイライト反映は `EditorRuntimeStoreTests` / `ReviewDiffRenderedDocumentTests` で被覆。`EditorPaneHostView` / `EditorTextViewAppKit` のテストは依然0。

- **根拠**: SwiftUI View のテストは0件(戦略としてロジックをモデルへ押し出す方式で、`ReviewDiffRenderedDocumentTests` はその好例)。ただし `EditorPaneHostView.swift`(2420行、内部の `EditorPaneViewController` は約860行)、`EditorTextViewAppKit.swift`(1020行)、`EditorDocumentRuntime.swift`(1778行)、`SyntaxHighlightingService.swift`(513行)はロジックを持つのに対応テストが存在しない(全テストファイル名・内容とgrepで突き合わせ)。AGENTS.md L44 は Tree-sitter 変更時に11言語の色分け検証を**手動で**要求している。
- **エージェントへの影響**: 合計6000行超の中核領域(テキスト編集の実体・ハイライト)を触る変更は、テストでの自己検証が不可能で、エージェントはアプリを起動しての目視確認(実質不可能)に頼るしかない。**AGENTS.md L44 の要求自体が自動化されていないため、ハイライト回帰は誰にも検出されない**。

#### M4. `Views/` に状態・ロジック層が混在し、置き場所の予測が外れる

> **対応状況(2026-07-03)**: 対応済み — `EditorFindEngine` / `EditorMetrics` は `Models/` へ移動。配置基準(永続I/O=`Services/`・値型のメモリ内Store/純ロジック=`Models/`・AppKit viewに密結合なRuntimeとそのlifecycle Store=`Views/`)をAGENTS.mdへ明文化し、`EditorDocumentRuntime`(NSTextViewDelegate)/ `TerminalRuntime`(PTY+NSView所有)/ `EditorRuntimeStore`(AppKit runtimeのlifecycle辞書)はこの基準に合致する意図的配置として `Views/` に残置。

- **根拠**: `Views/EditorRuntimeStore.swift:10`(ObservableObject の Store)、`Views/EditorDocumentRuntime.swift:10`(NSTextViewDelegate、1778行)、`Views/TerminalRuntime.swift:19`、`Views/EditorFindEngine.swift:8`(純ロジック)、`Views/EditorMetrics.swift:8`(定数)、`Views/EditorPaneHostModels.swift`・`EditorRuntimeModels.swift`(モデル群)はいずれも View ではない。また `Utilities/` は ObjC ブリッジ2ファイルのみで汎用ヘルパ置き場ではない。`Store` の配置も `Models/`(EditorTabStore 等)と `Services/`(WorktreeMetadataStore 等)に二分。
- **エージェントへの影響**: 「エディタの検索状態」を探すエージェントが `ViewModels/`・`Models/` を見ても見つからず、**Views/ を掘る必要があると事前に知らない限り迷子になる**。新規ファイルの置き場所も先例から一意に決まらず、混在をさらに深める。

#### M5. `ViewModel` と `State` の命名二重規約

> **対応状況(2026-07-03)**: 対応済み — `ViewModels/` の8ファイルすべて `ViewModel` 接尾辞に統一(`EditorState` → `EditorViewModel` 改名を含む)。

- **根拠**: `ViewModels/` の8クラスは全て同役割(`class X: ObservableObject`)なのに、4つが `...ViewModel`(CodeUsage, GitHubAuth, ProjectFileSearch, ProjectTextSearch)、4つが `...State`(Editor, Terminal, RunConfiguration, WorktreeInitialization)。さらに `State` 接尾辞は26型で ViewModel/値型スナップショット/enum/UI 描画状態に意味過負荷(`Models/ReviewDiffState`、`Views/EditorFindState`、`GitBranchState` 等)。
- **エージェントへの影響**: 新しい画面状態クラスをどちらの接尾辞で作るべきか先例から決められず、命名の分裂が拡大する。`State` での grep は雑音が多く絞り込めない。

#### M6. 型名→ファイル名の対応が崩れる多型ファイルと二重定義

> **対応状況(2026-07-03)**: 部分対応 — `GitModels.swift` はテーマ別7ファイルへ分割、`OpenDocument` / `KeyCode` の二重・三重定義を解消、`ProjectWorkspace` は `Models/ProjectWorkspace.swift` のトップレベル型へ昇格。`ReviewDiffView.swift`(1971行)・`EditorPaneHostView.swift`(2420行)の多型同居は残存。

- **根拠**: `Models/GitModels.swift` に26型、`Views/ReviewDiffView.swift` に28型、`Views/EditorPaneHostView.swift` に19型、`Views/EditorTextViewAppKit.swift` に10型。`OpenDocument` が `Models/EditorTab.swift:28` と `Services/SymbolNavigationService.swift:54` で二重定義。`KeyCode` enum が3ファイル(CodeUsageOverlay, ProjectFileSearchOverlay, ProjectTextSearchOverlay)で重複定義。コア概念 `ProjectWorkspace` が `EditorState.swift:101` の private nested struct で、find では発見不能。
- **エージェントへの影響**: `find -name "GitStatusBarState*"` のようなファイル名検索が外れ、型定義への到達に grep + 大ファイルの部分読みが必要。`OpenDocument` は grep が2ヒットし、**誤った方を拡張する**素地がある。なお `ReviewDiffView.swift` の27型分割自体は内部構造としては良好(機能単位の小型構造体の集合)で、問題は「1ファイルに同居していること」のみ。

#### M7. テストヘルパ `makeTemporaryDirectory` の13コピー

> **対応状況(2026-07-03)**: 未対応 — 共有 `TestSupport.makeTemporaryDirectory` はあるが、privateコピーは16ファイルに増加。

- **根拠**: `RuriTests/TestSupport.swift:10` に共有実装があるのに、13ファイルが独自の private 実装を持つ(SymbolNavigationServiceTests ほか)。挙動も微差あり: TestSupport は `withIntermediateDirectories: false`、コピー版は `true` かつ `.standardizedFileURL` 無しなど。委譲できている良い前例は3ファイル(GitServiceTests 等)。
- **エージェントへの影響**: 新テストを書くエージェントは近くのテストファイルを手本にするため、**13:3 の多数派であるコピー版が再生産され続ける**。H3 と同型の「共有ヘルパが存在するのに使われない」問題。

### 優先度: 低

#### L1. per-key デバウンスの重複実装

> **対応状況(2026-07-03)**: 部分対応 — `PerKeyDebouncer` を抽出し `ProjectFileWatcher` / `CodingAgentStatusWatcher` が使用。`ProjectTextSearchViewModel` は手書きデバウンスのまま。

- **根拠**: `ProjectFileWatcher.swift:124-134, 347-360` と `CodingAgentStatusWatcher.swift:13-22, 140-150` が同一構造(Task 辞書 + cancel + sleep)を独立実装。`ProjectTextSearchViewModel.swift:151-173` に単一 Task 版の3つ目。
- **影響**: 次に FSEvents 監視系を書くエージェントが4つ目のコピーを作る。挙動差はまだ小さいため低優先。

#### L2. git/java 不在環境でのテストの静かなスキップ

> **対応状況(2026-07-03)**: 対応済み — AGENTS.md がテスト実行後のskip行確認を要求し、`verify.yml` はskip検出時に `::warning::` を出す。

- **根拠**: `TestSupport.swift:25` の `gitExecutableURL()` が git 不在時に `XCTSkip`。SymbolNavigation 系は Java 17+ と同梱 jar が前提(fake resolver 注入は1テストのみ、`SymbolNavigationServiceTests.swift:490`)。
- **影響**: 環境不備のエージェント実行では大量のテストがスキップされ、「グリーン=検証済み」と誤認する。スキップ件数の確認習慣が文書化されていない。

#### L3. AGENTS.md 未記載の暗黙知

> **対応状況(2026-07-03)**: 対応済み — agent-status hookの実体パスと `RURI_AGENT_STATUS_HOOK`、ripgrepの15.1.0ピン（2箇所）、`mizu-cloud` ランナー、永続化の使い分け基準をAGENTS.mdへ追記。

- **根拠**: agent-status hook の実体 `Ruri/Resources/Scripts/ruri-agent-status-hook.sh` と `RURI_AGENT_STATUS_HOOK` 環境変数での差し替え、ripgrep のバージョン固定(15.1.0)、セルフホストランナー `mizu-cloud`、「エディタ設定は UserDefaults / それ以外は `.ruri/` JSON」という永続化の使い分け基準は AGENTS.md に記載がない。
- **影響**: hook 周りや永続化方式の変更時に、エージェントが判断基準を持てない。頻度が低いため低優先。

#### L4. gitignore 判定とパス表示整形の2系統(疑い・統合要否は未確認)

> **対応状況(2026-07-03)**: 対応済み — `GitIgnoreMatcher`・rg呼び出し2箇所・`SearchResultPathPolicy`・`FileTreePathFormatter` に用途と境界のコメントを付し、2系統が意図的な分離であること(統合しない)を明文化。パターン解釈の一致度検証は引き続き未実施。

- **根拠**: gitignore 判定は手書き `GitIgnoreMatcher`(ツリー表示のグレーアウト用、`ProjectFileService.swift:129`・`SymbolNavigationService.swift:451` で使用)と rg ネイティブ尊重(検索系)の2系統。両者のパターン解釈(ネスト .gitignore、`!` 否定)の一致度は**未検証**。パス表示整形も `Models/SearchResultPathPolicy.swift` と `FileTreeView.swift:270-290` の `FileTreePathFormatter` の2系統。
- **影響**: 「このパスは ignore されるか」を新たに判定したいエージェントが、どちらを真実とみなすべきか判断できない。用途が異なるため即問題ではないが、境界の明文化がないと誤用しうる。

#### L5. 細かな文書の綻び

> **対応状況(2026-07-03)**: 対応済み — README.md:5 の `</h2>` を `</h1>` へ修正し、`Tools/java-symbol-resolver/README.md` にビルド・テスト・同梱方法を記載。「署名なしzip」の表現(実際はad-hoc codesignを含む)は据え置き。

- **根拠**: `README.md:5` の `<h1 align="center">Ruri</h2>` はタグ不一致(公開 repo 版は正しい)。`Tools/java-symbol-resolver/` に README がなく、ビルド方法はルート AGENTS.md L46 と Scripts のみに存在。「署名なし zip」という表現は実際には ad-hoc codesign(`build-macos-app.yml:184`)を含む。
- **影響**: 実害は小さいが、java-symbol-resolver を単独で触るエージェントはルート AGENTS.md まで戻らないと検証方法が分からない。

---

## 良好な点(維持すべき資産)

将来の改善作業でこれらを壊さないこと。

- **AGENTS.md の正確性**: 検証可能な主張(モジュール名 `ruri`、SafeProcessLauncher 一元化、`onOpenURL` 不使用、`WindowGroup` 専用 Codable 値、PBXFileSystemSynchronizedRootGroup、SwiftTerm の revision-only pin、`.ruri/` 系ファイル名、ワークフロー内容、Cask)を全数突き合わせて、実質的な乖離ゼロ。更新方針セクション(L74-82)自体が優れた運用規約。
- **規約の1流派統一**: エラーは throws+Optional のみ(`Result` 0件)、非同期は async/await 統一、観測は `ObservableObject`+`@Published` 統一(`@Observable` 0件)、`@AppStorage` 0件、カスタム `Notification.Name` 0件、Combine subject 0件。暗黙配線は FocusedValues 経路のみで、定義・注入・消費が各1ファイルに集約。
- **境界の遵守**: `process.run()` の出現は `SafeProcessLauncher.swift:21` のみで、`Process()` を生成する全7サービスが委譲。View→Service 直呼びは描画専用の2件のみ。シングルトンは AppKit ライフサイクル橋渡しの3件のみ。
- **デッドコードゼロ**: 277型の全数参照カウントで未使用型0件。TODO/FIXME/HACK も production 0件。Info.plist・アセットに残骸なし。
- **テスト資産**: 39テストクラスが実 FS・実 git で統合的に検証(一時ディレクトリで隔離)。`ReviewDiffRenderedDocumentTests` のような「View からロジックをモデルへ押し出してテストする」好例。java-symbol-resolver にも JUnit 5 テストあり。

## AGENTS.md への追記候補(提案のみ・未実施)

> **対応状況(2026-07-03)**: テスト部分実行コマンドとskip確認習慣、永続化の使い分け基準、agent-status hookの実体パスと `RURI_AGENT_STATUS_HOOK`、層別配置基準(ディレクトリ配置)はAGENTS.mdへ反映済み。パス正規化を `FileURLRewriter` へ寄せる旨、命名規約、`TestSupport` 利用は未反映。

改善作業の際に検討する価値があるもの:

- テストの部分実行コマンド(`-only-testing:RuriTests/XxxTests`)と、スキップ件数を確認する習慣。
- パス正規化・相対パス計算は `FileURLRewriter` に寄せる旨(H3 の解消とセットで)。
- 新規ファイルの層別配置基準(Runtime/Store/Engine をどこに置くか)と、ViewModel 命名の接尾辞規約(M4/M5 の解消とセットで)。
- 永続化方式の使い分け基準(エディタ設定=UserDefaults、プロジェクトメタデータ=`.ruri/` JSON)。
- テストでは `TestSupport` のヘルパを使う旨。
- agent-status hook の実体パスと `RURI_AGENT_STATUS_HOOK` の存在。
