//
//  SyntaxHighlightingServiceTests.swift
//  ruriTests
//

import XCTest
@testable import ruri

// AGENTS.md の「Tree-sitter の query/capture mapping や対応言語を変更するときの11言語色分け検証」を
// role 段階のスナップショットとして自動化するテスト。
//
// このスナップショットが固定するもの / 揺れうるもの:
// - 固定: text → [SyntaxHighlightRun](location/length/role)の分割結果。capture 名の段階には立ち入らない。
//   同一範囲に複数 role の run が重複して返るのも現状の仕様として固定する(描画側は後勝ちで上書き)。
// - 揺れうるもの: role 分割は依存パッケージ(CodeEditLanguages / tree-sitter-groovy)の highlight query に
//   依存するため、パッケージ更新でスナップショットが正当に変わりうる。その場合は差分をレビューして
//   期待値を更新する。各テスト後段の「最低限含まれるべき role 集合」の包含アサーションは、
//   再記録時にも検証の意図(その言語で色分けされるべきトークン種)が守られるためのガード。
// - capture 名 → role のマッピング(SyntaxHighlightingService.swift)はアプリ側コードなので、
//   パッケージ更新を伴わずにスナップショットが変わった場合は意図した変更かを疑うこと。
//
// Gradle は SyntaxLanguageResolver が拡張子 .gradle を "groovy" に、JSONL は .jsonl を "json" に
// 正規化してから本サービスに渡る(SyntaxLanguageResolverTests で固定)。そのため Gradle/JSONL の
// 検証は languageName "groovy"/"json" にそれぞれの風のサンプルを与えて行う。
// XML は languageName "xml" がそのまま受理され、HTML 文法で処理される。
final class SyntaxHighlightingServiceTests: XCTestCase {
    private let service = SyntaxHighlightingService()

    // MARK: - Java

    private static let javaSample = """
    // greeting
    public class Greeter {
        private static final int COUNT = 2;
        String greet(String name) {
            return "Hello, " + name;
        }
    }
    """

    func testJavaHighlightingMatchesRoleSnapshot() async {
        let result = await highlightResult(for: Self.javaSample, languageName: "java")
        XCTAssertEqual(
            result.snapshot,
            """
            0:11 comment «// greeting»
            12:6 keyword «public»
            19:5 keyword «class»
            25:7 type «Greeter»
            25:7 variable «Greeter»
            39:7 keyword «private»
            47:6 keyword «static»
            54:5 keyword «final»
            60:3 type «int»
            64:5 constant «COUNT»
            64:5 variable «COUNT»
            72:1 number «2»
            79:6 type «String»
            86:5 variable «greet»
            86:5 function «greet»
            92:6 type «String»
            99:4 variable «name»
            115:6 keyword «return»
            122:9 string «"Hello, "»
            134:4 variable «name»
            """
        )
        XCTAssertTrue(result.roles.isSuperset(of: [.comment, .keyword, .type, .number, .string, .function]))
    }

    // MARK: - JavaScript

    private static let javaScriptSample = """
    // counter
    const count = 42;
    function add(a, b) {
      return a + b;
    }
    console.log(`total: ${add(count, 1)}`);
    """

    func testJavaScriptHighlightingMatchesRoleSnapshot() async {
        let result = await highlightResult(for: Self.javaScriptSample, languageName: "javascript")
        XCTAssertEqual(
            result.snapshot,
            """
            0:10 comment «// counter»
            11:5 keyword «const»
            17:5 variable «count»
            23:1 operator «=»
            25:2 number «42»
            27:1 punctuation «;»
            29:8 keyword «function»
            38:3 function «add»
            38:3 variable «add»
            41:1 punctuation «(»
            42:1 variable «a»
            43:1 punctuation «,»
            45:1 variable «b»
            46:1 punctuation «)»
            48:1 punctuation «{»
            52:6 keyword «return»
            59:1 variable «a»
            61:1 operator «+»
            63:1 variable «b»
            64:1 punctuation «;»
            66:1 punctuation «}»
            68:7 variable «console»
            68:7 variable «console»
            75:1 punctuation «.»
            76:3 property «log»
            76:3 function «log»
            79:1 punctuation «(»
            80:25 string «`total: ${add(count, 1)}`»
            88:2 punctuation «${»
            90:3 function «add»
            90:3 variable «add»
            93:1 punctuation «(»
            94:5 variable «count»
            99:1 punctuation «,»
            101:1 number «1»
            102:1 punctuation «)»
            103:1 punctuation «}»
            103:1 punctuation «}»
            105:1 punctuation «)»
            106:1 punctuation «;»
            """
        )
        XCTAssertTrue(result.roles.isSuperset(of: [.comment, .keyword, .number, .function, .variable, .string]))
    }

