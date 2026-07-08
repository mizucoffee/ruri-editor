//
//  SyntaxHighlightingService.swift
//  ruri
//

import AppKit
import CodeEditLanguages
import Foundation
import SwiftTreeSitter
import TreeSitterGroovy

enum SyntaxHighlightRole: String, Sendable {
    case keyword
    case type
    case string
    case number
    case comment
    case function
    case property
    case `operator`
    case punctuation
    case tag
    case attribute
    case annotation
    case constant
    case variable
}

struct SyntaxHighlightRun: Equatable, Sendable {
    let location: Int
    let length: Int
    let role: SyntaxHighlightRole

    var range: NSRange {
        NSRange(location: location, length: length)
    }
}

final class SyntaxHighlightingService: @unchecked Sendable {
    private let worker = TreeSitterSyntaxHighlightingWorker()
    nonisolated static let maximumHighlightedUTF16Length = 1_000_000

    nonisolated let supportedLanguageOptions: [SyntaxLanguageOption] = SyntaxLanguageResolver.languageOptions(
        for: TreeSitterSyntaxHighlightingWorker.supportedLanguageNames
    )

    nonisolated func highlightedRuns(for text: String, languageName: String?) async -> [SyntaxHighlightRun] {
        guard text.utf16.count <= Self.maximumHighlightedUTF16Length else {
            return []
        }

        return await worker.highlightedRuns(for: text, languageName: languageName)
    }

    static func themeName(for appearance: NSAppearance?) -> String {
        let effectiveAppearance = appearance ?? NSApp?.effectiveAppearance
        let match = effectiveAppearance?.bestMatch(from: [.darkAqua, .aqua])
        return match == .darkAqua ? "tree-sitter-dark" : "tree-sitter-light"
    }
}

