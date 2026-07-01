## Codex向けメモ

### 環境
- このプロジェクトは `Ruri.xcodeproj` で開くmacOS SwiftUIアプリ。
- App targetのSwift module名は `ruri` に固定し、`RuriTests` は `@testable import ruri` で参照する。
- 設定済みのMac Development証明書がない環境では通常の署名が失敗することがある。コード検証では `CODE_SIGNING_ALLOWED=NO` を使う。
- Javaシンボルジャンプは同梱 `java-symbol-resolver.jar`（JavaParser + JavaSymbolSolver）を使う。ローカル確認では `Scripts/build-java-symbol-resolver.sh` でJARを生成し、実行環境にはJava 17以上が必要。

```sh
xcodebuild -project Ruri.xcodeproj -scheme Ruri -destination platform=macOS -derivedDataPath /private/tmp/ruri-derived-data CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build
```

```sh
xcodebuild test -project Ruri.xcodeproj -scheme Ruri -destination platform=macOS -derivedDataPath /private/tmp/ruri-derived-data CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO
```

### 公開repo運用
- このリポジトリは `mizucoffee/ruri` から同期される公開・配布repo。
- `main` pushで `.github/workflows/release-macos-app.yml` が署名なしarm64 Release `.app` zipをビルドし、`homebrew-latest` と `v1.0.<run_number>` releaseを更新する。
- 公開repo固有のREADME、Cask、Actions、AGENTSは `mizucoffee/ruri` 側の `PublicRepository/ruri-editor/` で管理する。