    // MARK: - Kotlin

    private static let kotlinSample = """
    // entry
    fun main() {
        val label: String = "ruri"
        println(label.length + 1)
    }
    """

    func testKotlinHighlightingMatchesRoleSnapshot() async {
        let result = await highlightResult(for: Self.kotlinSample, languageName: "kotlin")
        XCTAssertEqual(
            result.snapshot,
            """
            0:8 comment «// entry»
            9:3 keyword «fun»
            13:4 variable «main»
            13:4 function «main»
            17:1 punctuation «(»
            18:1 punctuation «)»
            20:1 punctuation «{»
            26:3 keyword «val»
            30:5 variable «label»
            35:1 punctuation «:»
            37:6 type «String»
            37:6 type «String»
            44:1 operator «=»
            46:6 string «"ruri"»
            57:7 variable «println»
            57:7 function «println»
            57:7 function «println»
            64:1 punctuation «(»
            65:5 variable «label»
            70:1 punctuation «.»
            71:6 variable «length»
            71:6 property «length»
            78:1 operator «+»
            80:1 number «1»
            81:1 punctuation «)»
            83:1 punctuation «}»
            """
        )
        XCTAssertTrue(result.roles.isSuperset(of: [.comment, .keyword, .type, .string, .function, .number]))
    }

    // MARK: - Groovy

    private static let groovySample = """
    // task
    def label = "ruri"
    int total = 1 + 2
    println "total: ${total}"
    """

    func testGroovyHighlightingMatchesRoleSnapshot() async {
        let result = await highlightResult(for: Self.groovySample, languageName: "groovy")
        XCTAssertEqual(
            result.snapshot,
            """
            0:7 comment «// task»
            8:3 keyword «def»
            12:5 variable «label»
            12:5 variable «label»
            18:1 operator «=»
            20:6 string «"ruri"»
            21:4 string «ruri»
            27:3 type «int»
            31:5 variable «total»
            37:1 operator «=»
            39:1 number «1»
            41:1 operator «+»
            43:1 number «2»
            45:7 variable «println»
            45:7 function «println»
            53:17 string «"total: ${total}"»
            54:7 string «total: »
            63:5 variable «total»
            """
        )
        XCTAssertTrue(result.roles.isSuperset(of: [.comment, .keyword, .string, .number]))
    }

    // MARK: - Gradle(拡張子 .gradle は resolver が "groovy" に解決する)

    private static let gradleSample = """
    plugins {
        id 'java'
    }
    dependencies {
        implementation 'org.slf4j:slf4j-api:2.0.13'
    }
    """

    func testGradleStyleGroovyHighlightingMatchesRoleSnapshot() async {
        let result = await highlightResult(for: Self.gradleSample, languageName: "groovy")
        XCTAssertEqual(
            result.snapshot,
            """
            0:7 variable «plugins»
            0:7 function «plugins»
            14:2 variable «id»
            14:2 function «id»
            17:6 string «'java'»
            26:12 variable «dependencies»
            26:12 function «dependencies»
            45:14 variable «implementation»
            45:14 function «implementation»
            60:28 string «'org.slf4j:slf4j-api:2.0.13'»
            """
        )
        XCTAssertTrue(result.roles.isSuperset(of: [.string, .function]))
    }

    // MARK: - TypeScript

    private static let typeScriptSample = """
    // model
    interface User { id: number }
    const admin: User = { id: 1 };
    function label(user: User): string {
      return `user-${user.id}`;
    }
    """

