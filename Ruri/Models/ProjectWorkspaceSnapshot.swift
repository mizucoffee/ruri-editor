//
//  ProjectWorkspaceSnapshot.swift
//  ruri
//

import Foundation

struct ProjectWorkspaceSnapshot: Identifiable, Equatable, Sendable {
    typealias ID = URL

    let id: ID
    let url: URL
    let displayNameOverride: String?

    init(id: ID, url: URL, displayNameOverride: String? = nil) {
        self.id = id
        self.url = url
        self.displayNameOverride = displayNameOverride
    }

    var displayName: String {
        displayNameOverride ?? url.lastPathComponent
    }

    var projectName: String {
        Self.projectName(for: url)
    }

    var displayPath: String {
        url.path(percentEncoded: false)
    }

    nonisolated static func projectName(for url: URL) -> String {
        let standardizedURL = url.standardizedFileURL
        if standardizedURL.lastPathComponent == "ruri-base" {
            let parentName = standardizedURL.deletingLastPathComponent().lastPathComponent
            if !parentName.isEmpty {
                return parentName
            }
        }

        return standardizedURL.lastPathComponent
    }
}