private actor TreeSitterSyntaxHighlightingWorker {
    static let supportedLanguageNames = [
        "java",
        "kotlin",
        "groovy",
        "swift",
        "javascript",
        "typescript",
        "json",
        "sql",
        "markdown",
        "yaml",
        "css",
        "html",
        "xml"
    ]

    private var cachedQueries: [String: Query] = [:]

    func highlightedRuns(for text: String, languageName: String?) -> [SyntaxHighlightRun] {
        guard !text.isEmpty,
              let languageName,
              let languageConfiguration = languageConfiguration(for: languageName),
              let language = languageConfiguration.language,
              let query = query(for: languageConfiguration, languageName: languageName) else {
            return []
        }

        let parser = Parser()
        do {
            try parser.setLanguage(language)
        } catch {
            return []
        }

        guard let tree = parser.parse(text) else {
            return []
        }

        let cursor = query.execute(in: tree)
        let ranges = cursor
            .resolve(with: Predicate.Context(string: text))
            .highlights()

        return normalizedRuns(from: ranges, textUTF16Length: text.utf16.count, languageName: languageName)
    }

    private func languageConfiguration(for languageName: String) -> TreeSitterLanguageConfiguration? {
        switch languageName {
        case "java":
            return .codeEdit(.java)
        case "kotlin":
            return .codeEdit(.kotlin)
        case "groovy":
            return .groovy
        case "swift":
            return .codeEdit(.swift)
        case "javascript":
            return .codeEdit(.javascript)
        case "typescript":
            return .codeEdit(.typescript)
        case "json":
            return .codeEdit(.json)
        case "sql":
            return .codeEdit(.sql)
        case "markdown":
            return .codeEdit(.markdown)
        case "yaml":
            return .codeEdit(.yaml)
        case "css":
            return .codeEdit(.css)
        case "html", "xml":
            return .codeEdit(.html)
        default:
            return nil
        }
    }

    private func query(for configuration: TreeSitterLanguageConfiguration, languageName: String) -> Query? {
        if let cachedQuery = cachedQueries[languageName] {
            return cachedQuery
        }

        guard let query = makeQuery(for: configuration) else {
            return nil
        }

        cachedQueries[languageName] = query
        return query
    }

    private func makeQuery(for configuration: TreeSitterLanguageConfiguration) -> Query? {
        switch configuration {
        case .codeEdit(let codeLanguage):
            // Java はパッケージ同梱クエリだと宣言/呼び出し・フィールド・アノテーションを
            // 区別できないため、自前クエリで上書きする。
            if codeLanguage.id == .java {
                return makeQuery(language: codeLanguage.language, source: Self.javaHighlightQuery)
            }

            if let query = TreeSitterModel.shared.query(for: codeLanguage.id) {
                return query
            }

            guard codeLanguage.id == .swift else { return nil }
            return makeQuery(language: codeLanguage.language, source: Self.swiftHighlightQuery)

        case .groovy:
            return makeQuery(language: configuration.language, source: Self.groovyHighlightQuery)
        }
    }

    private func makeQuery(language: Language?, source: String) -> Query? {
        guard let language,
              let data = source.data(using: .utf8) else {
            return nil
        }

        return try? Query(language: language, data: data)
    }

    private func normalizedRuns(
        from ranges: [NamedRange],
        textUTF16Length: Int,
        languageName: String
    ) -> [SyntaxHighlightRun] {
        ranges.compactMap { range in
            guard let role = SyntaxHighlightRole(
                captureNameComponents: range.nameComponents,
                languageName: languageName
            ) else {
                return nil
            }

            let nsRange = range.range
            guard nsRange.location >= 0,
                  nsRange.length > 0,
                  NSMaxRange(nsRange) <= textUTF16Length else {
                return nil
            }

            return SyntaxHighlightRun(
                location: nsRange.location,
                length: nsRange.length,
                role: role
            )
        }
    }

    // IntelliJ 準拠の色分けのための自前 Java クエリ。同梱クエリとの差分:
    // メソッドは宣言のみ色付け(呼び出しは capture しない)、フィールド/enum 定数を @property/@constant、
    // アノテーションを @annotation、プリミティブ型と this/super をキーワード扱いにする。
    private static let javaHighlightQuery = """
    (line_comment) @comment
    (block_comment) @comment

    [
      (hex_integer_literal)
      (decimal_integer_literal)
      (octal_integer_literal)
      (decimal_floating_point_literal)
      (hex_floating_point_literal)
    ] @number

    [
      (character_literal)
      (string_literal)
    ] @string
    (escape_sequence) @string

    [
      (true)
      (false)
      (null_literal)
    ] @constant.builtin

    (method_declaration name: (identifier) @function)

    (marker_annotation "@" @annotation name: [(identifier) (scoped_identifier)] @annotation)
    (annotation "@" @annotation name: [(identifier) (scoped_identifier)] @annotation)

    (field_declaration declarator: (variable_declarator name: (identifier) @property))
    (field_access field: (identifier) @property)
    (enum_constant name: (identifier) @constant)

    ((identifier) @constant
     (#match? @constant "^_*[A-Z][A-Z\\\\d_]+$"))

    (type_identifier) @type
    (interface_declaration name: (identifier) @type)
    (class_declaration name: (identifier) @type)
    (enum_declaration name: (identifier) @type)
    (constructor_declaration name: (identifier) @type)

    [
      (boolean_type)
      (integral_type)
      (floating_point_type)
      (void_type)
    ] @keyword

    (this) @keyword
    (super) @keyword

    [
      "abstract"
      "assert"
      "break"
      "case"
      "catch"
      "class"
      "continue"
      "default"
      "do"
      "else"
      "enum"
      "exports"
      "extends"
      "final"
      "finally"
      "for"
      "if"
      "implements"
      "import"
      "instanceof"
      "interface"
      "module"
      "native"
      "new"
      "non-sealed"
      "open"
      "opens"
      "package"
      "private"
      "protected"
      "provides"
      "public"
      "requires"
      "record"
      "return"
      "sealed"
      "static"
      "strictfp"
      "switch"
      "synchronized"
      "throw"
      "throws"
      "to"
      "transient"
      "transitive"
      "try"
      "uses"
      "volatile"
      "while"
      "with"
    ] @keyword
    """

    private static let groovyHighlightQuery = """
    (line_comment) @comment
    (block_comment) @comment
    (groovydoc_comment) @comment

    (number_literal) @number
    (string_literal) @string
    (string_fragment) @string
    (boolean_literal) @constant.builtin
    (null_literal) @constant.builtin

    (identifier) @variable

    [
      "as"
      "in"
      "instanceof"
      "new"
    ] @keyword.operator

    [
      "assert"
      "break"
      "case"
      "catch"
      "continue"
      "default"
      "do"
      "else"
      "finally"
      "for"
      "if"
      "return"
      "switch"
      "throw"
      "throws"
      "try"
      "while"
      "yield"
    ] @keyword

    [
      "class"
      "def"
      "enum"
      "extends"
      "implements"
      "import"
      "interface"
      "non-sealed"
      "package"
      "permits"
      "pipeline"
      "record"
      "sealed"
      "trait"
      "var"
    ] @keyword

    [
      "abstract"
      "final"
      "native"
      "private"
      "protected"
      "public"
      "static"
      "strictfp"
      "synchronized"
      "transient"
      "volatile"
    ] @keyword

    [
      "+"
      "-"
      "*"
      "/"
      "%"
      "="
      "=="
      "!="
      "<"
      ">"
      "<="
      ">="
      "&&"
      "||"
      "!"
      "?:"
      "?."
      "*."
      ".."
      "..<"
      "<=>"
    ] @operator

    (field_access field: [(identifier) (quoted_identifier)] @property)
    (safe_navigation_expression property: [(identifier) (quoted_identifier)] @property)
    (safe_chain_dot_expression property: [(identifier) (quoted_identifier)] @property)
    (spread_dot_expression property: [(identifier) (quoted_identifier)] @property)
    (direct_field_access_expression field: [(identifier) (quoted_identifier)] @property)
    (method_pointer_expression method: [(identifier) (quoted_identifier)] @function)
    (method_reference_expression name: (identifier) @function)

    (class_declaration name: (identifier) @type.definition)
    (trait_declaration name: (identifier) @type.definition)
    (interface_declaration name: (identifier) @type.definition)
    (enum_declaration name: (identifier) @type.definition)
    (record_declaration name: (identifier) @type.definition)
    (annotation_type_declaration name: (identifier) @type.definition)
    (enum_constant name: (identifier) @constant)
    (method_declaration name: [(identifier) (quoted_identifier)] @function)
    (constructor_declaration name: (identifier) @constructor)
    (formal_parameter name: (identifier) @variable.parameter)
    (closure_parameter name: (identifier) @variable.parameter)
    (record_component name: (identifier) @variable.parameter)
    (variable_declarator name: (identifier) @variable)
    (field_declaration (variable_declarator name: (identifier) @property))

    (method_invocation function: (identifier) @function.call)
    (method_invocation function: (field_access field: (identifier) @function.call))
    (command_chain receiver: (identifier) @function.call)

    (type_identifier) @type
    (annotation "@" @annotation name: (qualified_name) @annotation)
    """

    private static let swiftHighlightQuery = """
    [ "." ";" ":" "," ] @punctuation.delimiter
    [ "\\(" "(" ")" "[" "]" "{" "}" ] @punctuation.bracket

    (attribute) @annotation
    (type_identifier) @type
    (self_expression) @variable.builtin

    "func" @keyword
    [
      (visibility_modifier)
      (member_modifier)
      (function_modifier)
      (property_modifier)
      (parameter_modifier)
      (inheritance_modifier)
    ] @keyword
    (function_declaration (simple_identifier) @function)
    (function_declaration ["init" @constructor])
    (throws) @keyword
    "async" @keyword
    "await" @keyword
    (where_keyword) @keyword
    (parameter external_name: (simple_identifier) @parameter)
    (parameter name: (simple_identifier) @parameter)
    (pattern bound_identifier: (simple_identifier)) @variable

    [
      "typealias"
      "struct"
      "class"
      "actor"
      "enum"
      "protocol"
      "extension"
      "indirect"
      "nonisolated"
      "override"
      "convenience"
      "required"
      "some"
    ] @keyword

    (import_declaration ["import" @keyword])
    (enum_entry ["case" @keyword])

    (call_expression (simple_identifier) @function.call)
    (call_expression
      (navigation_expression
        (navigation_suffix (simple_identifier) @function.call)))

    (for_statement ["for" @keyword])
    (for_statement ["in" @keyword])
    (else) @keyword
    (as_operator) @keyword
    ["while" "repeat" "continue" "break"] @keyword
    ["let" "var"] @keyword
    (guard_statement ["guard" @keyword])
    (if_statement ["if" @keyword])
    (switch_statement ["switch" @keyword])
    (switch_entry ["case" @keyword])
    (switch_entry ["fallthrough" @keyword])
    (switch_entry (default_keyword) @keyword)
    "return" @keyword
    ["do" (throw_keyword) (catch_keyword)] @keyword

    [
      (comment)
      (multiline_comment)
    ] @comment

    (line_str_text) @string
    (str_escaped_char) @string
    (multi_line_str_text) @string
    (raw_str_part) @string
    (raw_str_end_part) @string
    ["\\"" "\\"\\"\\""] @string

    [
      (integer_literal)
      (hex_literal)
      (oct_literal)
      (bin_literal)
    ] @number
    (real_literal) @number
    (boolean_literal) @constant.builtin
    "nil" @constant.builtin
    (regex_literal) @string

    (custom_operator) @operator
    [
      "try"
      "try?"
      "try!"
      "!"
      "+"
      "-"
      "*"
      "/"
      "%"
      "="
      "+="
      "-="
      "*="
      "/="
      "<"
      ">"
      "<="
      ">="
      "&"
      "~"
      "%="
      "!="
      "!=="
      "=="
      "==="
      "??"
      "->"
      "..<"
      "..."
    ] @operator
    """
}