    func testTypeScriptHighlightingMatchesRoleSnapshot() async {
        let result = await highlightResult(for: Self.typeScriptSample, languageName: "typescript")
        XCTAssertEqual(
            result.snapshot,
            """
            0:8 comment «// model»
            9:9 keyword «interface»
            19:4 type «User»
            24:1 punctuation «{»
            26:2 property «id»
            30:6 type «number»
            37:1 punctuation «}»
            39:5 keyword «const»
            45:5 variable «admin»
            52:4 type «User»
            57:1 operator «=»
            59:1 punctuation «{»
            61:2 property «id»
            65:1 number «1»
            67:1 punctuation «}»
            68:1 punctuation «;»
            70:8 keyword «function»
            79:5 function «label»
            79:5 variable «label»
            84:1 punctuation «(»
            85:4 variable «user»
            85:4 variable «user»
            91:4 type «User»
            95:1 punctuation «)»
            98:6 type «string»
            105:1 punctuation «{»
            109:6 keyword «return»
            116:17 string «`user-${user.id}`»
            122:2 punctuation «${»
            124:4 variable «user»
            128:1 punctuation «.»
            129:2 property «id»
            131:1 punctuation «}»
            131:1 punctuation «}»
            133:1 punctuation «;»
            135:1 punctuation «}»
            """
        )
        XCTAssertTrue(
            result.roles.isSuperset(of: [.comment, .keyword, .type, .number, .string, .function, .property])
        )
    }

    // MARK: - JSON

    private static let jsonSample = """
    {
      "name": "ruri",
      "version": 2,
      "stable": true,
      "tags": ["editor", "macos"]
    }
    """

    func testJSONHighlightingMatchesRoleSnapshot() async {
        let result = await highlightResult(for: Self.jsonSample, languageName: "json")
        XCTAssertEqual(
            result.snapshot,
            """
            4:6 string «"name"»
            4:6 string «"name"»
            12:6 string «"ruri"»
            22:9 string «"version"»
            22:9 string «"version"»
            33:1 number «2»
            38:8 string «"stable"»
            38:8 string «"stable"»
            48:4 constant «true»
            56:6 string «"tags"»
            56:6 string «"tags"»
            65:8 string «"editor"»
            75:7 string «"macos"»
            """
        )
        // JSON の highlight query は区切り記号({}[]:,)を capture しないため punctuation は現れない。
        XCTAssertTrue(result.roles.isSuperset(of: [.string, .number, .constant]))
    }

    // MARK: - JSONL(拡張子 .jsonl は resolver が "json" に解決する)

    private static let jsonLinesSample = """
    {"event": "open", "count": 1}
    {"event": "save", "count": 2}
    """

    func testJSONLinesHighlightingMatchesRoleSnapshot() async {
        let result = await highlightResult(for: Self.jsonLinesSample, languageName: "json")
        // 2行目(2つ目のドキュメント)にも run が付くこと(31: 以降)が JSONL 検証の要点。
        XCTAssertEqual(
            result.snapshot,
            """
            1:7 string «"event"»
            1:7 string «"event"»
            10:6 string «"open"»
            18:7 string «"count"»
            18:7 string «"count"»
            27:1 number «1»
            31:7 string «"event"»
            31:7 string «"event"»
            40:6 string «"save"»
            48:7 string «"count"»
            48:7 string «"count"»
            57:1 number «2»
            """
        )
        XCTAssertTrue(result.roles.isSuperset(of: [.string, .number]))
    }

    // MARK: - Markdown

    private static let markdownSample = """
    # Title

    Some *emphasis* and a [link](https://example.com).

    - item one
    """

    func testMarkdownHighlightingMatchesRoleSnapshot() async {
        let result = await highlightResult(for: Self.markdownSample, languageName: "markdown")
        // markdown は block 文法のみで highlight されるため、見出しとリスト記号だけが対象。
        // 強調・リンクは inline 文法側で、現状の highlightedRuns の対象外(色が付かないのが現状仕様)。
        XCTAssertEqual(
            result.snapshot,
            """
            0:1 punctuation «#»
            2:5 type «Title»
            61:2 punctuation «- »
            """
        )
        XCTAssertTrue(result.roles.isSuperset(of: [.type, .punctuation]))
    }

    // MARK: - YAML

    private static let yamlSample = """
    # config
    name: ruri
    count: 2
    stable: true
    tags:
      - editor
    """

    func testYAMLHighlightingMatchesRoleSnapshot() async {
        let result = await highlightResult(for: Self.yamlSample, languageName: "yaml")
        XCTAssertEqual(
            result.snapshot,
            """
            0:8 comment «# config»
            9:4 string «name»
            9:4 property «name»
            13:1 punctuation «:»
            15:4 string «ruri»
            20:5 string «count»
            20:5 property «count»
            25:1 punctuation «:»
            27:1 number «2»
            29:6 string «stable»
            29:6 property «stable»
            35:1 punctuation «:»
            37:4 constant «true»
            42:4 string «tags»
            42:4 property «tags»
            46:1 punctuation «:»
            50:1 punctuation «-»
            52:6 string «editor»
            """
        )
        XCTAssertTrue(result.roles.isSuperset(of: [.comment, .property, .number, .constant, .punctuation]))
    }

