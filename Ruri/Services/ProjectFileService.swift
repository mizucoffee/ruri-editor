//
//  ProjectFileService.swift
//  ruri
//

import Foundation

enum ProjectFileError: LocalizedError, Equatable, Sendable {
    case unreadableUTF8File
    case invalidFileName
    case destinationAlreadyExists

    var errorDescription: String? {
        switch self {
        case .unreadableUTF8File:
            "UTF-8として読めないファイルです"
        case .invalidFileName:
            "使用できないファイル名です"
        case .destinationAlreadyExists:
            "同じ名前のファイルまたはフォルダが既に存在します"
        }
    }
}

nonisolated struct ProjectFileSignature: Equatable, Sendable {
    let modificationDate: Date?
    let fileSize: UInt64?
}

nonisolated struct ProjectFileSnapshot: Equatable, Sendable {
    let text: String
    let signature: ProjectFileSignature?
}

struct ProjectFileService: Sendable {
    nonisolated init() {}

    nonisolated func loadDirectory(at url: URL) async throws -> [FileNode] {
        try await loadDirectory(at: url, projectRootURL: nil)
    }

    nonisolated func loadDirectory(at url: URL, projectRootURL: URL?) async throws -> [FileNode] {
        try await Task.detached(priority: .userInitiated) {
            try Self.loadDirectorySnapshot(at: url, projectRootURL: projectRootURL)
        }.value
    }

    nonisolated func readUTF8File(at url: URL) async throws -> String {
        try await Task.detached(priority: .userInitiated) {
            let data = try Data(contentsOf: url)

            guard let string = String(data: data, encoding: .utf8) else {
                throw ProjectFileError.unreadableUTF8File
            }

            return string
        }.value
    }

    nonisolated func readUTF8FileSnapshot(at url: URL) async throws -> ProjectFileSnapshot {
        try await Task.detached(priority: .userInitiated) {
            let data = try Data(contentsOf: url)

            guard let string = String(data: data, encoding: .utf8) else {
                throw ProjectFileError.unreadableUTF8File
            }

            return ProjectFileSnapshot(
                text: string,
                signature: try Self.fileSignatureSnapshot(at: url)
            )
        }.value
    }

    @discardableResult
    nonisolated func writeUTF8File(_ text: String, to url: URL) async throws -> ProjectFileSignature? {
        try await Task.detached(priority: .userInitiated) {
            try text.write(to: url, atomically: true, encoding: .utf8)
            return try Self.fileSignatureSnapshot(at: url)
        }.value
    }

    nonisolated func renameItem(at url: URL, to proposedName: String) async throws -> URL {
        try await Task.detached(priority: .userInitiated) {
            try Self.renameItemSnapshot(at: url, to: proposedName)
        }.value
    }

    nonisolated func fileSignature(at url: URL) async throws -> ProjectFileSignature? {
        try await Task.detached(priority: .utility) {
            try Self.fileSignatureSnapshot(at: url)
        }.value
    }

    nonisolated func loadSearchEntries(at url: URL) async throws -> [ProjectFileSearchEntry] {
        try await Task.detached(priority: .userInitiated) {
            try Self.loadSearchEntriesSnapshot(at: url.standardizedFileURL)
        }.value
    }

    nonisolated private static func loadDirectorySnapshot(at url: URL, projectRootURL: URL?) throws -> [FileNode] {
        let fileManager = FileManager.default
        let keys: [URLResourceKey] = [
            .isDirectoryKey
        ]
        var gitIgnoreMatcher = projectRootURL.map { GitIgnoreMatcher(rootURL: $0) }

        let urls = try fileManager.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: keys,
            options: []
        )

        let nodes = try urls.compactMap { childURL -> FileNode? in
            let values = try childURL.resourceValues(forKeys: Set(keys))
            let name = childURL.lastPathComponent

            if name == ".git" || name == ".ruri" {
                return nil
            }

            let isDirectory = values.isDirectory == true
            let isIgnored = gitIgnoreMatcher?.isIgnoredBySelfOrAncestor(childURL, isDirectory: isDirectory) ?? false

            guard values.isDirectory == true else {
                return FileNode(
                    url: childURL,
                    name: name,
                    isDirectory: false,
                    children: nil,
                    isIgnored: isIgnored
                )
            }

            return FileNode(
                url: childURL,
                name: name,
                isDirectory: true,
                isIgnored: isIgnored
            )
        }

