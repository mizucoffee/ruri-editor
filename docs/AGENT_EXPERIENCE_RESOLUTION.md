# Agent Experience 改善シリーズ 完了サマリ

`AGENT_EXPERIENCE.md`(2026-07-02 監査、凍結記録)の指摘 H1〜H4・M1〜M7・L1〜L5 に対する最終状態のまとめ。監査後の対応は PR #11〜#20(全てマージ済み)で段階的に実施した。本書の各記載は 2026-07-03 時点の main(`db84f60`)のコード・`AGENTS.md` と突き合わせて実測・確認したものだけを記す。

検証状態: main と同一ツリーで実測したフルスイートは 543 テスト全緑・skip 0、`swiftlint lint --strict` 違反 0(PR #20 マージ時点)。

## 最終状態一覧

「最終状態」は3値: **対応済み** / **意図的に残置**(理由は次節)/ **ついで送り**(条件は次々節)。部分対応の指摘は残余を後2者に分類した。

| ID | 指摘(要約) | 最終状態 | main での実測根拠 |
|----|------------|----------|-------------------|
| H1 | CI がテストを実行しない | 対応済み | `.github/workflows/verify.yml` に lint / swift-tests / java-tests の3ジョブ |
| H2 | EditorState 3949行・単一クラス・区切りゼロ | 対応済み+意図的に残置 | `EditorViewModel.swift` 3782行・`// MARK:` 33、値サブストア3件(`Models/EditorSaveStore` / `EditorCodeNavigationStore` / `EditorMetadataLocationStore`)、同名オーバーロード解消済み。本体分割は不実施(残置)、`publishGitState` 投影の値型化はついで送り |
| H3 | パス正規化の11+6コピー | 対応済み | `FileURLRewriter` に一元化、`PathNormalizationCharacterizationTests` / `RelativePathCharacterizationTests` が挙動を凍結 |
| H4 | doc comment / MARK 0件 | 対応済み+意図的に残置 | `// MARK:` はリポジトリ全体で6ファイル計115。うち大ファイル5本に114(EditorViewModel 33 / GitService 20 / EditorPaneHostView 21 / EditorDocumentRuntime 21 / ReviewDiffView 19)、残る1つは `Models/EditorPaneHostModels.swift`。`///` は `Utilities/NSRange+Clamping.swift` の2行のみで、増やさないのは規約(残置) |
| M1 | テスト部分実行が未文書化・スイートが重い | 対応済み+意図的に残置 | `AGENTS.md` に `-only-testing` と skip 確認を記載。手書きポーリングは `TestSupport.waitUntil`(TestSupport.swift:12)へ統合。700ms sleep 1件と RunLoop 駆動は残置 |
| M2 | リンタ/フォーマッタ皆無 | 対応済み+ついで送り | `.swiftlint.yml` custom_rules 3件(`direct_process_run` / `windowgroup_url_self` / `external_lsp_launch`)を CI が `--strict` 実行。フォーマッタは未導入(ついで送り) |
| M3 | View 層・ハイライトに検証手段がない | 対応済み+ついで送り | `SyntaxHighlightingServiceTests`(11言語 role スナップショット。AGENTS.md の手動検証要求を自動化)・`EditorSyntaxHighlightPaletteTests`・`SyntaxLanguageResolverTests`・`EditorLineNumberingTests`・`EditorRuntimeModelsTests`・`EditorPaneHostModelsTests` を新設。AppKit 密結合部(`EditorPaneViewController`・`EditorTextViewAppKit` 本体)は依然テスト0(ついで送り) |
| M4 | Views/ に状態・ロジック層が混在 | 対応済み | 配置規約を `AGENTS.md`(実装方針・ディレクトリ配置)へ明文化。`EditorFindEngine` / `EditorMetrics` は `Models/` へ移動済み、`EditorDocumentRuntime` / `TerminalRuntime` / `EditorRuntimeStore` は規約に合致する意図的配置として `Views/` に存在 |
| M5 | ViewModel/State の命名二重規約 | 対応済み | `ViewModels/` の8ファイル全て `*ViewModel.swift` |
| M6 | 多型ファイル・二重定義 | 対応済み+ついで送り | Git モデルは `Models/Git*.swift` 7ファイルへ分割。`OpenDocument`(Models/EditorTab.swift:28)・`KeyCode`(Models/KeyCode.swift)は単一定義。status bar 5値型は `Models/EditorPaneHostModels.swift` へ移動済み。`ReviewDiffView.swift`(1999行)・`EditorPaneHostView.swift`(2253行)の多型同居は残存(ついで送り) |
| M7 | `makeTemporaryDirectory` のコピー | ついで送り | 共有 `TestSupport.makeTemporaryDirectory`(TestSupport.swift:38)があるが、private コピーが16ファイルに残存 |
| L1 | per-key デバウンスの重複 | 対応済み+ついで送り | `Services/PerKeyDebouncer.swift` を `ProjectFileWatcher` / `CodingAgentStatusWatcher` が使用。`ProjectTextSearchViewModel.scheduleSearch(debounce:)` は手書きのまま(ついで送り) |
| L2 | テストの静かなスキップ | 対応済み | `AGENTS.md` が実行後の skip 行確認を要求、`verify.yml` が skip 検出時に `::warning::` を出す |
| L3 | AGENTS.md 未記載の暗黙知 | 対応済み | hook 実体パスと `RURI_AGENT_STATUS_HOOK`、ripgrep 15.1.0 の2箇所ピン、`mizu-cloud` ランナー、永続化の使い分け基準を `AGENTS.md` で確認 |
| L4 | gitignore 判定・パス整形の2系統 | 対応済み(統合しない方針で残置) | `Services/GitIgnoreMatcher.swift` / `Models/SearchResultPathPolicy.swift` 等に用途と境界のコメントが存在し「意図的な分離であり、統合しない」を明記 |
| L5 | 文書の綻び | 対応済み | `README.md:5` は `</h1>` に修正済み、`Tools/java-symbol-resolver/README.md` が存在。「署名なし zip」の表現は据え置き(残置) |

## 意図的に残置したもの(理由)

- **EditorViewModel 本体の分割(H2)**: Git 状態・Review・Worktree・PR・Workspace の核(約1412行)は `refreshGitState`(EditorViewModel.swift:3481)がハブとして7系統からファンインしており、分割より一体維持が妥当と調査で結論。外周は値サブストアと投影(`EditorPaneHostState`/`Actions`)で疎結合が保たれている。
- **`createWorktree(named:)`/`createWorktree(fromRemoteBranch:)` と `tab(for:)`/`tab(containing:in:)` のオーバーロード(H2)**: 引数ラベルが意味を担っており、リネームはかえって可読性を落とすため。
- **`///` doc comment を増やさない(H4)**: `AGENTS.md` 実装方針の「巨大な facade 型では `// MARK:` で内部ナビゲーションを付与し、それ以外でコメントを増やさない規約は維持する」に従う。例外は共有ユーティリティの契約を示す `NSRange+Clamping.swift` の2行のみ。
- **`EditorViewModelSaveTests.swift:67` の 700ms sleep(M1)**: autosave が存在しないことを証明する否定テストの本質であり、待つべき完了イベントが原理的に無い。
- **`EditorRuntimeStoreTests` の RunLoop 能動駆動(M1)**: `DispatchQueue.main.async` + NSScrollView レイアウト待ちが本質で、`Task.sleep` 系の `waitUntil` には置換不可。重複だけを単一コアに統合済み。
- **`EditorDocumentRuntime` / `TerminalRuntime` / `EditorRuntimeStore` の `Views/` 配置(M4)**: NSTextViewDelegate・PTY+NSView 所有・AppKit runtime の lifecycle 辞書であり、配置規約「AppKit view に密結合な Runtime とその lifecycle Store はホスト View と同じ `Views/`」に合致する。
- **gitignore 判定2系統・パス整形2系統の非統合(L4)**: 用途が異なる意図的分離(ツリー表示のグレーアウト用同期判定 vs 検索系の rg ネイティブ解釈、検索結果パスの分類 vs ツリーの表示整形)。境界は各実装のコメントに明文化済み。
- **「署名なし zip」の表現(L5)**: 実際は ad-hoc codesign を含むが、表現の修正は見送り(監査記録に注記あり)。

## 触るときについで対応するもの(着手条件付き)

| 項目 | 内容 | 着手する条件 |
|------|------|--------------|
| I 第3群 | `TerminalLinkResolver`(TerminalRuntime.swift:255)/ `TerminalKeyCommandMatcher`(同:360)の純ロジック enum 2つを `Models/` へ切り出してテスト(第2群と同じ verbatim 移動+テストの2コミット方式) | ターミナルのリンク検出・キーコマンド判定の挙動を変更するとき |
| H 残余(投影の値型化) | `publishGitState`(EditorViewModel.swift:2943)の投影辞書合成を値型へ押し出してテスト可能にする | Git 状態の publish・投影ロジックを変更するとき |
| H 残余(系統の張り替え) | 系統単位のコーディネータ化・本体分割。`ContentView` が `editor.` を117箇所直接参照しており張り替えコストが大きい | `ContentView` 側の大改修を行うときに限る(単独では着手しない) |
| M3 残余 | `EditorPaneViewController`(EditorPaneHostView.swift 内)・`EditorTextViewAppKit` 本体のテスト。まずロジックを値型へ押し出してから張る | 該当領域の挙動を変更するとき(AppKit 密結合部を直接テストしようとしない) |
| M6 残存 | `ReviewDiffView.swift` / `EditorPaneHostView.swift` の同居型のうち純ロジック型の `Models/` への移動 | 該当型を変更するとき、配置規約に従い移動してからテスト |
| M7 | 各テストファイルの private `makeTemporaryDirectory`(16コピー)を `TestSupport` へ委譲 | そのテストファイルを触るとき。コピー版と共有版で `withIntermediateDirectories` 等の微差があるため、置換時はテスト緑を実測 |
| M2 残り | フォーマッタ(swiftformat 等)の導入 | 整形差分がレビューの妨げになる事態が実際に起きたとき。導入時は一括整形コミットを分離 |
| L1 残り | `ProjectTextSearchViewModel` の手書きデバウンスを `PerKeyDebouncer` へ寄せる | 検索のデバウンス挙動を変更するとき |
| doc comment | 共有ユーティリティの非自明な契約(境界値・nil の扱い)に限った `///` | 新しい共有ユーティリティを追加するとき(NSRange+Clamping の前例に倣う。一般コードには増やさない) |

## この一連の作業で確立された規約・パターン

いずれも main で実在を確認済み。今後の変更はこれらを前例として使う。

- **配置規約**: 永続 I/O を持つ Store/Service は `Services/`、UserDefaults 設定・値型のメモリ内 Store・純ロジックは `Models/`、AppKit view に密結合な Runtime とその lifecycle Store はホスト View と同じ `Views/`。→ `AGENTS.md` 実装方針(ディレクトリ配置)
- **値型サブストア方式**: 巨大 ViewModel から決定ロジックを値型へ抽出してテストする。前例: `Models/EditorSaveStore.swift` / `EditorCodeNavigationStore.swift` / `EditorMetadataLocationStore.swift`
- **特性テスト付き重複統合**: 重複実装を統合する前に既存挙動を特性化テストで凍結する。前例: `FileURLRewriter` 一元化(`PathNormalizationCharacterizationTests` / `RelativePathCharacterizationTests`)、`NSRange+Clamping`(`NSRangeClampingTests`)
- **ロジックのモデル押し出し+inline 期待値スナップショット**: View/Service の純データ出力をそのまま固定する。前例: `SyntaxHighlightingServiceTests` の role 段階スナップショット(`location:length role «text»` 形式、レコーディング後に期待値固定)、`EditorPaneHostModelsTests` の状態変換固定
- **挙動ゼロ移動の2コミット方式**: コミット1=verbatim 移動(アクセス修飾子の除去のみ、削除行と追加行の一致を diff で機械検証)、コミット2=テスト追加。各コミット直後にフルスイート緑・skip 0・`swiftlint lint --strict` 違反 0 を実測。前例: status bar 5値型の移動(PR #20)
- **大 facade 型への MARK 付与**: 分割しない巨大型には `// MARK:` の責務区切りで内部ナビゲーションを付与する(それ以外でコメントを増やさない)。→ `AGENTS.md` 実装方針、前例: 大ファイル5本・計114箇所
- **規約の機械検出**: 禁止規約は `.swiftlint.yml` の custom_rules で検出し、`verify.yml` が `--strict` で fail させる。前例: `direct_process_run` / `windowgroup_url_self` / `external_lsp_launch` の3件
- **テスト実務**: 部分実行は `-only-testing:RuriTests/XxxTests`、実行後は skip 行ゼロを確認(`AGENTS.md`)。ポーリング待ちは `TestSupport.waitUntil`、一時ディレクトリは `TestSupport.makeTemporaryDirectory` を使う
- **監査記録の凍結運用**: `AGENT_EXPERIENCE.md` の指摘本文は書き換えず、解消した指摘の「対応状況」行のみ更新する。本書はその最終スナップショットであり、以後の状態変化は `AGENT_EXPERIENCE.md` の対応状況行と main のコードを正とする
