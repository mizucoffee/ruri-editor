//
//  WorktreeInitialization.swift
//  ruri
//

import Foundation

nonisolated struct WorktreeInitializationDocument: Equatable, Sendable {
    var initializationCommand: String

    init(initializationCommand: String = "") {
        self.initializationCommand = initializationCommand
    }
}

nonisolated struct WorktreeInitializationMetadataLocation: Equatable, Sendable {
    let metadataDirectoryURL: URL
    let repositoryRootURL: URL?

    init(metadataDirectoryURL: URL, repositoryRootURL: URL?) {
        self.metadataDirectoryURL = metadataDirectoryURL.standardizedFileURL
        self.repositoryRootURL = repositoryRootURL?.standardizedFileURL
    }
}
