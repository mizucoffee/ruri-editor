//
//  GitIgnoreMatcher.swift
//  ruri
//

import Foundation

struct GitIgnoreMatcher {
    private let rootURL: URL
    private let rootPath: String
    private var rulesByBasePath: [String: [GitIgnoreRule]] = [:]

    nonisolated init(rootURL: URL) {
        let standardizedRootURL = rootURL.standardizedFileURL

        self.rootURL = standardizedRootURL
        self.rootPath = Self.normalizedDirectoryPath(standardizedRootURL)
    }

    nonisolated mutating func isIgnored(_ url: URL, isDirectory: Bool) -> Bool {
        let pathComponents = relativePathComponents(for: url)
        guard !pathComponents.isEmpty else { return false }

        return isIgnored(pathComponents: pathComponents, isDirectory: isDirectory)
    }

    nonisolated mutating func isIgnoredBySelfOrAncestor(_ url: URL, isDirectory: Bool) -> Bool {
        let pathComponents = relativePathComponents(for: url)
        guard !pathComponents.isEmpty else { return false }

        for count in 1...pathComponents.count {
            let components = Array(pathComponents.prefix(count))
            let isTarget = count == pathComponents.count
            if isIgnored(pathComponents: components, isDirectory: isTarget ? isDirectory : true) {
                return true
            }
        }

        return false
    }

    nonisolated private mutating func isIgnored(pathComponents: [String], isDirectory: Bool) -> Bool {
        let parentComponents = Array(pathComponents.dropLast())
        var ignored = false

        for depth in 0...parentComponents.count {
            let baseComponents = Array(parentComponents.prefix(depth))

            for rule in rules(for: baseComponents) where rule.matches(pathComponents: pathComponents, isDirectory: isDirectory) {
                ignored = !rule.isNegated
            }
        }

        return ignored
    }

    nonisolated private mutating func rules(for baseComponents: [String]) -> [GitIgnoreRule] {
        let basePath = baseComponents.joined(separator: "/")

        if let rules = rulesByBasePath[basePath] {
            return rules
        }

        let rules = loadRules(for: baseComponents)
        rulesByBasePath[basePath] = rules

        return rules
    }

    nonisolated private func loadRules(for baseComponents: [String]) -> [GitIgnoreRule] {
        let url = baseComponents.reduce(rootURL) { partialURL, component in
            partialURL.appending(path: component, directoryHint: .isDirectory)
        }
        let gitIgnoreURL = url.appending(path: ".gitignore")

        guard let contents = try? String(contentsOf: gitIgnoreURL, encoding: .utf8) else {
            return []
        }

        return contents
            .components(separatedBy: .newlines)
            .compactMap { GitIgnoreRule(line: $0, baseComponents: baseComponents) }
    }

    nonisolated private func relativePathComponents(for url: URL) -> [String] {
        let targetPath = url.standardizedFileURL.path(percentEncoded: false)
        let rootPrefix = rootPath.hasSuffix("/") ? rootPath : "\(rootPath)/"

        guard targetPath.hasPrefix(rootPrefix) else { return [] }

        return targetPath
            .dropFirst(rootPrefix.count)
            .split(separator: "/")
            .map(String.init)
    }

    nonisolated private static func normalizedDirectoryPath(_ url: URL) -> String {
        var path = url.standardizedFileURL.path(percentEncoded: false)

        while path.count > 1 && path.hasSuffix("/") {
            path.removeLast()
        }

        return path
    }
}

private struct GitIgnoreRule {
    let isNegated: Bool
    let isAnchored: Bool
    let directoryOnly: Bool
    let baseComponents: [String]
    let patternComponents: [String]

