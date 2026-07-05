//
//  WorktreeMetadataStore.swift
//  ruri
//

import Foundation

nonisolated protocol WorktreeMetadataStoring: Sendable {
    func memo(forBranch branchName: String, metadataDirectoryURL: URL) async -> String
    func reviewBase(forBranch branchName: String, metadataDirectoryURL: URL) async -> GitReviewDiffBase?
    func saveMemo(
        _ memo: String,
        forBranch branchName: String,
        metadataDirectoryURL: URL,
        repositoryRootURL: URL?
    ) async throws
    func saveReviewBase(
        _ reviewBase: GitReviewDiffBase,
        forBranch branchName: String,
        metadataDirectoryURL: URL,
        repositoryRootURL: URL?
    ) async throws
    func viewedReviewFiles(forBranch branchName: String, metadataDirectoryURL: URL) async -> [String: String]
    func saveViewedReviewFile(
        path: String,
        fingerprint: String?,
        forBranch branchName: String,
        metadataDirectoryURL: URL,
        repositoryRootURL: URL?
    ) async throws
}

nonisolated struct WorktreeMetadataStore: WorktreeMetadataStoring, Sendable {
    private static let fileName = "worktree-metadata.json"
    private static let ruriExcludeLine = ".ruri/"
    // 同一JSONへのread-modify-writeを直列化し、save同士のlost updateを防ぐ。
    private static let writeSerializer = WorktreeMetadataWriteSerializer()

    nonisolated init() {}

    nonisolated func memo(forBranch branchName: String, metadataDirectoryURL: URL) async -> String {
        await Task.detached(priority: .utility) {
            let fileURL = metadataDirectoryURL
                .standardizedFileURL
                .appending(path: Self.fileName)
            let document = Self.loadDocument(from: fileURL)
            return document.branches[branchName]?.memo ?? ""
        }.value
    }

    nonisolated func reviewBase(forBranch branchName: String, metadataDirectoryURL: URL) async -> GitReviewDiffBase? {
        await Task.detached(priority: .utility) {
            let fileURL = metadataDirectoryURL
                .standardizedFileURL
                .appending(path: Self.fileName)
            let document = Self.loadDocument(from: fileURL)
            return document.branches[branchName]?.reviewBase?.gitReviewDiffBase
        }.value
    }

    nonisolated func saveMemo(
        _ memo: String,
        forBranch branchName: String,
        metadataDirectoryURL: URL,
        repositoryRootURL: URL?
    ) async throws {
        try await Self.writeSerializer.run {
            let metadataDirectoryURL = metadataDirectoryURL.standardizedFileURL
            let fileURL = metadataDirectoryURL.appending(path: Self.fileName)
            let fileManager = FileManager.default

            try fileManager.createDirectory(
                at: metadataDirectoryURL,
                withIntermediateDirectories: true
            )

            var document = Self.loadDocument(from: fileURL)
            document.version = 1
            var branch = document.branches[branchName] ?? WorktreeMetadataBranch()
            branch.memo = memo
            document.branches[branchName] = branch

            try Self.saveDocument(document, to: fileURL)

            if let repositoryRootURL,
               FileURLRewriter.isDescendantOrSame(metadataDirectoryURL, of: repositoryRootURL) {
                try Self.ensureRuriDirectoryIsLocallyExcluded(in: repositoryRootURL)
            }
        }
    }

    nonisolated func saveReviewBase(
        _ reviewBase: GitReviewDiffBase,
        forBranch branchName: String,
        metadataDirectoryURL: URL,
        repositoryRootURL: URL?
    ) async throws {
        try await Self.writeSerializer.run {
            let metadataDirectoryURL = metadataDirectoryURL.standardizedFileURL
            let fileURL = metadataDirectoryURL.appending(path: Self.fileName)
            let fileManager = FileManager.default

            try fileManager.createDirectory(
                at: metadataDirectoryURL,
                withIntermediateDirectories: true
            )

            var document = Self.loadDocument(from: fileURL)
            document.version = 1
            var branch = document.branches[branchName] ?? WorktreeMetadataBranch()
            branch.reviewBase = WorktreeMetadataReviewBase(reviewBase)
            document.branches[branchName] = branch

            try Self.saveDocument(document, to: fileURL)

            if let repositoryRootURL,
               FileURLRewriter.isDescendantOrSame(metadataDirectoryURL, of: repositoryRootURL) {
                try Self.ensureRuriDirectoryIsLocallyExcluded(in: repositoryRootURL)
            }
        }
    }

    nonisolated func viewedReviewFiles(
        forBranch branchName: String,
        metadataDirectoryURL: URL
    ) async -> [String: String] {
        await Task.detached(priority: .utility) {
            let fileURL = metadataDirectoryURL
                .standardizedFileURL
                .appending(path: Self.fileName)
            let document = Self.loadDocument(from: fileURL)
            return document.branches[branchName]?.viewedReviewFiles ?? [:]
        }.value
    }

    nonisolated func saveViewedReviewFile(
        path: String,
        fingerprint: String?,
        forBranch branchName: String,
        metadataDirectoryURL: URL,
        repositoryRootURL: URL?
    ) async throws {
        try await Self.writeSerializer.run {
            let metadataDirectoryURL = metadataDirectoryURL.standardizedFileURL
            let fileURL = metadataDirectoryURL.appending(path: Self.fileName)
            let fileManager = FileManager.default

            try fileManager.createDirectory(
                at: metadataDirectoryURL,
                withIntermediateDirectories: true
            )

            var document = Self.loadDocument(from: fileURL)
            document.version = 1
            var branch = document.branches[branchName] ?? WorktreeMetadataBranch()
            var viewedReviewFiles = branch.viewedReviewFiles ?? [:]
            viewedReviewFiles[path] = fingerprint
            branch.viewedReviewFiles = viewedReviewFiles.isEmpty ? nil : viewedReviewFiles
            document.branches[branchName] = branch

            try Self.saveDocument(document, to: fileURL)

            if let repositoryRootURL,
               FileURLRewriter.isDescendantOrSame(metadataDirectoryURL, of: repositoryRootURL) {
                try Self.ensureRuriDirectoryIsLocallyExcluded(in: repositoryRootURL)
            }
        }
    }

    private nonisolated static func loadDocument(from fileURL: URL) -> WorktreeMetadataDocument {
        guard let data = try? Data(contentsOf: fileURL),
              let document = try? JSONDecoder().decode(WorktreeMetadataDocument.self, from: data) else {
            return WorktreeMetadataDocument(version: 1, branches: [:])
        }

        return document
    }

    private nonisolated static func saveDocument(_ document: WorktreeMetadataDocument, to fileURL: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(document)
        try data.write(to: fileURL, options: .atomic)
    }

    private nonisolated static func ensureRuriDirectoryIsLocallyExcluded(in repositoryRootURL: URL) throws {
        let excludeURL = repositoryRootURL
            .standardizedFileURL
            .appending(path: ".git/info/exclude")
        let fileManager = FileManager.default
        let excludeDirectoryURL = excludeURL.deletingLastPathComponent()

        guard fileManager.fileExists(atPath: excludeDirectoryURL.path(percentEncoded: false)) else {
            return
        }

        let existingText = (try? String(contentsOf: excludeURL, encoding: .utf8)) ?? ""
        let lines = existingText
            .split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespaces) }

        guard !lines.contains(Self.ruriExcludeLine) else { return }

        var updatedText = existingText
        if !updatedText.isEmpty && !updatedText.hasSuffix("\n") {
            updatedText.append("\n")
        }
        updatedText.append("\(Self.ruriExcludeLine)\n")
        try updatedText.write(to: excludeURL, atomically: true, encoding: .utf8)
    }

}

private actor WorktreeMetadataWriteSerializer {
    func run<T: Sendable>(_ body: @Sendable () throws -> T) async rethrows -> T {
        try body()
    }
}

private struct WorktreeMetadataDocument: Codable {
    var version: Int
    var branches: [String: WorktreeMetadataBranch]
}

private struct WorktreeMetadataBranch: Codable {
    var memo: String = ""
    var reviewBase: WorktreeMetadataReviewBase?
    var viewedReviewFiles: [String: String]?
}

private struct WorktreeMetadataReviewBase: Codable {
    var kind: String
    var branchName: String?

    init(_ base: GitReviewDiffBase) {
        switch base {
        case .branch(let branchName):
            kind = "branch"
            self.branchName = branchName
        case .uncommitted:
            kind = "uncommitted"
            branchName = nil
        }
    }

    var gitReviewDiffBase: GitReviewDiffBase? {
        switch kind {
        case "branch":
            guard let branchName = branchName?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !branchName.isEmpty else {
                return nil
            }
            return .branch(branchName)
        case "uncommitted":
            return .uncommitted
        default:
            return nil
        }
    }
}
