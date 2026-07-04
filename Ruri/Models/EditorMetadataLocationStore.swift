//
//  EditorMetadataLocationStore.swift
//  ruri
//

import Foundation

struct EditorMetadataLocationStore {
    var fileExists: (URL) -> Bool = { url in
        FileManager.default.fileExists(atPath: url.path(percentEncoded: false))
    }

    func metadataDirectoryURL(
        snapshot: GitRepositorySnapshot,
        baseWorkspaceURL: URL?
    ) -> URL {
        if snapshot.isRuriStyleWorktree {
            return snapshot.worktreeRootURL
                .deletingLastPathComponent()
                .appending(path: ".ruri", directoryHint: .isDirectory)
                .standardizedFileURL
        }

        if let baseWorkspaceURL {
            return baseWorkspaceURL
                .deletingLastPathComponent()
                .appending(path: ".ruri", directoryHint: .isDirectory)
                .standardizedFileURL
        }

        return snapshot.worktreeRootURL
            .appending(path: ".ruri", directoryHint: .isDirectory)
            .standardizedFileURL
    }

    func fallbackMetadataDirectoryURL(for workspaceURL: URL) -> URL {
        let workspaceURL = workspaceURL.standardizedFileURL
        if workspaceURL.lastPathComponent == "ruri-base" {
            return workspaceURL
                .deletingLastPathComponent()
                .appending(path: ".ruri", directoryHint: .isDirectory)
                .standardizedFileURL
        }

        let siblingBaseURL = workspaceURL
            .deletingLastPathComponent()
            .appending(path: "ruri-base", directoryHint: .isDirectory)
        if fileExists(siblingBaseURL) {
            return workspaceURL
                .deletingLastPathComponent()
                .appending(path: ".ruri", directoryHint: .isDirectory)
                .standardizedFileURL
        }

        return workspaceURL
            .appending(path: ".ruri", directoryHint: .isDirectory)
            .standardizedFileURL
    }

    func metadataRepositoryRootURL(
        snapshot: GitRepositorySnapshot,
        hasBaseWorkspace: Bool
    ) -> URL? {
        if snapshot.isRuriStyleWorktree || hasBaseWorkspace {
            return nil
        }

        return snapshot.worktreeRootURL
    }
}
