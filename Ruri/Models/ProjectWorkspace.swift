//
//  ProjectWorkspace.swift
//  ruri
//

import Foundation

struct ProjectWorkspace: Identifiable {
    struct GitHubPullRequestLookupKey: Equatable {
        let worktreeRootURL: URL
        let branchName: String
        let baseBranchName: String?

        init(worktreeRootURL: URL, branchName: String, baseBranchName: String?) {
            self.worktreeRootURL = worktreeRootURL.standardizedFileURL
            self.branchName = branchName
            self.baseBranchName = baseBranchName
        }
    }

    enum DocumentRefresh: Sendable {
        case unchanged
        case deleted(OpenDocument.ID)
        case snapshot(OpenDocument.ID, ProjectFileSnapshot)
        case unreadable(OpenDocument.ID, ProjectFileSignature?)

        var documentID: OpenDocument.ID? {
            switch self {
            case .unchanged:
                nil
            case .deleted(let documentID),
                 .snapshot(let documentID, _),
                 .unreadable(let documentID, _):
                documentID
            }
        }
    }

    let id: ProjectWorkspaceSnapshot.ID
    let url: URL
    var displayNameOverride: String?
    var projectTree: ProjectTreeState
    var documentStore: EditorDocumentStore
    var tabStore: EditorTabStore
    var navigationHistory: EditorNavigationHistory
    var rootRequestID: UUID?
    var gitRefreshRequestID: UUID?
    var gitRepositoryStatus = GitRepositoryStatus.inactive
    var gitSnapshot: GitRepositorySnapshot?
    var githubPullRequestStatus: GitHubPullRequestStatus?
    var githubPullRequestLookupKey: GitHubPullRequestLookupKey?
    var githubPullRequestRefreshRequestID: UUID?
    var isRefreshingFileSystem = false
    var hasPendingFileSystemRefresh = false
    var pendingFileSystemChange: ProjectFileWatcher.Change?
    var pendingDocumentRefreshes: [OpenDocument.ID: DocumentRefresh] = [:]

    init(url: URL, displayNameOverride: String? = nil) {
        let standardizedURL = url.standardizedFileURL

        id = standardizedURL
        self.url = standardizedURL
        self.displayNameOverride = displayNameOverride
        projectTree = ProjectTreeState()
        projectTree.reset(to: standardizedURL)
        documentStore = EditorDocumentStore()
        tabStore = EditorTabStore()
        navigationHistory = EditorNavigationHistory()
    }

    var snapshot: ProjectWorkspaceSnapshot {
        ProjectWorkspaceSnapshot(id: id, url: url, displayNameOverride: displayNameOverride)
    }
}
