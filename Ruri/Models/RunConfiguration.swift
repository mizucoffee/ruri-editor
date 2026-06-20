//
//  RunConfiguration.swift
//  ruri
//

import Foundation

nonisolated struct RunConfiguration: Identifiable, Equatable, Codable, Sendable {
    typealias ID = UUID

    let id: ID
    var name: String
    var command: String

    init(id: ID = UUID(), name: String, command: String) {
        self.id = id
        self.name = name
        self.command = command
    }
}

nonisolated struct RunConfigurationMetadataLocation: Equatable, Sendable {
    let metadataDirectoryURL: URL
    let repositoryRootURL: URL?

    init(metadataDirectoryURL: URL, repositoryRootURL: URL?) {
        self.metadataDirectoryURL = metadataDirectoryURL.standardizedFileURL
        self.repositoryRootURL = repositoryRootURL?.standardizedFileURL
    }
}