private enum TreeSitterLanguageConfiguration {
    case codeEdit(CodeLanguage)
    case groovy

    nonisolated var language: Language? {
        switch self {
        case .codeEdit(let codeLanguage):
            return codeLanguage.language
        case .groovy:
            return Language(language: tree_sitter_groovy())
        }
    }
}

private extension SyntaxHighlightRole {
    nonisolated init?(captureNameComponents: [String], languageName: String) {
        guard let firstComponent = captureNameComponents.first else {
            return nil
        }

        switch firstComponent {
        case "comment":
            self = .comment
        case "string", "escape", "character":
            self = .string
        case "number", "float":
            self = .number
        case "keyword", "conditional", "repeat", "exception", "storageclass":
            self = .keyword
        case "type", "constructor", "class", "namespace", "module":
            self = .type
        case "text":
            switch captureNameComponents.dropFirst().first {
            case "title":
                // markdown 見出し。IntelliJ はキーワード系の色 + 太字で表示する。
                self = .keyword
            case "literal":
                self = .string
            case "uri", "reference":
                self = .attribute
            default:
                self = .variable
            }
        case "function", "method":
            // IntelliJ 流儀では呼び出しはデフォルト色。宣言(と区別のないクエリの capture)のみ色付け。
            guard captureNameComponents.dropFirst().first != "call" else {
                return nil
            }
            self = .function
        case "property", "field":
            self = .property
        case "operator":
            self = .operator
        case "punctuation":
            self = .punctuation
        case "tag":
            self = .tag
        case "annotation":
            self = .annotation
        case "attribute":
            // Kotlin の同梱クエリはアノテーションを @attribute で capture する。
            // HTML/XML/CSS などの属性と色を分けるためここで振り分ける。
            self = languageName == "kotlin" ? .annotation : .attribute
        case "label":
            self = .attribute
        case "constant":
            // constant.builtin(true/false/null など)は IntelliJ ではキーワード色。
            self = captureNameComponents.dropFirst().first == "builtin" ? .keyword : .constant
        case "boolean", "null":
            self = .keyword
        case "symbol":
            self = .constant
        case "variable", "identifier", "parameter":
            self = .variable
        default:
            return nil
        }
    }
}
