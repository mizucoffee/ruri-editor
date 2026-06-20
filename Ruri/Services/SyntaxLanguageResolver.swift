//
//  SyntaxLanguageResolver.swift
//  ruri
//

import Foundation

struct SyntaxLanguageOption: Equatable, Hashable, Sendable {
    let identifier: String
    let displayName: String
}

enum SyntaxLanguageResolver {
    private static let displayNameOverrides: [String: String] = [
        "1c": "1C",
        "abnf": "ABNF",
        "accesslog": "Access Log",
        "apache": "Apache",
        "applescript": "AppleScript",
        "arduino": "Arduino",
        "armasm": "ARM Assembly",
        "asciidoc": "AsciiDoc",
        "bash": "Bash",
        "bnf": "BNF",
        "c": "C",
        "cal": "C/AL",
        "clojure": "Clojure",
        "cmake": "CMake",
        "coq": "Coq",
        "cpp": "C++",
        "csharp": "C#",
        "css": "CSS",
        "dart": "Dart",
        "delphi": "Delphi",
        "diff": "Diff",
        "django": "Django",
        "dns": "DNS",
        "dockerfile": "Dockerfile",
        "dos": "Batch",
        "elixir": "Elixir",
        "erlang": "Erlang",
        "fsharp": "F#",
        "go": "Go",
        "gradle": "Gradle",
        "graphql": "GraphQL",
        "groovy": "Groovy",
        "htmlbars": "HTMLBars",
        "http": "HTTP",
        "ini": "INI",
        "java": "Java",
        "javascript": "JavaScript",
        "json": "JSON",
        "julia": "Julia",
        "kotlin": "Kotlin",
        "less": "Less",
        "llvm": "LLVM",
        "lua": "Lua",
        "makefile": "Makefile",
        "markdown": "Markdown",
        "nginx": "Nginx",
        "objectivec": "Objective-C",
        "perl": "Perl",
        "php": "PHP",
        "plaintext": "Plain Text",
        "powershell": "PowerShell",
        "protobuf": "Protocol Buffers",
        "python": "Python",
        "r": "R",
        "ruby": "Ruby",
        "rust": "Rust",
        "scala": "Scala",
        "scss": "SCSS",
        "sql": "SQL",
        "swift": "Swift",
        "toml": "TOML",
        "typescript": "TypeScript",
        "vbnet": "VB.NET",
        "wasm": "WebAssembly",
        "xml": "XML",
        "yaml": "YAML"
    ]

    private static let exactFileNameLanguages: [String: String] = [
        "dockerfile": "dockerfile",
        "gemfile": "ruby",
        "makefile": "makefile",
        "podfile": "ruby",
        "rakefile": "ruby"
    ]

    private static let extensionLanguages: [String: String] = [
        "bat": "dos",
        "c": "c",
        "cc": "cpp",
        "clj": "clojure",
        "cmd": "dos",
        "cpp": "cpp",
        "cs": "csharp",
        "css": "css",
        "dart": "dart",
        "diff": "diff",
        "erl": "erlang",
        "ex": "elixir",
        "exs": "elixir",
        "fs": "fsharp",
        "go": "go",
        "gradle": "groovy",
        "graphql": "graphql",
        "groovy": "groovy",
        "htm": "html",
        "hpp": "cpp",
        "hrl": "erlang",
        "html": "html",
        "ini": "ini",
        "java": "java",
        "jl": "julia",
        "js": "javascript",
        "json": "json",
        "jsonl": "json",
        "jsx": "javascript",
        "kt": "kotlin",
        "kts": "kotlin",
        "less": "less",
        "lua": "lua",
        "m": "objectivec",
        "md": "markdown",
        "mm": "objectivec",
        "php": "php",
        "pl": "perl",
        "pm": "perl",
        "proto": "protobuf",
        "ps1": "powershell",
        "py": "python",
        "r": "r",
        "rb": "ruby",
        "rs": "rust",
        "sass": "scss",
        "scala": "scala",
        "scss": "scss",
        "sh": "bash",
        "sql": "sql",
        "swift": "swift",
        "toml": "toml",
        "ts": "typescript",
        "tsx": "typescript",
        "vue": "html",
        "xml": "xml",
        "yaml": "yaml",
        "yml": "yaml",
        "zsh": "bash"
    ]

    static func languageName(for url: URL) -> String? {
        let lowercasedFileName = url.lastPathComponent.lowercased()
        if let language = exactFileNameLanguages[lowercasedFileName] {
            return language
        }

        let pathExtension = url.pathExtension.lowercased()
        guard !pathExtension.isEmpty else { return nil }
        return extensionLanguages[pathExtension]
    }

    static func displayName(for languageName: String) -> String {
        if let displayName = displayNameOverrides[languageName] {
            return displayName
        }

        return languageName
            .split(separator: "-")
            .map { segment in
                String(segment.prefix(1)).uppercased() + String(segment.dropFirst())
            }
            .joined(separator: " ")
    }

    static func languageOptions(for languageNames: [String]) -> [SyntaxLanguageOption] {
        languageNames
            .map { languageName in
                SyntaxLanguageOption(
                    identifier: languageName,
                    displayName: displayName(for: languageName)
                )
            }
            .sorted { lhs, rhs in
                lhs.displayName.localizedStandardCompare(rhs.displayName) == .orderedAscending
            }
    }

    static func autoDisplayName(for inferredLanguageName: String?) -> String {
        guard let inferredLanguageName else { return "Auto Detect" }
        return "Auto Detect (\(displayName(for: inferredLanguageName)))"
    }
}