    nonisolated init?(line: String, baseComponents: [String]) {
        var pattern = line.trimmingCharacters(in: .whitespaces)
        guard !pattern.isEmpty else { return nil }

        if pattern.hasPrefix("#") {
            return nil
        }

        if pattern.hasPrefix("\\#") || pattern.hasPrefix("\\!") {
            pattern.removeFirst()
        }

        let isNegated = pattern.hasPrefix("!")
        if isNegated {
            pattern.removeFirst()
            pattern = pattern.trimmingCharacters(in: .whitespaces)
        }

        guard !pattern.isEmpty else { return nil }

        let directoryOnly = pattern.hasSuffix("/")
        while pattern.count > 1 && pattern.hasSuffix("/") {
            pattern.removeLast()
        }

        let isAnchored = pattern.hasPrefix("/")
        if isAnchored {
            pattern.removeFirst()
        }

        guard !pattern.isEmpty else { return nil }

        self.isNegated = isNegated
        self.isAnchored = isAnchored
        self.directoryOnly = directoryOnly
        self.baseComponents = baseComponents
        self.patternComponents = pattern.split(separator: "/").map(String.init)
    }

    nonisolated func matches(pathComponents: [String], isDirectory: Bool) -> Bool {
        guard !directoryOnly || isDirectory,
              pathComponents.starts(with: baseComponents) else {
            return false
        }

        let localComponents = Array(pathComponents.dropFirst(baseComponents.count))
        guard !localComponents.isEmpty else { return false }

        if !isAnchored && patternComponents.count == 1 {
            return GlobMatcher.matchComponent(patternComponents[0], localComponents.last ?? "")
        }

        return GlobMatcher.matchPath(patternComponents, localComponents)
    }
}

enum GlobMatcher {
    nonisolated static func matchPath(_ patternComponents: [String], _ pathComponents: [String]) -> Bool {
        matchPath(patternComponents, pathComponents, patternIndex: 0, pathIndex: 0)
    }

    nonisolated private static func matchPath(
        _ patternComponents: [String],
        _ pathComponents: [String],
        patternIndex: Int,
        pathIndex: Int
    ) -> Bool {
        if patternIndex == patternComponents.count {
            return pathIndex == pathComponents.count
        }

        let pattern = patternComponents[patternIndex]

        if pattern == "**" {
            if matchPath(
                patternComponents,
                pathComponents,
                patternIndex: patternIndex + 1,
                pathIndex: pathIndex
            ) {
                return true
            }

            guard pathIndex < pathComponents.count else { return false }

            return matchPath(
                patternComponents,
                pathComponents,
                patternIndex: patternIndex,
                pathIndex: pathIndex + 1
            )
        }

        guard pathIndex < pathComponents.count,
              matchComponent(pattern, pathComponents[pathIndex]) else {
            return false
        }

        return matchPath(
            patternComponents,
            pathComponents,
            patternIndex: patternIndex + 1,
            pathIndex: pathIndex + 1
        )
    }

    nonisolated static func matchComponent(_ pattern: String, _ text: String) -> Bool {
        matchComponent(
            Array(pattern),
            Array(text),
            patternIndex: 0,
            textIndex: 0
        )
    }

    nonisolated private static func matchComponent(
        _ pattern: [Character],
        _ text: [Character],
        patternIndex: Int,
        textIndex: Int
    ) -> Bool {
        if patternIndex == pattern.count {
            return textIndex == text.count
        }

        switch pattern[patternIndex] {
        case "*":
            for nextTextIndex in textIndex...text.count {
                if matchComponent(
                    pattern,
                    text,
                    patternIndex: patternIndex + 1,
                    textIndex: nextTextIndex
                ) {
                    return true
                }
            }

            return false

        case "?":
            guard textIndex < text.count else { return false }

            return matchComponent(
                pattern,
                text,
                patternIndex: patternIndex + 1,
                textIndex: textIndex + 1
            )

        case "\\":
            let nextPatternIndex = patternIndex + 1
            guard nextPatternIndex < pattern.count,
                  textIndex < text.count,
                  pattern[nextPatternIndex] == text[textIndex] else {
                return false
            }

            return matchComponent(
                pattern,
                text,
                patternIndex: nextPatternIndex + 1,
                textIndex: textIndex + 1
            )

        default:
            guard textIndex < text.count,
                  pattern[patternIndex] == text[textIndex] else {
                return false
            }

            return matchComponent(
                pattern,
                text,
                patternIndex: patternIndex + 1,
                textIndex: textIndex + 1
            )
        }
    }
}
