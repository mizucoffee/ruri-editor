# java-symbol-resolver

Ruriのレビュー用Javaコードナビゲーション(シンボル解決)を担う同梱CLIツール。JavaParser + JavaSymbolSolver(`javaparser-symbol-solver-core`)を使い、外部LSP(`jdtls` 等)は起動しない方針(ルート `AGENTS.md` 参照)。

## 要件

- Java 17以上(Gradle toolchainは17を指定)
- ビルドは同梱のGradle wrapper(`./gradlew`)を使う

## ビルドと同梱

アプリへの同梱確認は、repo rootから次を実行する:

```sh
Scripts/build-java-symbol-resolver.sh
```

このスクリプトは同梱 `gradlew`(なければシステムの `gradle`)で `shadowJar` を実行し、`build/libs/java-symbol-resolver.jar` を `Ruri/Resources/Tools/java-symbol-resolver.jar` へコピーする。生成されたJARはgit管理しない。

このディレクトリ単体でビルドする場合:

```sh
./gradlew shadowJar
```

出力は `build/libs/java-symbol-resolver.jar`(shadowJarの設定でバージョン・classifierなしの固定ファイル名)。

## テスト

```sh
./gradlew test
```

JUnit 5(`useJUnitPlatform()`)。PR時は `.github/workflows/verify.yml` の `java-tests` ジョブが同じテストを自動実行する。

## アプリ側からの利用

`Ruri/Services/JavaSymbolResolverClient.swift` がapp bundle内の `Tools/` → `Resources/Tools/` → bundle rootの順で `java-symbol-resolver.jar` を解決し、`java -Xmx<N>m -jar` で起動する。ヒープ上限は物理メモリの1/4を1024–4096MBにクランプした値(`JavaResolverHeapLimit`)。JARが見つからない場合はエラーになるため、シンボルジャンプ関連の動作確認前に上記のビルドを行う。

`OutOfMemoryError` 発生時は当該リクエストへのエラー応答を書き出した後、終了コード3(`Main.EXIT_CODE_OUT_OF_MEMORY`、Swift側の `outOfMemoryExitCode` と対応)でプロセスを終了する。クライアントは次のリクエストで自動的に再起動する。

## 構成

- エントリポイント: `net.mizucoffee.ruri.symbol.Main`
- ソース: `src/main/java/net/mizucoffee/ruri/symbol/`
- テスト: `src/test/java/net/mizucoffee/ruri/symbol/`