        return nodes.sorted { lhs, rhs in
            if lhs.isDirectory != rhs.isDirectory {
                return lhs.isDirectory && !rhs.isDirectory
            }

            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }

    nonisolated private static func renameItemSnapshot(at url: URL, to proposedName: String) throws -> URL {
        let fileManager = FileManager.default
        let newName = proposedName.trimmingCharacters(in: .whitespacesAndNewlines)

        guard isValidFileName(newName) else {
            throw ProjectFileError.invalidFileName
        }

        guard newName != url.lastPathComponent else {
            return url.standardizedFileURL
        }

        let destinationURL = url
            .deletingLastPathComponent()
            .appendingPathComponent(newName)

        if fileManager.fileExists(atPath: destinationURL.path(percentEncoded: false)) {
            throw ProjectFileError.destinationAlreadyExists
        }

        try fileManager.moveItem(at: url, to: destinationURL)
        return destinationURL.standardizedFileURL
    }

    nonisolated private static func isValidFileName(_ name: String) -> Bool {
        !name.isEmpty
            && name != "."
            && name != ".."
            && !name.contains("/")
            && !name.contains("\0")
    }

    nonisolated private static func fileSignatureSnapshot(at url: URL) throws -> ProjectFileSignature? {
        do {
            let attributes = try FileManager.default.attributesOfItem(
                atPath: url.path(percentEncoded: false)
            )

            guard attributes[.type] as? FileAttributeType == .typeRegular else {
                return nil
            }

            return ProjectFileSignature(
                modificationDate: attributes[.modificationDate] as? Date,
                fileSize: (attributes[.size] as? NSNumber)?.uint64Value
            )
        } catch let error as NSError where error.domain == NSCocoaErrorDomain
            && error.code == NSFileReadNoSuchFileError {
            return nil
        }
    }

    nonisolated private static func loadSearchEntriesSnapshot(at rootURL: URL) throws -> [ProjectFileSearchEntry] {
        let fileManager = FileManager.default
        let keys: [URLResourceKey] = [
            .isDirectoryKey,
            .isRegularFileKey
        ]

        _ = try rootURL.resourceValues(forKeys: [.isDirectoryKey])

        guard let enumerator = fileManager.enumerator(
            at: rootURL,
            includingPropertiesForKeys: keys,
            options: []
        ) else {
            return []
        }

        var entries: [ProjectFileSearchEntry] = []
        var gitIgnoreMatcher = GitIgnoreMatcher(rootURL: rootURL)

        for case let fileURL as URL in enumerator {
            let values = try fileURL.resourceValues(forKeys: Set(keys))
            let name = fileURL.lastPathComponent
            let isDirectory = values.isDirectory == true

            if name == ".git" || name == ".ruri" {
                if isDirectory {
                    enumerator.skipDescendants()
                }

                continue
            }

            if gitIgnoreMatcher.isIgnored(fileURL, isDirectory: isDirectory) {
                if isDirectory {
                    enumerator.skipDescendants()
                }

                continue
            }

            guard values.isRegularFile == true else { continue }

            entries.append(
                ProjectFileSearchEntry(
                    url: fileURL.standardizedFileURL,
                    fileName: name,
                    relativeParentPath: relativePath(
                        from: rootURL,
                        to: fileURL.deletingLastPathComponent().standardizedFileURL
                    )
                )
            )
        }

        return entries
    }

    nonisolated private static func relativePath(from rootURL: URL, to targetURL: URL) -> String {
        let rootPath = normalizedDirectoryPath(rootURL)
        let targetPath = normalizedDirectoryPath(targetURL)

        guard targetPath != rootPath else { return "" }

        let rootPrefix = rootPath.hasSuffix("/") ? rootPath : "\(rootPath)/"
        guard targetPath.hasPrefix(rootPrefix) else {
            return targetURL.lastPathComponent
        }

        return String(targetPath.dropFirst(rootPrefix.count))
    }

    nonisolated private static func normalizedDirectoryPath(_ url: URL) -> String {
        var path = url.standardizedFileURL.path(percentEncoded: false)

        while path.count > 1 && path.hasSuffix("/") {
            path.removeLast()
        }

        return path
    }
}
