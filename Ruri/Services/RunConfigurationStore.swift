//
//  RunConfigurationStore.swift
//  ruri
//

import Foundation

nonisolated protocol RunConfigurationStoring: Sendable {
    func load(metadataDirectoryURL: URL) async -> RunConfigurationDocument
    func save(
        _ document: RunConfigurationDocument,
        metadataDirectoryURL: URL,
        repositoryRootURL: URL?
    ) async throws
}

nonisolated struct RunConfigurationDocument: Equatable, Sendable {
    var configurations: [RunConfiguration]
    var activeConfigurationID: RunConfiguration.ID?

    init(configurations: [RunConfiguration] = [], activeConfigurationID: RunConfiguration.ID? = nil) {
        self.configurations = configurations
        self.activeConfigurationID = activeConfigurationID
        normalizeActiveConfiguration()
    }

    var activeConfiguration: RunConfiguration? {
        guard let activeConfigurationID else { return configurations.first }
        return configurations.first { $0.id == activeConfigurationID } ?? configurations.first
    }

    mutating func normalizeActiveConfiguration() {
        if let activeConfigurationID,
           configurations.contains(where: { $0.id == activeConfigurationID }) {
            return
        }

        activeConfigurationID = configurations.first?.id
    }
}

nonisolated struct RunConfigurationStore: RunConfigurationStoring, Sendable {
    private static let fileName = "run-configurations.json"
    private static let ruriExcludeLine = ".ruri/"

    nonisolated init() {}

    nonisolated func load(metadataDirectoryURL: URL) async -> RunConfigurationDocument {
        await Task.detached(priority: .utility) {
            let fileURL = metadataDirectoryURL
                .standardizedFileURL
                .appending(path: Self.fileName)
            return Self.loadDocument(from: fileURL).runConfigurationDocument
        }.value
    }

    nonisolated func save(
        _ document: RunConfigurationDocument,
        metadataDirectoryURL: URL,
        repositoryRootURL: URL?
    ) async throws {
        try await Task.detached(priority: .utility) {
            let metadataDirectoryURL = metadataDirectoryURL.standardizedFileURL
            let fileURL = metadataDirectoryURL.appending(path: Self.fileName)
            let fileManager = FileManager.default

            try fileManager.createDirectory(
                at: metadataDirectoryURL,
                withIntermediateDirectories: true
            )

            var normalizedDocument = document
            normalizedDocument.normalizeActiveConfiguration()
            try Self.saveDocument(
                RunConfigurationCodableDocument(normalizedDocument),
                to: fileURL
            )

            if let repositoryRootURL,
               FileURLRewriter.isDescendantOrSame(metadataDirectoryURL, of: repositoryRootURL) {
                try Self.ensureRuriDirectoryIsLocallyExcluded(in: repositoryRootURL)
            }
        }.value
    }

    private nonisolated static func loadDocument(from fileURL: URL) -> RunConfigurationCodableDocument {
        guard let data = try? Data(contentsOf: fileURL),
              let document = try? JSONDecoder().decode(RunConfigurationCodableDocument.self, from: data) else {
            return RunConfigurationCodableDocument(version: 1, activeConfigurationID: nil, configurations: [])
        }

        return document
    }

    private nonisolated static func saveDocument(
        _ document: RunConfigurationCodableDocument,
        to fileURL: URL
    ) throws {
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

nonisolated private struct RunConfigurationCodableDocument: Codable {
    var version: Int
    var activeConfigurationID: RunConfiguration.ID?
    var configurations: [RunConfiguration]

    init(version: Int, activeConfigurationID: RunConfiguration.ID?, configurations: [RunConfiguration]) {
        self.version = version
        self.activeConfigurationID = activeConfigurationID
        self.configurations = configurations
    }

    init(_ document: RunConfigurationDocument) {
        version = 1
        activeConfigurationID = document.activeConfigurationID
        configurations = document.configurations
    }

    var runConfigurationDocument: RunConfigurationDocument {
        RunConfigurationDocument(
            configurations: configurations,
            activeConfigurationID: activeConfigurationID
        )
    }
}