    // MARK: - CSS

    private static let cssSample = """
    /* base */
    .editor {
        color: #333;
        margin: 4px;
    }
    """

    func testCSSHighlightingMatchesRoleSnapshot() async {
        let result = await highlightResult(for: Self.cssSample, languageName: "css")
        XCTAssertEqual(
            result.snapshot,
            """
            0:10 comment «/* base */»
            12:6 property «editor»
            25:5 property «color»
            30:1 punctuation «:»
            32:4 string «#333»
            32:1 punctuation «#»
            42:6 property «margin»
            48:1 punctuation «:»
            50:3 number «4px»
            51:2 type «px»
            """
        )
        XCTAssertTrue(result.roles.isSuperset(of: [.comment, .property, .number, .punctuation]))
    }

    // MARK: - HTML

    private static let htmlSample = """
    <!-- page -->
    <div class="editor">
      <a href="index.html">Home</a>
    </div>
    """

    func testHTMLHighlightingMatchesRoleSnapshot() async {
        let result = await highlightResult(for: Self.htmlSample, languageName: "html")
        XCTAssertEqual(
            result.snapshot,
            """
            0:13 comment «<!-- page -->»
            14:1 punctuation «<»
            15:3 tag «div»
            19:5 attribute «class»
            26:6 string «editor»
            33:1 punctuation «>»
            37:1 punctuation «<»
            38:1 tag «a»
            40:4 attribute «href»
            46:10 string «index.html»
            57:1 punctuation «>»
            62:2 punctuation «</»
            64:1 tag «a»
            65:1 punctuation «>»
            67:2 punctuation «</»
            69:3 tag «div»
            72:1 punctuation «>»
            """
        )
        XCTAssertTrue(result.roles.isSuperset(of: [.comment, .tag, .attribute, .string, .punctuation]))
    }

    // MARK: - XML(languageName "xml" は HTML 文法で処理される)

    private static let xmlSample = """
    <config version="2">
      <name>ruri</name>
    </config>
    """

    func testXMLHighlightingMatchesRoleSnapshot() async {
        let result = await highlightResult(for: Self.xmlSample, languageName: "xml")
        XCTAssertEqual(
            result.snapshot,
            """
            0:1 punctuation «<»
            1:6 tag «config»
            8:7 attribute «version»
            17:1 string «2»
            19:1 punctuation «>»
            23:1 punctuation «<»
            24:4 tag «name»
            28:1 punctuation «>»
            33:2 punctuation «</»
            35:4 tag «name»
            39:1 punctuation «>»
            41:2 punctuation «</»
            43:6 tag «config»
            49:1 punctuation «>»
            """
        )
        XCTAssertTrue(result.roles.isSuperset(of: [.tag, .attribute, .string, .punctuation]))
    }

    // MARK: - 境界

    func testUnsupportedLanguageNameReturnsNoRuns() async {
        let runs = await service.highlightedRuns(for: "identification division.", languageName: "cobol")
        XCTAssertEqual(runs, [])
    }

    func testNilLanguageNameReturnsNoRuns() async {
        let runs = await service.highlightedRuns(for: Self.javaSample, languageName: nil)
        XCTAssertEqual(runs, [])
    }

    func testTextExceedingMaximumUTF16LengthReturnsNoRuns() async {
        let oversized = String(repeating: "a", count: SyntaxHighlightingService.maximumHighlightedUTF16Length + 1)
        let runs = await service.highlightedRuns(for: oversized, languageName: "java")
        XCTAssertEqual(runs, [])
    }

    // MARK: - Helpers

    private func highlightResult(
        for source: String,
        languageName: String
    ) async -> (snapshot: String, roles: Set<SyntaxHighlightRole>) {
        let runs = await service.highlightedRuns(for: source, languageName: languageName)
        let nsSource = source as NSString
        let lines = runs.map { run -> String in
            let text = nsSource.substring(with: run.range)
                .replacingOccurrences(of: "\n", with: "\\n")
            return "\(run.location):\(run.length) \(run.role.rawValue) «\(text)»"
        }
        return (lines.joined(separator: "\n"), Set(runs.map(\.role)))
    }
}
