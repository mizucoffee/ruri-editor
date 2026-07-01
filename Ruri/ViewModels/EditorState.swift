//
//  EditorState.swift
//  ruri
//

import Combine
import Foundation

struct ClosedEditorDocument: Equatable, Sendable {
    let workspaceID: ProjectWorkspaceSnapshot.ID
    let documentID: OpenDocument.ID
}

enum OpenProjectResult: Equatable, Sendable {
    case opened(ProjectWorkspaceSnapshot.ID)
    case activated(ProjectWorkspaceSnapshot.ID)
    case requiresNewWindow(URL)
}

struct ProjectFileChangeNotification: Equatable, Sendable {
    let sequence: Int
    let projectURL: URL
}

struct WorktreeDeletionTarget: Equatable, Sendable {
    let workspaceID: ProjectWorkspaceSnapshot.ID
    let displayName: String
    let displayPath: String
}

struct DeletedWorktreeResult: Equatable, Sendable {
    let workspaceID: ProjectWorkspaceSnapshot.ID
    let activatedWorkspaceID: ProjectWorkspaceSnapshot.ID?
}

enum EditorCodeNavigationResult: Equatable, Sendable {
    case navigated(ClosedEditorDocument?)
    case references([CodeUsageResult], title: String)
}

@MainActor
final class EditorState: ObservableObject {
    private enum OpenFileTabPolicy {
        case replaceUneditedSelectedTab
        case preserveSelectedTab
    }

    private enum NavigationHistoryDirection {
        case back
        case forward
    }

    private enum SaveTabResult {
        case saved(URL)
        case skipped
        case conflict
        case failed
    }

    @Published private(set) var projectWorkspaces: [ProjectWorkspaceSnapshot] = []
    @Published private(set) var activeProjectID: ProjectWorkspaceSnapshot.ID?
    @Published private(set) var projectName: String?
    @Published private(set) var projectURL: URL?
    @Published private(set) var fileTree: [FileNode] = []
    @Published private(set) var selectedFileTreeURL: URL?
    @Published private(set) var isFileTreeShowingChangedFilesOnly = false
    @Published private(set) var tabs: [EditorTabSnapshot] = []
    @Published private(set) var selectedTabID: EditorTab.ID?
    @Published private(set) var currentError: EditorError?
    @Published private(set) var fileChangeNotification: ProjectFileChangeNotification?
    @Published private(set) var saveConflictConfirmation: SaveConflictConfirmation?
    @Published private(set) var symbolIndexStatus = SymbolIndexStatusState.inactive
    @Published private(set) var gitRepositoryStatus = GitRepositoryStatus.inactive
    @Published private(set) var gitSnapshot: GitRepositorySnapshot?
    @Published private(set) var gitBranchesByProjectID: [ProjectWorkspaceSnapshot.ID: GitBranchState] = [:]
    @Published private(set) var githubPullRequestStatusesByProjectID: [ProjectWorkspaceSnapshot.ID: GitHubPullRequestStatus] = [:]
    @Published private(set) var githubPullRequestLoadingProjectIDs: Set<ProjectWorkspaceSnapshot.ID> = []
    @Published private(set) var worktreeMemosByProjectID: [ProjectWorkspaceSnapshot.ID: String] = [:]
    @Published private(set) var githubPullRequestStatus: GitHubPullRequestStatus?
    @Published private(set) var externalPullRequestWorktreeCreationRequest: ExternalPullRequestWorktreeCreationRequest?
    @Published private(set) var editorMode: EditorMode = .edit
    @Published private(set) var reviewDiffState = ReviewDiffState.unavailable
    @Published private(set) var reviewDiffBase: GitReviewDiffBase?
    @Published private(set) var reviewDiffRemoteBranches: [GitRemoteBranchInfo] = []
    @Published private(set) var isLoadingReviewDiffRemoteBranches = false
    @Published private(set) var reviewDiffRemoteBranchErrorMessage: String?
    @Published private(set) var reviewDiffHideWhitespace = false

    private struct GitHubPullRequestLookupKey: Equatable {
        let worktreeRootURL: URL
        let branchName: String
        let baseBranchName: String?

        init(worktreeRootURL: URL, branchName: String, baseBranchName: String?) {
            self.worktreeRootURL = worktreeRootURL.standardizedFileURL
            self.branchName = branchName
            self.baseBranchName = baseBranchName
        }
    }

    private struct ProjectWorkspace: Identifiable {
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

    private struct ReviewDiffRequestContext: Equatable {
        let baseWorkspaceID: ProjectWorkspaceSnapshot.ID
        let targetWorkspaceID: ProjectWorkspaceSnapshot.ID
        let targetWorkspaceURL: URL
        let base: GitReviewDiffBase
        let options: GitReviewDiffOptions

        func involves(_ workspaceID: ProjectWorkspaceSnapshot.ID) -> Bool {
            baseWorkspaceID == workspaceID || targetWorkspaceID == workspaceID
        }
    }

    private struct ReviewDiffNavigationSource {
        let fileURL: URL
        let text: String
        let sourceDocumentID: OpenDocument.ID?
    }

    private let fileService: ProjectFileService
    private let symbolNavigationService: SymbolNavigationService
    private let gitService: any GitServiceProtocol
    private let githubPullRequestService: any GitHubPullRequestServiceProtocol
    private let worktreeMetadataStore: any WorktreeMetadataStoring
    private let worktreeInitializationStore: any WorktreeInitializationStoring
    private let worktreeInitializationService: any WorktreeInitializationServiceProtocol
    private let isFileWatchingEnabled: Bool
    private let gitSnapshotRefreshDelayNanoseconds: UInt64
    private var workspaces: [ProjectWorkspace] = []
    private var fileChangeSequence = 0
    private var gitSnapshotRefreshTasks: [ProjectWorkspaceSnapshot.ID: Task<Void, Never>] = [:]
    private var gitSnapshotRefreshRequestIDs: [ProjectWorkspaceSnapshot.ID: UUID] = [:]
    private var githubPullRequestRefreshTasks: [ProjectWorkspaceSnapshot.ID: Task<Void, Never>] = [:]
    private var worktreeMemoLoadTasks: [ProjectWorkspaceSnapshot.ID: Task<Void, Never>] = [:]
    private var worktreeMemoSaveTasks: [ProjectWorkspaceSnapshot.ID: Task<Void, Never>] = [:]
    private var worktreeMemoKeysByProjectID: [ProjectWorkspaceSnapshot.ID: WorktreeMemoPersistenceKey] = [:]
    private var reviewBaseLoadTask: Task<Void, Never>?
    private var reviewBaseSaveTask: Task<Void, Never>?
    private var reviewBasePersistenceKey: ReviewBasePersistenceKey?
    private var reviewDiffRemoteBranchLoadTask: Task<Void, Never>?
    private var gitFileRefreshRequestIDs: [URL: UUID] = [:]
    private var reviewDiffRefreshTask: Task<Void, Never>?
    private var reviewDiffRefreshRequestID: UUID?
    private var currentReviewDiffContext: ReviewDiffRequestContext?
    private var hasStartedFileWatcher = false
    private lazy var fileWatcher = ProjectFileWatcher { [weak self] change in
        Task {
            await self?.handleExternalProjectChange(change)
        }
    }
    private var focusedEditorWorkspaceID: ProjectWorkspaceSnapshot.ID?
    private var focusedEditorTabID: EditorTab.ID?
    private var symbolReindexTasksByWorkspaceID: [ProjectWorkspaceSnapshot.ID: Task<Void, Never>] = [:]

    private struct WorktreeMemoPersistenceKey: Equatable, Sendable {
        let branchName: String
        let metadataDirectoryURL: URL
        let repositoryRootURL: URL?

        init(branchName: String, metadataDirectoryURL: URL, repositoryRootURL: URL?) {
            self.branchName = branchName
            self.metadataDirectoryURL = metadataDirectoryURL.standardizedFileURL
            self.repositoryRootURL = repositoryRootURL?.standardizedFileURL
        }
    }

    private struct ReviewBasePersistenceKey: Equatable, Sendable {
        let branchName: String
        let metadataDirectoryURL: URL
        let repositoryRootURL: URL?

        init(branchName: String, metadataDirectoryURL: URL, repositoryRootURL: URL?) {
            self.branchName = branchName
            self.metadataDirectoryURL = metadataDirectoryURL.standardizedFileURL
            self.repositoryRootURL = repositoryRootURL?.standardizedFileURL
        }
    }

    var mainTabs: [EditorTabSnapshot] {
        tabs
    }

    var selectedFileURL: URL? {
        selectedTab?.url
    }

    var selectedText: String {
        selectedTab?.text ?? ""
    }

    var hasUnsavedChanges: Bool {
        selectedTab?.hasUnsavedChanges ?? false
    }

    var canSave: Bool {
        selectedTab?.canSave ?? false
    }

    var commandSaveTargetTabID: EditorTab.ID? {
        selectedTabID
    }

    var canSaveCommandTarget: Bool {
        commandSaveTargetTabID.map { canSaveTab($0) } ?? false
    }

    var canCloseCommandTarget: Bool {
        selectedTabID != nil
    }

    var canFocusSelectedFileInTree: Bool {
        guard let index = activeWorkspaceIndex,
              let selectedTabID = workspaces[index].tabStore.selectedTabID,
              let selectedTab = workspaces[index].tabStore.tab(for: selectedTabID) else {
            return false
        }

        guard Self.isDescendantOrSame(selectedTab.documentID, of: workspaces[index].url) else {
            return false
        }

        if workspaces[index].projectTree.showsChangedFilesOnly {
            return workspaces[index].gitSnapshot?.change(for: selectedTab.documentID) != nil
        }

        return true
    }

    var canShowChangedFilesOnlyInFileTree: Bool {
        activeWorkspaceIndex.map { workspaces[$0].gitSnapshot != nil } ?? false
    }

    var canCreateWorktree: Bool {
        activeWorkspaceIndex.map { workspaces[$0].gitSnapshot != nil } ?? false
    }

    var hasOpenedProject: Bool {
        !projectWorkspaces.isEmpty
    }

    var activeWorktreeDeletionTarget: WorktreeDeletionTarget? {
        activeProjectID.flatMap { worktreeDeletionTarget(for: $0) }
    }

    var canDeleteWorktree: Bool {
        activeWorktreeDeletionTarget != nil
    }

    var canUseReviewMode: Bool {
        reviewDiffRequestContext != nil
    }

    var canNavigateBack: Bool {
        activeWorkspaceIndex.map { workspaces[$0].navigationHistory.canGoBack } ?? false
    }

    var canNavigateForward: Bool {
        activeWorkspaceIndex.map { workspaces[$0].navigationHistory.canGoForward } ?? false
    }

    var runConfigurationMetadataLocation: RunConfigurationMetadataLocation? {
        guard let index = activeWorkspaceIndex,
              let snapshot = workspaces[index].gitSnapshot else {
            guard let projectURL else { return nil }
            return RunConfigurationMetadataLocation(
                metadataDirectoryURL: projectURL.appending(path: ".ruri", directoryHint: .isDirectory),
                repositoryRootURL: projectURL
            )
        }

        let workspaceID = workspaces[index].id
        return RunConfigurationMetadataLocation(
            metadataDirectoryURL: metadataDirectoryURL(for: workspaceID, snapshot: snapshot),
            repositoryRootURL: metadataRepositoryRootURL(for: workspaceID, snapshot: snapshot)
        )
    }

    var worktreeInitializationMetadataLocation: WorktreeInitializationMetadataLocation? {
        guard let index = activeWorkspaceIndex,
              let snapshot = workspaces[index].gitSnapshot else {
            guard let projectURL else { return nil }
            return WorktreeInitializationMetadataLocation(
                metadataDirectoryURL: projectURL.appending(path: ".ruri", directoryHint: .isDirectory),
                repositoryRootURL: projectURL
            )
        }

        let workspaceID = workspaces[index].id
        return WorktreeInitializationMetadataLocation(
            metadataDirectoryURL: metadataDirectoryURL(for: workspaceID, snapshot: snapshot),
            repositoryRootURL: metadataRepositoryRootURL(for: workspaceID, snapshot: snapshot)
        )
    }

    private func worktreeInitializationMetadataLocation(
        for workspaceID: ProjectWorkspaceSnapshot.ID
    ) -> WorktreeInitializationMetadataLocation? {
        guard let index = workspaceIndex(for: workspaceID) else { return nil }

        guard let snapshot = workspaces[index].gitSnapshot else {
            return WorktreeInitializationMetadataLocation(
                metadataDirectoryURL: fallbackMetadataDirectoryURL(for: workspaces[index].url),
                repositoryRootURL: workspaces[index].url
            )
        }

        return WorktreeInitializationMetadataLocation(
            metadataDirectoryURL: metadataDirectoryURL(for: workspaceID, snapshot: snapshot),
            repositoryRootURL: metadataRepositoryRootURL(for: workspaceID, snapshot: snapshot)
        )
    }

    var agentStatusDirectoryURL: URL? {
        guard let index = activeWorkspaceIndex else { return nil }

        if let snapshot = workspaces[index].gitSnapshot {
            return metadataDirectoryURL(
                for: workspaces[index].id,
                snapshot: snapshot
            )
            .appending(path: "agent-status", directoryHint: .isDirectory)
            .standardizedFileURL
        }

        return fallbackMetadataDirectoryURL(for: workspaces[index].url)
            .appending(path: "agent-status", directoryHint: .isDirectory)
            .standardizedFileURL
    }

    var errorMessage: String? {
        currentError?.message
    }

    var saveConflictConfirmationMessage: String? {
        guard let saveConflictConfirmation else { return nil }
        return "\(saveConflictConfirmation.fileName) has changed outside ruri."
    }

    init(
        fileService: ProjectFileService = ProjectFileService(),
        symbolNavigationService: SymbolNavigationService? = nil,
        gitService: any GitServiceProtocol = GitService(),
        githubPullRequestService: any GitHubPullRequestServiceProtocol = GitHubPullRequestService(),
        worktreeMetadataStore: any WorktreeMetadataStoring = WorktreeMetadataStore(),
        worktreeInitializationStore: any WorktreeInitializationStoring = WorktreeInitializationStore(),
        worktreeInitializationService: any WorktreeInitializationServiceProtocol = WorktreeInitializationService(),
        isFileWatchingEnabled: Bool = true,
        gitSnapshotRefreshDelayNanoseconds: UInt64 = 1_500_000_000
    ) {
        self.fileService = fileService
        self.symbolNavigationService = symbolNavigationService ?? SymbolNavigationService()
        self.gitService = gitService
        self.githubPullRequestService = githubPullRequestService
        self.worktreeMetadataStore = worktreeMetadataStore
        self.worktreeInitializationStore = worktreeInitializationStore
        self.worktreeInitializationService = worktreeInitializationService
        self.isFileWatchingEnabled = isFileWatchingEnabled
        self.gitSnapshotRefreshDelayNanoseconds = gitSnapshotRefreshDelayNanoseconds
        self.symbolNavigationService.statusDidChange = { [weak self] status in
            self?.symbolIndexStatus = status
        }
    }

    deinit {
        MainActor.assumeIsolated {
            if isFileWatchingEnabled && hasStartedFileWatcher {
                fileWatcher.stopWatchingAll()
            }
            gitSnapshotRefreshTasks.values.forEach { $0.cancel() }
            githubPullRequestRefreshTasks.values.forEach { $0.cancel() }
            worktreeMemoLoadTasks.values.forEach { $0.cancel() }
            worktreeMemoSaveTasks.values.forEach { $0.cancel() }
            reviewBaseLoadTask?.cancel()
            reviewBaseSaveTask?.cancel()
            reviewDiffRemoteBranchLoadTask?.cancel()
            reviewDiffRefreshTask?.cancel()
            symbolReindexTasksByWorkspaceID.values.forEach { $0.cancel() }
        }
    }

    func setEditorMode(_ mode: EditorMode) {
        switch mode {
        case .edit:
            editorMode = .edit
            cancelReviewDiffRefresh()

        case .review:
            guard reviewDiffRequestContext != nil else {
                editorMode = .edit
                reviewDiffState = .unavailable
                cancelReviewDiffRefresh()
                return
            }

            editorMode = .review
            startReviewDiffRefresh(force: true)
        }
    }

    func refreshReviewDiff() {
        startReviewDiffRefresh(force: true)
    }

    func setReviewDiffHideWhitespace(_ hideWhitespace: Bool) {
        guard reviewDiffHideWhitespace != hideWhitespace else { return }

        reviewDiffHideWhitespace = hideWhitespace
        startReviewDiffRefresh(force: true)
    }

    func setReviewDiffBase(_ base: GitReviewDiffBase) {
        guard let key = reviewBasePersistenceKey(forActiveWorkspace: true) else { return }

        let normalizedBase = Self.normalizedReviewDiffBase(base)
        reviewBaseLoadTask?.cancel()
        reviewDiffBase = normalizedBase
        reviewBasePersistenceKey = key
        reviewBaseSaveTask?.cancel()
        reviewBaseSaveTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await self.worktreeMetadataStore.saveReviewBase(
                    normalizedBase,
                    forBranch: key.branchName,
                    metadataDirectoryURL: key.metadataDirectoryURL,
                    repositoryRootURL: key.repositoryRootURL
                )
            } catch {
                self.currentError = EditorError(message: error.localizedDescription)
            }
            self.reviewBaseSaveTask = nil
        }

        if editorMode == .review {
            startReviewDiffRefresh(force: true)
        }
    }

    func loadReviewDiffRemoteBranches(refresh: Bool = true) {
        guard !isLoadingReviewDiffRemoteBranches else { return }

        isLoadingReviewDiffRemoteBranches = true
        reviewDiffRemoteBranchErrorMessage = nil
        reviewDiffRemoteBranchLoadTask?.cancel()
        reviewDiffRemoteBranchLoadTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                self.reviewDiffRemoteBranches = try await self.remoteBranches(refresh: refresh)
            } catch {
                self.reviewDiffRemoteBranchErrorMessage = error.localizedDescription
            }
            self.isLoadingReviewDiffRemoteBranches = false
            self.reviewDiffRemoteBranchLoadTask = nil
        }
    }

    func refreshGitHubPullRequest() {
        guard let workspaceID = activeProjectID else { return }

        startGitHubPullRequestRefresh(for: workspaceID, force: true)
    }

    func openExternalGitHubPullRequestURL(_ url: URL) async {
        guard let reference = GitHubExternalURLParser.pullRequestReference(from: url) else {
            currentError = EditorError(message: "Unsupported Ruri URL.")
            return
        }

        await openExternalGitHubPullRequest(reference)
    }

    func canOpenExternalGitHubPullRequest(_ reference: GitHubPullRequestExternalReference) async -> Bool {
        await workspaceMatchingGitHubRepository(reference.repository) != nil
    }

    func openExternalGitHubPullRequest(_ reference: GitHubPullRequestExternalReference) async {
        guard let targetWorkspace = await workspaceMatchingGitHubRepository(reference.repository) else {
            currentError = EditorError(
                message: "Open \(reference.repository.owner)/\(reference.repository.name) in Ruri before opening this pull request."
            )
            return
        }

        do {
            let details = try await githubPullRequestService.pullRequestDetails(
                number: reference.number,
                openedRootURL: targetWorkspace.url
            )
            try await openExternalPullRequest(details, repository: reference.repository, sourceWorkspaceID: targetWorkspace.id)
        } catch {
            presentError(error)
        }
    }

    func cancelExternalPullRequestWorktreeCreation() {
        externalPullRequestWorktreeCreationRequest = nil
    }

    func confirmExternalPullRequestWorktreeCreation() async {
        guard let request = externalPullRequestWorktreeCreationRequest else { return }
        await confirmExternalPullRequestWorktreeCreation(request)
    }

    func confirmExternalPullRequestWorktreeCreation(
        _ request: ExternalPullRequestWorktreeCreationRequest?
    ) async {
        guard let request else { return }
        externalPullRequestWorktreeCreationRequest = nil

        do {
            let workspaceID = try await createWorktree(
                fromRemoteBranch: request.remoteBranchName,
                sourceWorkspaceID: request.sourceWorkspaceID
            )
            try await initializeCreatedWorktreeFromSavedCommand(
                workspaceID,
                sourceWorkspaceID: request.sourceWorkspaceID
            )
            activeProjectID = workspaceID
            clearError()
            publishAllState()
            setEditorMode(.review)
        } catch {
            presentError(error)
        }
    }

    private func workspaceMatchingGitHubRepository(
        _ repository: GitHubRepositoryIdentity
    ) async -> ProjectWorkspace? {
        for workspace in workspaces {
            let identities = await gitService.githubRepositoryIdentities(openedRootURL: workspace.url)
            if identities.contains(where: { $0.matches(repository) }) {
                return workspace
            }
        }

        return nil
    }

    private func openExternalPullRequest(
        _ details: GitHubPullRequestDetails,
        repository: GitHubRepositoryIdentity,
        sourceWorkspaceID: ProjectWorkspaceSnapshot.ID
    ) async throws {
        guard details.state.uppercased() == "OPEN" else {
            currentError = EditorError(message: "Pull request #\(details.number) is not open.")
            return
        }

        guard details.headRepository.matches(repository) else {
            currentError = EditorError(message: "Fork pull requests are not supported yet.")
            return
        }

        if let workspaceID = existingWorkspaceID(
            forBranch: details.headBranchName,
            sourceWorkspaceID: sourceWorkspaceID
        ) {
            activeProjectID = workspaceID
            clearError()
            publishAllState()
            setEditorMode(.review)
            return
        }

        externalPullRequestWorktreeCreationRequest = ExternalPullRequestWorktreeCreationRequest(
            pullRequestNumber: details.number,
            repository: repository,
            headBranchName: details.headBranchName,
            remoteBranchName: "origin/\(details.headBranchName)",
            sourceWorkspaceID: sourceWorkspaceID
        )
    }

    private func existingWorkspaceID(
        forBranch branchName: String,
        sourceWorkspaceID: ProjectWorkspaceSnapshot.ID
    ) -> ProjectWorkspaceSnapshot.ID? {
        guard let sourceIndex = workspaceIndex(for: sourceWorkspaceID),
              let sourceSnapshot = workspaces[sourceIndex].gitSnapshot else {
            return nil
        }

        return workspaces.first { workspace in
            guard let snapshot = workspace.gitSnapshot,
                  case .branch(let currentBranchName) = snapshot.branch,
                  currentBranchName == branchName else {
                return false
            }

            return FileURLRewriter.urlsMatch(
                snapshot.gitCommonDirectoryURL,
                sourceSnapshot.gitCommonDirectoryURL
            )
        }?.id
    }

    func refreshAllWorktreeOverview() async {
        let workspaceIDs = workspaces.map(\.id)
        for workspaceID in workspaceIDs {
            await refreshGitState(for: workspaceID)
            startGitHubPullRequestRefresh(for: workspaceID, force: true)
            refreshWorktreeMemo(for: workspaceID)
        }
    }

    func setWorktreeMemo(_ memo: String, for workspaceID: ProjectWorkspaceSnapshot.ID) {
        let workspaceID = normalizedProjectID(for: workspaceID)
        worktreeMemosByProjectID[workspaceID] = memo

        guard let key = worktreeMemoPersistenceKey(for: workspaceID) else { return }
        worktreeMemoKeysByProjectID[workspaceID] = key
        worktreeMemoSaveTasks[workspaceID]?.cancel()
        worktreeMemoSaveTasks[workspaceID] = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(nanoseconds: 400_000_000)
            } catch {
                return
            }

            guard let self,
                  self.worktreeMemoKeysByProjectID[workspaceID] == key,
                  self.worktreeMemosByProjectID[workspaceID] == memo else {
                return
            }

            do {
                try await self.worktreeMetadataStore.saveMemo(
                    memo,
                    forBranch: key.branchName,
                    metadataDirectoryURL: key.metadataDirectoryURL,
                    repositoryRootURL: key.repositoryRootURL
                )
            } catch {
                self.presentError(error)
            }

            self.worktreeMemoSaveTasks[workspaceID] = nil
        }
    }

    func worktreeDeletionTarget(for workspaceID: ProjectWorkspaceSnapshot.ID) -> WorktreeDeletionTarget? {
        let workspaceID = normalizedProjectID(for: workspaceID)
        guard let index = workspaceIndex(for: workspaceID),
              workspaces[index].gitSnapshot?.worktreeKind == .linked else {
            return nil
        }

        let snapshot = workspaces[index].snapshot
        return WorktreeDeletionTarget(
            workspaceID: snapshot.id,
            displayName: snapshot.displayName,
            displayPath: snapshot.displayPath
        )
    }

    @discardableResult
    func openProject(_ url: URL) async -> OpenProjectResult {
        let workspaceID = normalizedProjectID(for: url)

        if workspaces.contains(where: { $0.id == workspaceID }) {
            activeProjectID = workspaceID
            clearError()
            publishAllState()
            let status = await refreshGitState(for: workspaceID)
            if let snapshot = status?.snapshot {
                await openRelatedWorktreesIfNeeded(for: snapshot, activeWorkspaceID: workspaceID)
            }
            startSymbolIndexingForActiveWorkspace()
            return .activated(workspaceID)
        }

        guard workspaces.isEmpty else {
            return .requiresNewWindow(workspaceID)
        }

        var workspace = ProjectWorkspace(url: url)
        let requestID = UUID()
        workspace.rootRequestID = requestID
        workspace.gitRepositoryStatus = .checking
        workspaces.append(workspace)
        activeProjectID = workspace.id
        if isFileWatchingEnabled {
            fileWatcher.startWatching(workspace.url)
            hasStartedFileWatcher = true
        }
        publishAllState()

        do {
            let nodes = try await fileService.loadDirectory(
                at: workspace.url,
                projectRootURL: workspace.url
            )
            guard let index = workspaceIndex(for: workspace.id),
                  workspaces[index].rootRequestID == requestID else {
                return .opened(workspace.id)
            }

            workspaces[index].projectTree.replaceRootChildren(nodes)
            workspaces[index].rootRequestID = nil

            if activeProjectID == workspace.id {
                clearError()
            }
        } catch {
            guard let index = workspaceIndex(for: workspace.id),
                  workspaces[index].rootRequestID == requestID else {
                return .opened(workspace.id)
            }

            workspaces[index].projectTree.replaceRootChildren([])
            workspaces[index].rootRequestID = nil

            if activeProjectID == workspace.id {
                presentError(error)
            }
        }

        publishAllState()
        let status = await refreshGitState(for: workspace.id)
        if let snapshot = status?.snapshot {
            await openRelatedWorktreesIfNeeded(for: snapshot, activeWorkspaceID: workspace.id)
        }
        startSymbolIndexingForActiveWorkspace()
        return .opened(workspace.id)
    }

    func selectProject(_ id: ProjectWorkspaceSnapshot.ID) {
        guard workspaces.contains(where: { $0.id == id }) else { return }

        activeProjectID = id
        clearError()
        publishAllState()
        Task { [weak self] in
            await self?.refreshGitState(for: id)
            self?.startSymbolIndexingForActiveWorkspace()
        }
    }

    func toggleDirectory(_ url: URL) async {
        guard let workspaceID = activeProjectID,
              let index = workspaceIndex(for: workspaceID) else {
            return
        }

        let gitSnapshot = workspaces[index].gitSnapshot
        let result = workspaces[index].projectTree.toggleDirectory(at: url, gitSnapshot: gitSnapshot)
        await handleDirectoryMutationResult(
            result,
            workspaceID: workspaceID,
            expandedDirectoryURL: url
        )
    }

    func selectFileTreeNode(_ url: URL) {
        guard let index = activeWorkspaceIndex else { return }

        guard selectFileTreeNode(url, in: index) else { return }
        publishProjectState()
    }

    private func selectFileTreeNode(_ url: URL, in index: Int) -> Bool {
        let gitSnapshot = workspaces[index].gitSnapshot
        return workspaces[index].projectTree.selectNode(at: url, gitSnapshot: gitSnapshot)
    }

    func moveFileTreeSelection(by offset: Int) {
        guard let index = activeWorkspaceIndex else { return }

        let gitSnapshot = workspaces[index].gitSnapshot
        workspaces[index].projectTree.moveSelection(by: offset, gitSnapshot: gitSnapshot)
        publishProjectState()
    }

    func toggleFileTreeChangedFilesOnly() {
        guard let index = activeWorkspaceIndex,
              let gitSnapshot = workspaces[index].gitSnapshot else {
            return
        }

        let isEnabled = !workspaces[index].projectTree.showsChangedFilesOnly
        workspaces[index].projectTree.setShowsChangedFilesOnly(isEnabled, gitSnapshot: gitSnapshot)
        publishProjectState()
    }

    func expandSelectedFileTreeNode() async {
        guard let workspaceID = activeProjectID,
              let index = workspaceIndex(for: workspaceID) else {
            return
        }

        let gitSnapshot = workspaces[index].gitSnapshot
        let expandedDirectoryURL = workspaces[index].projectTree.selectedNode().flatMap { node in
            node.isDirectory && !node.isExpanded ? node.url : nil
        }
        let result = workspaces[index].projectTree.expandSelectedDirectoryOrSelectFirstChild(
            gitSnapshot: gitSnapshot
        )
        await handleDirectoryMutationResult(
            result,
            workspaceID: workspaceID,
            expandedDirectoryURL: expandedDirectoryURL
        )
    }

    func collapseSelectedFileTreeNodeOrSelectParent() {
        guard let index = activeWorkspaceIndex else { return }

        let gitSnapshot = workspaces[index].gitSnapshot
        _ = workspaces[index].projectTree.collapseSelectedDirectoryOrSelectParent(
            gitSnapshot: gitSnapshot
        )
        publishProjectState()
    }

    @discardableResult
    func focusSelectedFileInTree() async -> Bool {
        guard let workspaceID = activeProjectID,
              let index = workspaceIndex(for: workspaceID),
              let selectedTabID = workspaces[index].tabStore.selectedTabID,
              let selectedTab = workspaces[index].tabStore.tab(for: selectedTabID),
              Self.isDescendantOrSame(selectedTab.documentID, of: workspaces[index].url) else {
            return false
        }

        let targetURL = selectedTab.documentID.standardizedFileURL
        let directoryURLs = directoryAncestors(of: targetURL, within: workspaces[index].url)

        for directoryURL in directoryURLs {
            guard let currentIndex = workspaceIndex(for: workspaceID) else { return false }

            let gitSnapshot = workspaces[currentIndex].gitSnapshot
            let result = workspaces[currentIndex].projectTree.expandDirectoryIfNeeded(
                at: directoryURL,
                gitSnapshot: gitSnapshot
            )
            await handleDirectoryMutationResult(
                result,
                workspaceID: workspaceID,
                expandedDirectoryURL: directoryURL
            )

            guard let expandedIndex = workspaceIndex(for: workspaceID),
                  let directoryNode = workspaces[expandedIndex].projectTree.node(at: directoryURL),
                  directoryNode.isDirectory,
                  directoryNode.isExpanded,
                  !directoryNode.isLoadingChildren else {
                return false
            }
        }

        guard activeProjectID == workspaceID,
              let currentIndex = workspaceIndex(for: workspaceID),
              selectFileTreeNode(targetURL, in: currentIndex) else {
            return false
        }

        publishProjectState()
        return true
    }

    @discardableResult
    func activateSelectedFileTreeNode() async -> ClosedEditorDocument? {
        guard let workspaceID = activeProjectID,
              let index = workspaceIndex(for: workspaceID),
              let selectedNode = workspaces[index].projectTree.selectedNode() else {
            return nil
        }

        if selectedNode.isDirectory {
            let gitSnapshot = workspaces[index].gitSnapshot
            let result = workspaces[index].projectTree.toggleDirectory(
                at: selectedNode.url,
                gitSnapshot: gitSnapshot
            )
            await handleDirectoryMutationResult(
                result,
                workspaceID: workspaceID,
                expandedDirectoryURL: selectedNode.url
            )
            return nil
        }

        return await openFile(selectedNode.url)
    }

    func renameFileTreeNode(_ url: URL, to proposedName: String) async {
        guard let workspaceID = activeProjectID,
              let index = workspaceIndex(for: workspaceID),
              workspaces[index].projectTree.node(at: url) != nil else {
            return
        }

        do {
            let newURL = try await fileService.renameItem(at: url, to: proposedName)
            guard let currentIndex = workspaceIndex(for: workspaceID) else { return }

            workspaces[currentIndex].projectTree.renameNode(at: url, to: newURL)
            let documentIDMapping = workspaces[currentIndex].documentStore.rewriteDocumentURLs(
                replacing: url,
                with: newURL
            )
            workspaces[currentIndex].tabStore.rewriteDocumentIDs(documentIDMapping)
            workspaces[currentIndex].navigationHistory.rewriteURLs(replacing: url, with: newURL)

            if activeProjectID == workspaceID {
                clearError()
                publishProjectState()
                publishTabState()
            }
            await refreshGitState(for: workspaceID)
        } catch {
            if activeProjectID == workspaceID {
                presentError(error)
            }
        }
    }

    @discardableResult
    func createWorktree(named branchName: String) async throws -> ProjectWorkspaceSnapshot.ID {
        guard let sourceWorkspaceID = activeProjectID,
              let sourceIndex = workspaceIndex(for: sourceWorkspaceID),
              let sourceSnapshot = workspaces[sourceIndex].gitSnapshot else {
            throw GitWorktreeCreationError.notRepository(projectURL ?? URL(filePath: "/"))
        }

        let baseWorktreeURL = worktreeCreationBaseURL(from: sourceSnapshot)
        let trimmedBranchName = branchName.trimmingCharacters(in: .whitespacesAndNewlines)
        let worktree = try await gitService.createWorktree(
            branchName: trimmedBranchName,
            baseBranch: nil,
            openedRootURL: baseWorktreeURL
        )

        return await openCreatedWorktree(
            worktree,
            baseWorktreeURL: baseWorktreeURL,
            sourceWorkspaceID: sourceWorkspaceID
        )
    }

    func remoteBranches(refresh: Bool = true) async throws -> [GitRemoteBranchInfo] {
        guard let sourceWorkspaceID = activeProjectID,
              let sourceIndex = workspaceIndex(for: sourceWorkspaceID),
              let sourceSnapshot = workspaces[sourceIndex].gitSnapshot else {
            throw GitWorktreeCreationError.notRepository(projectURL ?? URL(filePath: "/"))
        }

        let baseWorktreeURL = worktreeCreationBaseURL(from: sourceSnapshot)
        return try await gitService.remoteBranches(
            openedRootURL: baseWorktreeURL,
            refresh: refresh
        )
    }

    @discardableResult
    func createWorktree(fromRemoteBranch remoteBranchFullName: String) async throws -> ProjectWorkspaceSnapshot.ID {
        guard let sourceWorkspaceID = activeProjectID,
              workspaceIndex(for: sourceWorkspaceID) != nil else {
            throw GitWorktreeCreationError.notRepository(projectURL ?? URL(filePath: "/"))
        }

        return try await createWorktree(
            fromRemoteBranch: remoteBranchFullName,
            sourceWorkspaceID: sourceWorkspaceID
        )
    }

    private func createWorktree(
        fromRemoteBranch remoteBranchFullName: String,
        sourceWorkspaceID: ProjectWorkspaceSnapshot.ID
    ) async throws -> ProjectWorkspaceSnapshot.ID {
        guard let sourceIndex = workspaceIndex(for: sourceWorkspaceID),
              let sourceSnapshot = workspaces[sourceIndex].gitSnapshot else {
            throw GitWorktreeCreationError.notRepository(sourceWorkspaceID.standardizedFileURL)
        }

        let baseWorktreeURL = worktreeCreationBaseURL(from: sourceSnapshot)
        let worktree = try await gitService.createWorktree(
            fromRemoteBranch: remoteBranchFullName,
            openedRootURL: baseWorktreeURL
        )

        return await openCreatedWorktree(
            worktree,
            baseWorktreeURL: baseWorktreeURL,
            sourceWorkspaceID: sourceWorkspaceID
        )
    }

    private func worktreeCreationBaseURL(from snapshot: GitRepositorySnapshot) -> URL {
        snapshot.worktrees.first { worktree in
            worktree.kind == .main
        }?.rootURL ?? snapshot.worktreeRootURL
    }

    private func openCreatedWorktree(
        _ worktree: GitWorktreeInfo,
        baseWorktreeURL: URL,
        sourceWorkspaceID: ProjectWorkspaceSnapshot.ID
    ) async -> ProjectWorkspaceSnapshot.ID {
        let workspaceID = normalizedProjectID(for: worktree.rootURL)

        if let baseWorkspaceID = workspaces.first(where: { workspace in
            FileURLRewriter.urlsMatch(workspace.url, baseWorktreeURL)
        })?.id, baseWorkspaceID != sourceWorkspaceID {
            await refreshGitState(for: baseWorkspaceID)
        }
        await refreshGitState(for: sourceWorkspaceID)
        await openRelatedWorktree(worktree, activeWorkspaceID: sourceWorkspaceID)

        activeProjectID = workspaceID
        clearError()
        publishAllState()
        await refreshGitState(for: workspaceID)
        startSymbolIndexingForActiveWorkspace()

        return workspaceID
    }

    func initializeCreatedWorktree(
        _ workspaceID: ProjectWorkspaceSnapshot.ID,
        command: String
    ) async throws {
        let workspaceID = normalizedProjectID(for: workspaceID)
        guard let index = workspaceIndex(for: workspaceID) else {
            throw GitWorktreeCreationError.notRepository(workspaceID)
        }

        let workspaceURL = workspaces[index].url
        try await worktreeInitializationService.run(command: command, in: workspaceURL)
        await refreshWorkspaceFileSystem(
            workspaceID,
            change: .workspaceRescan(rootURL: workspaceURL)
        )
    }

    private func initializeCreatedWorktreeFromSavedCommand(
        _ workspaceID: ProjectWorkspaceSnapshot.ID,
        sourceWorkspaceID: ProjectWorkspaceSnapshot.ID
    ) async throws {
        let command = await savedWorktreeInitializationCommand(for: sourceWorkspaceID)
        try await initializeCreatedWorktree(workspaceID, command: command)
    }

    private func savedWorktreeInitializationCommand(
        for sourceWorkspaceID: ProjectWorkspaceSnapshot.ID
    ) async -> String {
        guard let location = worktreeInitializationMetadataLocation(for: sourceWorkspaceID) else {
            return ""
        }

        let document = await worktreeInitializationStore.load(
            metadataDirectoryURL: location.metadataDirectoryURL
        )
        return document.initializationCommand
    }

    @discardableResult
    func deleteWorktree(_ workspaceID: ProjectWorkspaceSnapshot.ID) async throws -> DeletedWorktreeResult {
        let workspaceID = normalizedProjectID(for: workspaceID)
        guard let targetIndex = workspaceIndex(for: workspaceID) else {
            throw GitWorktreeDeletionError.worktreeNotFound(workspaceID)
        }

        guard let snapshot = workspaces[targetIndex].gitSnapshot else {
            throw GitWorktreeDeletionError.notRepository(workspaces[targetIndex].url)
        }

        guard snapshot.worktreeKind == .linked else {
            throw GitWorktreeDeletionError.cannotDeleteMainWorktree(workspaces[targetIndex].url)
        }

        let targetURL = workspaces[targetIndex].url
        let replacementWorkspaceID = replacementWorkspaceID(
            afterDeleting: workspaceID,
            snapshot: snapshot
        )
        try await gitService.deleteWorktree(openedRootURL: targetURL)

        removeWorkspaceState(for: workspaceID)
        if activeProjectID == workspaceID {
            activeProjectID = replacementWorkspaceID
        }

        clearError()
        publishAllState()

        for remainingWorkspaceID in workspaces.map(\.id) {
            await refreshGitState(for: remainingWorkspaceID)
        }
        startSymbolIndexingForActiveWorkspace()

        return DeletedWorktreeResult(
            workspaceID: workspaceID,
            activatedWorkspaceID: activeProjectID
        )
    }

    func pullWorktree(_ workspaceID: ProjectWorkspaceSnapshot.ID) async throws {
        let workspaceID = normalizedProjectID(for: workspaceID)
        guard let targetIndex = workspaceIndex(for: workspaceID) else {
            throw GitPullError.notRepository(workspaceID)
        }

        let targetURL = workspaces[targetIndex].url
        try await gitService.pull(openedRootURL: targetURL)

        clearError()
        await refreshWorkspaceFileSystem(
            workspaceID,
            change: .workspaceRescan(rootURL: targetURL)
        )
    }

    func switchGitBranch(named branchName: String) async throws {
        guard let index = activeWorkspaceIndex else {
            throw GitBranchSwitchError.notRepository(projectURL ?? URL(filePath: "/"))
        }

        let workspaceID = workspaces[index].id
        let workspaceURL = workspaces[index].url
        guard workspaces[index].gitSnapshot?.isRuriStyleWorktree == true else {
            throw GitBranchSwitchError.notRuriStyleWorktree(workspaceURL)
        }

        try await gitService.switchBranch(named: branchName, openedRootURL: workspaceURL)
        clearError()
        await refreshWorkspaceFileSystem(
            workspaceID,
            change: .workspaceRescan(rootURL: workspaceURL)
        )
    }

    private func replacementWorkspaceID(
        afterDeleting workspaceID: ProjectWorkspaceSnapshot.ID,
        snapshot: GitRepositorySnapshot
    ) -> ProjectWorkspaceSnapshot.ID? {
        if let mainWorktreeID = snapshot.worktrees.first(where: { worktree in
            worktree.kind == .main
        }).map({ normalizedProjectID(for: $0.rootURL) }),
           mainWorktreeID != workspaceID,
           workspaces.contains(where: { $0.id == mainWorktreeID }) {
            return mainWorktreeID
        }

        return workspaces.first { workspace in
            workspace.id != workspaceID
        }?.id
    }

    private func removeWorkspaceState(for workspaceID: ProjectWorkspaceSnapshot.ID) {
        guard let index = workspaceIndex(for: workspaceID) else { return }

        let workspaceURL = workspaces[index].url
        githubPullRequestRefreshTasks.removeValue(forKey: workspaceID)?.cancel()
        worktreeMemoLoadTasks.removeValue(forKey: workspaceID)?.cancel()
        worktreeMemoSaveTasks.removeValue(forKey: workspaceID)?.cancel()
        worktreeMemoKeysByProjectID.removeValue(forKey: workspaceID)
        worktreeMemosByProjectID.removeValue(forKey: workspaceID)
        workspaces.remove(at: index)

        if isFileWatchingEnabled {
            fileWatcher.stopWatching(workspaceURL)
        }
        cancelWorkspaceTasks(for: workspaceID, workspaceURL: workspaceURL)
        symbolNavigationService.stopIndexing(for: workspaceURL)
    }

    private func cancelWorkspaceTasks(
        for workspaceID: ProjectWorkspaceSnapshot.ID,
        workspaceURL: URL
    ) {
        gitSnapshotRefreshTasks.removeValue(forKey: workspaceID)?.cancel()
        gitSnapshotRefreshRequestIDs.removeValue(forKey: workspaceID)
        gitFileRefreshRequestIDs = gitFileRefreshRequestIDs.filter { requestURL, _ in
            !Self.isDescendantOrSame(requestURL, of: workspaceURL)
        }
    }

    private func handleDirectoryMutationResult(
        _ result: ProjectTreeState.ToggleResult,
        workspaceID: ProjectWorkspaceSnapshot.ID,
        expandedDirectoryURL: URL?
    ) async {
        var currentResult = result
        var currentExpandedDirectoryURL = expandedDirectoryURL
        var expandedPaths = Set<String>()

        while true {
            switch currentResult {
            case .updated:
                if activeProjectID == workspaceID {
                    publishProjectState()
                }

            case .notFound:
                if activeProjectID == workspaceID {
                    publishProjectState()
                }
                return

            case .needsChildren(let directoryURL):
                if activeProjectID == workspaceID {
                    publishProjectState()
                }

                do {
                    guard let loadingIndex = workspaceIndex(for: workspaceID) else { return }
                    let workspaceURL = workspaces[loadingIndex].url
                    let children = try await fileService.loadDirectory(
                        at: directoryURL,
                        projectRootURL: workspaceURL
                    )
                    guard let currentIndex = workspaceIndex(for: workspaceID) else { return }

                    workspaces[currentIndex].projectTree.finishLoadingChildren(children, for: directoryURL)
                    currentExpandedDirectoryURL = directoryURL

                    if activeProjectID == workspaceID {
                        clearError()
                    }
                } catch {
                    guard let currentIndex = workspaceIndex(for: workspaceID) else { return }

                    workspaces[currentIndex].projectTree.failLoadingChildren(for: directoryURL)

                    if activeProjectID == workspaceID {
                        presentError(error)
                        publishProjectState()
                    }

                    return
                }
            }

            guard let expandedDirectoryURL = currentExpandedDirectoryURL else {
                return
            }

            let currentExpandedPath = FileURLRewriter.normalizedPath(expandedDirectoryURL)
            guard expandedPaths.insert(currentExpandedPath).inserted else {
                if activeProjectID == workspaceID {
                    publishProjectState()
                }
                return
            }

            guard let currentIndex = workspaceIndex(for: workspaceID),
                  let nextDirectoryURL = workspaces[currentIndex].projectTree.chainedExpansionCandidate(
                    afterExpanding: expandedDirectoryURL
                  ) else {
                if activeProjectID == workspaceID {
                    publishProjectState()
                }
                return
            }

            let nextDirectoryPath = FileURLRewriter.normalizedPath(nextDirectoryURL)
            guard !expandedPaths.contains(nextDirectoryPath) else {
                if activeProjectID == workspaceID {
                    publishProjectState()
                }
                return
            }

            let gitSnapshot = workspaces[currentIndex].gitSnapshot
            currentResult = workspaces[currentIndex].projectTree.toggleDirectory(
                at: nextDirectoryURL,
                gitSnapshot: gitSnapshot
            )
            currentExpandedDirectoryURL = nextDirectoryURL
        }
    }

    @discardableResult
    func openFile(_ url: URL) async -> ClosedEditorDocument? {
        switchToEditModeForFileOpenIfNeeded()

        return await openFile(
            url,
            tabPolicy: .replaceUneditedSelectedTab,
            recordsNavigation: true
        )
    }

    @discardableResult
    func openFilePreservingSelectedTab(_ url: URL) async -> ClosedEditorDocument? {
        switchToEditModeForFileOpenIfNeeded()

        return await openFile(
            url,
            tabPolicy: .preserveSelectedTab,
            recordsNavigation: true
        )
    }

    @discardableResult
    private func openFile(
        _ url: URL,
        tabPolicy: OpenFileTabPolicy,
        recordsNavigation: Bool
    ) async -> ClosedEditorDocument? {
        guard let workspaceID = activeProjectID,
              let index = workspaceIndex(for: workspaceID) else {
            return nil
        }

        let origin = recordsNavigation ? currentNavigationPlace(in: index) : nil

        if let existingTab = tab(containing: url, in: index) {
            _ = workspaces[index].tabStore.openTab(
                for: existingTab.documentID,
                replaceSelectedMainTab: false
            )
            recordNavigationIfMoved(from: origin, in: workspaceID)
            clearError()
            publishTabState()
            return nil
        }

        var closedDocument: ClosedEditorDocument?

        do {
            let snapshot = try await fileService.readUTF8FileSnapshot(at: url)
            closedDocument = openLoadedFile(
                url: url,
                text: snapshot.text,
                signature: snapshot.signature,
                in: workspaceID,
                tabPolicy: tabPolicy
            )

            if activeProjectID == workspaceID {
                clearError()
            }
        } catch ProjectFileError.unreadableUTF8File {
            if activeProjectID == workspaceID {
                currentError = EditorError(message: ProjectFileError.unreadableUTF8File.localizedDescription)
            }
        } catch {
            if activeProjectID == workspaceID {
                presentError(error)
            }
        }

        if activeProjectID == workspaceID {
            recordNavigationIfMoved(from: origin, in: workspaceID)
            publishTabState()
        }

        return closedDocument
    }

    func selectTab(_ id: EditorTab.ID) {
        guard let workspaceID = activeProjectID,
              let index = workspaceIndex(for: workspaceID) else {
            return
        }

        let origin = currentNavigationPlace(in: index)
        workspaces[index].tabStore.selectTab(id)
        recordNavigationIfMoved(from: origin, in: workspaceID)
        publishTabState()
    }

    @discardableResult
    func closeTab(_ id: EditorTab.ID) -> ClosedEditorDocument? {
        guard let workspaceID = activeProjectID,
              let index = workspaceIndex(for: workspaceID),
              let result = workspaces[index].tabStore.closeTab(id) else {
            return nil
        }

        workspaces[index].documentStore.closeDocument(result.closedDocumentID)
        publishTabState()

        return ClosedEditorDocument(workspaceID: workspaceID, documentID: result.closedDocumentID)
    }

    @discardableResult
    func closeCommandTarget() -> ClosedEditorDocument? {
        guard let selectedTabID else { return nil }
        return closeTab(selectedTabID)
    }

    func updateSelectedText(_ newText: String) {
        guard let selectedTabID else { return }
        updateText(newText, in: selectedTabID)
    }

    func tab(for id: EditorTab.ID) -> EditorTabSnapshot? {
        tabs.first { $0.id == id }
    }

    func text(for id: EditorTab.ID) -> String {
        tab(for: id)?.text ?? ""
    }

    func editorSession(for id: EditorTab.ID) -> EditorDocumentSession? {
        guard let index = activeWorkspaceIndex,
              let tab = workspaces[index].tabStore.tab(for: id) else {
            return nil
        }

        return workspaces[index].documentStore.session(for: tab.documentID)
    }

    func updateText(_ newText: String, in id: EditorTab.ID) {
        guard let index = activeWorkspaceIndex,
              let tab = workspaces[index].tabStore.tab(for: id),
              let document = workspaces[index].documentStore.document(for: tab.documentID) else {
            return
        }

        guard document.text != newText else { return }

        workspaces[index].documentStore.updateText(newText, for: tab.documentID)
        publishTabState()
    }

    func updateSelection(_ selectedRange: NSRange, in id: EditorTab.ID) {
        guard let index = activeWorkspaceIndex,
              let tab = workspaces[index].tabStore.tab(for: id) else {
            return
        }

        workspaces[index].documentStore.updateSelection(selectedRange, for: tab.documentID)
    }

    func updateScrollOrigin(_ scrollOrigin: CGPoint, in id: EditorTab.ID) {
        guard let index = activeWorkspaceIndex,
              let tab = workspaces[index].tabStore.tab(for: id) else {
            return
        }

        workspaces[index].documentStore.updateScrollOrigin(scrollOrigin, for: tab.documentID)
    }

    func focusEditor(tabID: EditorTab.ID) {
        guard let index = activeWorkspaceIndex,
              workspaces[index].tabStore.tab(for: tabID) != nil else {
            return
        }

        let workspaceID = workspaces[index].id
        if focusedEditorWorkspaceID == workspaceID,
           focusedEditorTabID == tabID,
           workspaces[index].pendingDocumentRefreshes.isEmpty {
            return
        }

        focusedEditorWorkspaceID = workspaces[index].id
        focusedEditorTabID = tabID
        guard let tab = workspaces[index].tabStore.tab(for: tabID) else { return }
        if applyPendingDocumentRefresh(for: tab.documentID, in: index) {
            publishTabState()
        }
    }

    func blurEditor(tabID: EditorTab.ID) {
        guard focusedEditorWorkspaceID == activeProjectID,
              focusedEditorTabID == tabID else {
            return
        }

        focusedEditorWorkspaceID = nil
        focusedEditorTabID = nil
    }

    func revealRange(_ range: NSRange, in id: EditorTab.ID) {
        guard let index = activeWorkspaceIndex,
              requestRevealRange(range, in: id, workspaceIndex: index) else {
            return
        }

        publishTabState()
    }

    @discardableResult
    func navigateToFileRange(_ url: URL, range: NSRange) async -> ClosedEditorDocument? {
        guard let workspaceID = activeProjectID,
              let index = workspaceIndex(for: workspaceID) else {
            return nil
        }

        switchToEditModeForFileOpenIfNeeded()
        let origin = currentNavigationPlace(in: index)
        let closedDocument = await openFile(
            url,
            tabPolicy: .preserveSelectedTab,
            recordsNavigation: false
        )

        guard activeProjectID == workspaceID,
              let currentIndex = workspaceIndex(for: workspaceID),
              let selectedTabID = workspaces[currentIndex].tabStore.selectedTabID,
              let selectedTab = self.tab(for: selectedTabID),
              FileURLRewriter.urlsMatch(selectedTab.url, url) else {
            return closedDocument
        }

        let targetRange = clampedRange(range, toUTF16Length: selectedTab.text.utf16.count)
        if requestRevealRange(targetRange, in: selectedTabID, workspaceIndex: currentIndex) {
            recordNavigationIfMoved(from: origin, in: workspaceID)
            publishTabState()
        }

        return closedDocument
    }

    func lineContentRange(lineNumber: Int, in url: URL) async -> NSRange? {
        if let workspaceID = activeProjectID,
           let index = workspaceIndex(for: workspaceID),
           let tab = tab(containing: url, in: index),
           let document = workspaces[index].documentStore.document(for: tab.documentID) {
            return ReviewDiffCodeNavigationRequest.lineContentRange(
                lineNumber: lineNumber,
                in: document.text
            )
        }

        guard let text = try? await fileService.readUTF8File(at: url) else {
            return nil
        }

        return ReviewDiffCodeNavigationRequest.lineContentRange(
            lineNumber: lineNumber,
            in: text
        )
    }

    func navigateBackInHistory() async {
        await navigateInHistory(.back)
    }

    func navigateForwardInHistory() async {
        await navigateInHistory(.forward)
    }

    @discardableResult
    func goToImplementation(
        at utf16Offset: Int,
        in id: EditorTab.ID
    ) async -> ClosedEditorDocument? {
        guard let workspaceID = activeProjectID,
              let index = workspaceIndex(for: workspaceID),
              let sourceTab = workspaces[index].tabStore.tab(for: id),
              let document = workspaces[index].documentStore.document(for: sourceTab.documentID) else {
            return nil
        }

        let origin = currentNavigationPlace(in: index)
        let request = SymbolNavigationRequest(
            projectURL: workspaces[index].url,
            fileURL: document.url,
            text: document.text,
            utf16Offset: utf16Offset
        )

        guard let resolution = await symbolNavigationService.resolveImplementationOrReferences(
            request,
            openDocuments: symbolNavigationOpenDocuments(in: index)
        ) else {
            return nil
        }

        guard case .implementation(let target) = resolution else {
            return nil
        }

        let targetWasOpen = tab(containing: target.url, in: index) != nil
        if !targetWasOpen {
            workspaces[index].documentStore.markUserEdited(sourceTab.documentID)
        }

        let closedDocument = await openFile(
            target.url,
            tabPolicy: .preserveSelectedTab,
            recordsNavigation: false
        )
        guard activeProjectID == workspaceID,
              let currentIndex = workspaceIndex(for: workspaceID),
              let selectedTabID = workspaces[currentIndex].tabStore.selectedTabID,
              let selectedTab = self.tab(for: selectedTabID),
              FileURLRewriter.urlsMatch(selectedTab.url, target.url) else {
            return closedDocument
        }

        let targetRange = target.range.nsRange
        if requestRevealRange(targetRange, in: selectedTabID, workspaceIndex: currentIndex) {
            recordNavigationIfMoved(from: origin, in: workspaceID)
            publishTabState()
        }

        return closedDocument
    }

    func resolveImplementationOrReferences(
        at utf16Offset: Int,
        in id: EditorTab.ID
    ) async -> EditorCodeNavigationResult? {
        guard let workspaceID = activeProjectID,
              let index = workspaceIndex(for: workspaceID),
              let sourceTab = workspaces[index].tabStore.tab(for: id),
              let document = workspaces[index].documentStore.document(for: sourceTab.documentID) else {
            return nil
        }

        let origin = currentNavigationPlace(in: index)
        let request = SymbolNavigationRequest(
            projectURL: workspaces[index].url,
            fileURL: document.url,
            text: document.text,
            utf16Offset: utf16Offset
        )

        guard let resolution = await symbolNavigationService.resolveImplementationOrReferences(
            request,
            openDocuments: symbolNavigationOpenDocuments(in: index)
        ) else {
            return nil
        }

        switch resolution {
        case .implementation(let target):
            let closedDocument = await navigateToCodeTarget(
                target,
                sourceDocumentID: sourceTab.documentID,
                origin: origin,
                workspaceID: workspaceID,
                initialWorkspaceIndex: index
            )
            return .navigated(closedDocument)

        case .references(let targets):
            guard !targets.isEmpty else { return nil }
            if targets.count == 1,
               let target = targets.first {
                let closedDocument = await navigateToCodeTarget(
                    target,
                    sourceDocumentID: sourceTab.documentID,
                    origin: origin,
                    workspaceID: workspaceID,
                    initialWorkspaceIndex: index
                )
                return .navigated(closedDocument)
            }

            let results = await codeUsageResults(for: targets, workspaceID: workspaceID)
            guard activeProjectID == workspaceID else { return nil }
            guard !results.isEmpty else { return nil }
            return .references(results, title: codeNavigationResultsTitle(for: targets))
        }
    }

    func resolveReviewDiffImplementationOrReferences(
        _ reviewRequest: ReviewDiffCodeNavigationRequest
    ) async -> EditorCodeNavigationResult? {
        guard let workspaceID = activeProjectID,
              let index = workspaceIndex(for: workspaceID) else {
            return nil
        }

        let origin = currentNavigationPlace(in: index)
        guard let source = await reviewDiffNavigationSource(
            for: reviewRequest,
            workspaceID: workspaceID,
            workspaceIndex: index
        ) else {
            return nil
        }

        guard activeProjectID == workspaceID,
              let currentIndex = workspaceIndex(for: workspaceID),
              let utf16Offset = ReviewDiffCodeNavigationRequest.utf16Offset(
                lineNumber: reviewRequest.lineNumber,
                utf16Column: reviewRequest.utf16Column,
                in: source.text
              ) else {
            return nil
        }

        let request = SymbolNavigationRequest(
            projectURL: workspaces[currentIndex].url,
            fileURL: source.fileURL,
            text: source.text,
            utf16Offset: utf16Offset
        )

        guard let resolution = await symbolNavigationService.resolveImplementationOrReferences(
            request,
            openDocuments: symbolNavigationOpenDocuments(
                in: currentIndex,
                including: SymbolNavigationOpenDocument(url: source.fileURL, text: source.text)
            )
        ) else {
            return nil
        }

        switch resolution {
        case .implementation(let target):
            setEditorMode(.edit)
            let closedDocument = await navigateToCodeTarget(
                target,
                sourceDocumentID: source.sourceDocumentID,
                origin: origin,
                workspaceID: workspaceID,
                initialWorkspaceIndex: currentIndex
            )
            return .navigated(closedDocument)

        case .references(let targets):
            guard !targets.isEmpty else { return nil }
            if targets.count == 1,
               let target = targets.first {
                setEditorMode(.edit)
                let closedDocument = await navigateToCodeTarget(
                    target,
                    sourceDocumentID: source.sourceDocumentID,
                    origin: origin,
                    workspaceID: workspaceID,
                    initialWorkspaceIndex: currentIndex
                )
                return .navigated(closedDocument)
            }

            let results = await codeUsageResults(for: targets, workspaceID: workspaceID)
            guard activeProjectID == workspaceID else { return nil }
            guard !results.isEmpty else { return nil }
            setEditorMode(.edit)
            return .references(results, title: codeNavigationResultsTitle(for: targets))
        }
    }

    func reviewDiffImplementationHoverRange(
        _ reviewRequest: ReviewDiffCodeNavigationRequest
    ) async -> NSRange? {
        guard let workspaceID = activeProjectID,
              let index = workspaceIndex(for: workspaceID),
              let source = await reviewDiffNavigationSource(
                for: reviewRequest,
                workspaceID: workspaceID,
                workspaceIndex: index
              ) else {
            return nil
        }

        guard activeProjectID == workspaceID,
              let currentIndex = workspaceIndex(for: workspaceID),
              let utf16Offset = ReviewDiffCodeNavigationRequest.utf16Offset(
                lineNumber: reviewRequest.lineNumber,
                utf16Column: reviewRequest.utf16Column,
                in: source.text
              ) else {
            return nil
        }

        let request = SymbolNavigationRequest(
            projectURL: workspaces[currentIndex].url,
            fileURL: source.fileURL,
            text: source.text,
            utf16Offset: utf16Offset
        )

        guard let hoverTarget = await symbolNavigationService.resolveHoverTarget(
            request,
            openDocuments: symbolNavigationOpenDocuments(
                in: currentIndex,
                including: SymbolNavigationOpenDocument(url: source.fileURL, text: source.text)
            )
        ) else {
            return nil
        }

        return Self.lineLocalRange(
            for: hoverTarget.sourceRange.nsRange,
            lineNumber: reviewRequest.lineNumber,
            in: source.text
        )
    }

    func implementationHoverRange(
        at utf16Offset: Int,
        in id: EditorTab.ID
    ) async -> NSRange? {
        guard let workspaceID = activeProjectID,
              let index = workspaceIndex(for: workspaceID),
              let sourceTab = workspaces[index].tabStore.tab(for: id),
              let document = workspaces[index].documentStore.document(for: sourceTab.documentID) else {
            return nil
        }

        let request = SymbolNavigationRequest(
            projectURL: workspaces[index].url,
            fileURL: document.url,
            text: document.text,
            utf16Offset: utf16Offset
        )

        return await symbolNavigationService.resolveHoverTarget(
            request,
            openDocuments: symbolNavigationOpenDocuments(in: index)
        )?.sourceRange.nsRange
    }

    @discardableResult
    func navigateToCodeUsage(_ result: CodeUsageResult) async -> ClosedEditorDocument? {
        guard let workspaceID = activeProjectID,
              let index = workspaceIndex(for: workspaceID) else {
            return nil
        }

        switchToEditModeForFileOpenIfNeeded()
        let origin = currentNavigationPlace(in: index)
        let sourceDocumentID = workspaces[index].tabStore.selectedTabID
            .flatMap { workspaces[index].tabStore.tab(for: $0)?.documentID }

        return await navigateToCodeRange(
            result.matchRange.nsRange,
            in: result.url,
            sourceDocumentID: sourceDocumentID,
            origin: origin,
            workspaceID: workspaceID,
            initialWorkspaceIndex: index
        )
    }

    func saveSelectedFile() async {
        guard let selectedTabID else { return }
        await saveTab(selectedTabID)
    }

    func saveCommandTarget() async {
        guard let commandSaveTargetTabID else { return }
        await saveTab(commandSaveTargetTabID)
    }

    func saveTab(_ id: EditorTab.ID) async {
        guard let workspaceID = activeProjectID else { return }

        let result = await saveTab(
            id,
            in: workspaceID,
            allowingConflictOverwrite: false,
            presentsConflictConfirmation: true
        )
        if case .saved = result {
            await refreshGitState(for: workspaceID)
        }
    }

    func confirmSaveConflictOverwrite() async {
        guard let confirmation = saveConflictConfirmation else { return }

        saveConflictConfirmation = nil
        let result = await saveTab(
            confirmation.tabID,
            in: confirmation.workspaceID,
            allowingConflictOverwrite: true,
            presentsConflictConfirmation: true
        )
        if case .saved = result {
            await refreshGitState(for: confirmation.workspaceID)
        }
    }

    func cancelSaveConflict() {
        saveConflictConfirmation = nil
    }

    private func saveTab(
        _ id: EditorTab.ID,
        in workspaceID: ProjectWorkspaceSnapshot.ID?,
        allowingConflictOverwrite: Bool,
        presentsConflictConfirmation: Bool
    ) async -> SaveTabResult {
        guard let workspaceID,
              let index = workspaceIndex(for: workspaceID),
              let tab = workspaces[index].tabStore.tab(for: id) else {
            return .skipped
        }

        applyPendingDocumentRefresh(for: tab.documentID, in: index)
        if activeProjectID == workspaceID {
            publishTabState()
        }

        guard let currentIndex = workspaceIndex(for: workspaceID),
              let document = workspaces[currentIndex].documentStore.document(for: tab.documentID) else {
            return .skipped
        }

        guard document.externalStatus != .conflict || allowingConflictOverwrite else {
            if presentsConflictConfirmation {
                saveConflictConfirmation = SaveConflictConfirmation(
                    workspaceID: workspaceID,
                    tabID: id,
                    url: document.url
                )
            }
            return .conflict
        }

        let textToSave = document.text

        do {
            let signature = try await fileService.writeUTF8File(textToSave, to: document.url)
            guard let currentIndex = workspaceIndex(for: workspaceID) else { return .skipped }

            workspaces[currentIndex].documentStore.markSaved(
                document.id,
                savedText: textToSave,
                signature: signature
            )
            await symbolNavigationService.updateFile(
                projectURL: workspaces[currentIndex].url,
                fileURL: document.url,
                text: textToSave
            )

            if activeProjectID == workspaceID {
                clearError()
            }
            if activeProjectID == workspaceID {
                publishTabState()
            }
            return .saved(document.url)
        } catch {
            if activeProjectID == workspaceID {
                presentError(error)
            }
        }

        if activeProjectID == workspaceID {
            publishTabState()
        }
        return .failed
    }

    func canSaveTab(_ id: EditorTab.ID) -> Bool {
        tab(for: id)?.canSave ?? false
    }

    func handleExternalProjectChange(
        for rootURL: URL,
        changedPaths: Set<String> = []
    ) async {
        let change: ProjectFileWatcher.Change = changedPaths.isEmpty
            ? .workspaceRescan(rootURL: rootURL)
            : .fileChange(rootURL: rootURL, paths: changedPaths)
        await refreshExternalProjectContentChange(
            for: rootURL,
            change: change
        )
    }

    func handleExternalProjectChange(_ change: ProjectFileWatcher.Change) async {
        var refreshedWorkspaceIDs = Set<ProjectWorkspaceSnapshot.ID>()

        if !change.changedPaths.isEmpty || change.requiresWorkspaceRescan {
            let workspaceID = normalizedProjectID(for: change.rootURL)
            await refreshExternalProjectContentChange(
                for: change.rootURL,
                change: change
            )
            refreshedWorkspaceIDs.insert(workspaceID)
        }

        await refreshGitMetadataChanges(
            rootURL: change.rootURL,
            changedPaths: change.gitMetadataChangedPaths,
            excluding: refreshedWorkspaceIDs
        )
    }

    private func refreshExternalProjectContentChange(
        for rootURL: URL,
        change: ProjectFileWatcher.Change
    ) async {
        let workspaceID = normalizedProjectID(for: rootURL)
        guard let index = workspaceIndex(for: workspaceID) else { return }

        if workspaces[index].isRefreshingFileSystem {
            workspaces[index].hasPendingFileSystemRefresh = true
            workspaces[index].pendingFileSystemChange = mergedFileSystemChange(
                workspaces[index].pendingFileSystemChange,
                change
            )
            return
        }

        workspaces[index].pendingFileSystemChange = mergedFileSystemChange(
            workspaces[index].pendingFileSystemChange,
            change
        )
        workspaces[index].isRefreshingFileSystem = true

        while true {
            guard let currentIndex = workspaceIndex(for: workspaceID) else { return }

            let pendingChange = workspaces[currentIndex].pendingFileSystemChange
                ?? ProjectFileWatcher.Change(rootURL: rootURL.standardizedFileURL, dirtyFilePaths: [])
            workspaces[currentIndex].pendingFileSystemChange = nil
            workspaces[currentIndex].hasPendingFileSystemRefresh = false
            await refreshWorkspaceFileSystem(
                workspaceID,
                change: pendingChange
            )

            guard let refreshedIndex = workspaceIndex(for: workspaceID) else { return }

            if workspaces[refreshedIndex].hasPendingFileSystemRefresh {
                continue
            }

            workspaces[refreshedIndex].isRefreshingFileSystem = false
            break
        }
    }

    private func mergedFileSystemChange(
        _ existing: ProjectFileWatcher.Change?,
        _ change: ProjectFileWatcher.Change
    ) -> ProjectFileWatcher.Change {
        guard let existing else { return change }

        return ProjectFileWatcher.Change(
            rootURL: existing.rootURL,
            dirtyFilePaths: existing.dirtyFilePaths.union(change.dirtyFilePaths),
            dirtyDirectoryPaths: existing.dirtyDirectoryPaths.union(change.dirtyDirectoryPaths),
            dirtyRecursivePaths: existing.dirtyRecursivePaths.union(change.dirtyRecursivePaths),
            gitMetadataChangedPaths: existing.gitMetadataChangedPaths.union(change.gitMetadataChangedPaths),
            requiresWorkspaceRescan: existing.requiresWorkspaceRescan || change.requiresWorkspaceRescan,
            requiresFullGitRefresh: existing.requiresFullGitRefresh || change.requiresFullGitRefresh
        )
    }

    private func refreshGitMetadataChanges(
        rootURL: URL,
        changedPaths: Set<String>,
        excluding refreshedWorkspaceIDs: Set<ProjectWorkspaceSnapshot.ID>
    ) async {
        guard !changedPaths.isEmpty else { return }

        let fallbackWorkspaceID = normalizedProjectID(for: rootURL)
        let workspaceIDs = gitMetadataWorkspaceIDs(
            for: changedPaths,
            fallbackWorkspaceID: fallbackWorkspaceID
        )

        for workspaceID in workspaceIDs where !refreshedWorkspaceIDs.contains(workspaceID) {
            await refreshGitState(
                for: workspaceID,
                showsChecking: false,
                publishesUnchanged: false
            )
        }
    }

    func moveTab(_ movingID: EditorTab.ID, to targetID: EditorTab.ID) {
        guard let index = activeWorkspaceIndex else { return }

        workspaces[index].tabStore.moveTab(movingID, to: targetID)
        publishTabState()
    }

    func presentError(_ error: Error) {
        currentError = EditorError(error)
    }

    func clearError() {
        currentError = nil
    }

    private var activeWorkspaceIndex: Int? {
        guard let activeProjectID else { return nil }
        return workspaceIndex(for: activeProjectID)
    }

    private var selectedTab: EditorTabSnapshot? {
        guard let selectedTabID else { return nil }
        return tab(for: selectedTabID)
    }

    private func switchToEditModeForFileOpenIfNeeded() {
        guard editorMode == .review else { return }
        setEditorMode(.edit)
    }

    private func navigateInHistory(_ direction: NavigationHistoryDirection) async {
        guard let workspaceID = activeProjectID else { return }

        while true {
            guard let index = workspaceIndex(for: workspaceID) else { return }

            let currentPlace = currentNavigationPlace(in: index)
            let targetPlace: EditorNavigationPlace?

            switch direction {
            case .back:
                targetPlace = workspaces[index].navigationHistory.nextBackCandidate()
            case .forward:
                targetPlace = workspaces[index].navigationHistory.nextForwardCandidate()
            }

            guard let targetPlace else {
                publishTabState()
                return
            }

            if let currentPlace,
               targetPlace.hasSamePosition(as: currentPlace) {
                continue
            }

            guard await restoreNavigationPlace(targetPlace, in: workspaceID) else {
                continue
            }

            guard let updatedIndex = workspaceIndex(for: workspaceID) else { return }

            if let currentPlace {
                switch direction {
                case .back:
                    workspaces[updatedIndex].navigationHistory.recordCurrentPlaceForForward(currentPlace)
                case .forward:
                    workspaces[updatedIndex].navigationHistory.recordCurrentPlaceForBack(currentPlace)
                }
            }

            publishTabState()
            return
        }
    }

    private func restoreNavigationPlace(
        _ place: EditorNavigationPlace,
        in workspaceID: ProjectWorkspaceSnapshot.ID
    ) async -> Bool {
        guard let index = workspaceIndex(for: workspaceID) else { return false }

        if tab(containing: place.url, in: index) == nil {
            _ = await openFile(
                place.url,
                tabPolicy: .preserveSelectedTab,
                recordsNavigation: false
            )
        }

        guard activeProjectID == workspaceID,
              let currentIndex = workspaceIndex(for: workspaceID),
              let tab = tab(containing: place.url, in: currentIndex),
              let document = workspaces[currentIndex].documentStore.document(for: tab.documentID),
              let session = workspaces[currentIndex].documentStore.session(for: tab.documentID) else {
            return false
        }

        workspaces[currentIndex].tabStore.selectTab(tab.id)
        session.restoreNavigationPlace(
            selectedRange: clampedRange(place.selectedRange, toUTF16Length: document.text.utf16.count),
            scrollOrigin: place.scrollOrigin
        )
        clearError()
        return true
    }

    private func recordNavigationIfMoved(
        from origin: EditorNavigationPlace?,
        in workspaceID: ProjectWorkspaceSnapshot.ID
    ) {
        guard let origin,
              let index = workspaceIndex(for: workspaceID),
              let currentPlace = currentNavigationPlace(in: index),
              !origin.hasSamePosition(as: currentPlace) else {
            return
        }

        workspaces[index].navigationHistory.recordNavigation(from: origin)
    }

    private func currentNavigationPlace(in workspaceIndex: Int) -> EditorNavigationPlace? {
        guard let selectedTabID = workspaces[workspaceIndex].tabStore.selectedTabID,
              let tab = workspaces[workspaceIndex].tabStore.tab(for: selectedTabID),
              let session = workspaces[workspaceIndex].documentStore.session(for: tab.documentID) else {
            return nil
        }

        return EditorNavigationPlace(
            url: tab.documentID,
            selectedRange: session.selectedRange,
            scrollOrigin: session.scrollOrigin
        )
    }

    private func requestRevealRange(
        _ range: NSRange,
        in id: EditorTab.ID,
        workspaceIndex: Int
    ) -> Bool {
        guard let tab = workspaces[workspaceIndex].tabStore.tab(for: id),
              let document = workspaces[workspaceIndex].documentStore.document(for: tab.documentID),
              let session = workspaces[workspaceIndex].documentStore.session(for: tab.documentID) else {
            return false
        }

        session.requestSelectionReveal(clampedRange(range, toUTF16Length: document.text.utf16.count))
        return true
    }

    private func navigateToCodeTarget(
        _ target: SymbolNavigationTarget,
        sourceDocumentID: OpenDocument.ID?,
        origin: EditorNavigationPlace?,
        workspaceID: ProjectWorkspaceSnapshot.ID,
        initialWorkspaceIndex: Int
    ) async -> ClosedEditorDocument? {
        let targetWasOpen = tab(containing: target.url, in: initialWorkspaceIndex) != nil
        if !targetWasOpen,
           let sourceDocumentID {
            workspaces[initialWorkspaceIndex].documentStore.markUserEdited(sourceDocumentID)
        }

        let closedDocument = await openFile(
            target.url,
            tabPolicy: .preserveSelectedTab,
            recordsNavigation: false
        )
        guard activeProjectID == workspaceID,
              let currentIndex = workspaceIndex(for: workspaceID),
              let selectedTabID = workspaces[currentIndex].tabStore.selectedTabID,
              let selectedTab = self.tab(for: selectedTabID),
              FileURLRewriter.urlsMatch(selectedTab.url, target.url) else {
            return closedDocument
        }

        let targetRange = target.range.nsRange
        if requestRevealRange(targetRange, in: selectedTabID, workspaceIndex: currentIndex) {
            recordNavigationIfMoved(from: origin, in: workspaceID)
            publishTabState()
        }

        return closedDocument
    }

    private func navigateToCodeRange(
        _ range: NSRange,
        in url: URL,
        sourceDocumentID: OpenDocument.ID?,
        origin: EditorNavigationPlace?,
        workspaceID: ProjectWorkspaceSnapshot.ID,
        initialWorkspaceIndex: Int
    ) async -> ClosedEditorDocument? {
        let targetWasOpen = tab(containing: url, in: initialWorkspaceIndex) != nil
        if !targetWasOpen,
           let sourceDocumentID {
            workspaces[initialWorkspaceIndex].documentStore.markUserEdited(sourceDocumentID)
        }

        let closedDocument = await openFile(
            url,
            tabPolicy: .preserveSelectedTab,
            recordsNavigation: false
        )
        guard activeProjectID == workspaceID,
              let currentIndex = workspaceIndex(for: workspaceID),
              let selectedTabID = workspaces[currentIndex].tabStore.selectedTabID,
              let selectedTab = self.tab(for: selectedTabID),
              FileURLRewriter.urlsMatch(selectedTab.url, url) else {
            return closedDocument
        }

        let targetRange = clampedRange(range, toUTF16Length: selectedTab.text.utf16.count)
        if requestRevealRange(targetRange, in: selectedTabID, workspaceIndex: currentIndex) {
            recordNavigationIfMoved(from: origin, in: workspaceID)
            publishTabState()
        }

        return closedDocument
    }

    private func codeUsageResults(
        for targets: [SymbolNavigationTarget],
        workspaceID: ProjectWorkspaceSnapshot.ID
    ) async -> [CodeUsageResult] {
        guard let index = workspaceIndex(for: workspaceID) else { return [] }

        let projectURL = workspaces[index].url
        var seen = Set<CodeUsageResult.ID>()
        var results: [CodeUsageResult] = []

        for target in targets {
            guard let text = await textForCodeUsageTarget(target.url, workspaceID: workspaceID) else {
                continue
            }

            let result = CodeUsageResult.result(for: target, text: text, projectURL: projectURL)
            guard seen.insert(result.id).inserted else { continue }
            results.append(result)
        }

        return CodeUsageResult.sorted(results)
    }

    private func codeNavigationResultsTitle(for targets: [SymbolNavigationTarget]) -> String {
        targets.allSatisfy { $0.kind == .usage } ? "Usages" : "Locations"
    }

    private func textForCodeUsageTarget(
        _ url: URL,
        workspaceID: ProjectWorkspaceSnapshot.ID
    ) async -> String? {
        if let index = workspaceIndex(for: workspaceID),
           let document = workspaces[index].documentStore.documents.first(where: { document in
               FileURLRewriter.urlsMatch(document.url, url)
           }) {
            return document.text
        }

        return try? await fileService.readUTF8File(at: url)
    }

    private func reviewDiffNavigationSource(
        for reviewRequest: ReviewDiffCodeNavigationRequest,
        workspaceID: ProjectWorkspaceSnapshot.ID,
        workspaceIndex index: Int
    ) async -> ReviewDiffNavigationSource? {
        let fileURL = reviewRequest.fileURL.standardizedFileURL
        guard Self.isDescendantOrSame(fileURL, of: workspaces[index].url) else {
            return nil
        }

        switch reviewRequest.side {
        case .new:
            let openDocument = workspaces[index].documentStore.documents.first { document in
                FileURLRewriter.urlsMatch(document.url, fileURL)
            }

            if let openDocument {
                return ReviewDiffNavigationSource(
                    fileURL: fileURL,
                    text: openDocument.text,
                    sourceDocumentID: openDocument.id
                )
            }

            do {
                let text = try await fileService.readUTF8File(at: fileURL)
                guard activeProjectID == workspaceID else { return nil }
                return ReviewDiffNavigationSource(fileURL: fileURL, text: text, sourceDocumentID: nil)
            } catch {
                return nil
            }

        case .old:
            guard case .loaded(let snapshot) = reviewDiffState,
                  Self.isDescendantOrSame(fileURL, of: snapshot.targetWorktreeRootURL),
                  let relativePath = Self.relativePath(
                    for: fileURL,
                    rootURL: snapshot.targetWorktreeRootURL
                  ) else {
                return nil
            }

            do {
                let text = try await gitService.fileContents(
                    at: snapshot.baseRevision,
                    relativePath: relativePath,
                    openedRootURL: snapshot.targetWorktreeRootURL
                )
                guard activeProjectID == workspaceID else { return nil }
                return ReviewDiffNavigationSource(fileURL: fileURL, text: text, sourceDocumentID: nil)
            } catch {
                return nil
            }
        }
    }

    private static func lineLocalRange(
        for range: NSRange,
        lineNumber: Int,
        in text: String
    ) -> NSRange? {
        guard let lineRange = ReviewDiffCodeNavigationRequest.lineContentRange(
            lineNumber: lineNumber,
            in: text
        ) else {
            return nil
        }

        let lowerBound = max(range.location, lineRange.location)
        let upperBound = min(NSMaxRange(range), NSMaxRange(lineRange))
        guard lowerBound < upperBound else { return nil }
        return NSRange(location: lowerBound - lineRange.location, length: upperBound - lowerBound)
    }

    private static func relativePath(for url: URL, rootURL: URL) -> String? {
        let path = FileURLRewriter.normalizedPath(url)
        let rootPath = FileURLRewriter.normalizedPath(rootURL)

        if path == rootPath {
            return ""
        }

        let rootPathPrefix = rootPath.hasSuffix("/") ? rootPath : "\(rootPath)/"
        guard path.hasPrefix(rootPathPrefix) else {
            return nil
        }

        return String(path.dropFirst(rootPathPrefix.count))
    }

    private func symbolNavigationOpenDocuments(in workspaceIndex: Int) -> [SymbolNavigationOpenDocument] {
        workspaces[workspaceIndex].documentStore.documents.compactMap { document in
            guard document.url.pathExtension.lowercased() == "java" else {
                return nil
            }

            return SymbolNavigationOpenDocument(url: document.url, text: document.text)
        }
    }

    private func symbolNavigationOpenDocuments(
        in workspaceIndex: Int,
        including sourceDocument: SymbolNavigationOpenDocument
    ) -> [SymbolNavigationOpenDocument] {
        guard sourceDocument.url.pathExtension.lowercased() == "java" else {
            return symbolNavigationOpenDocuments(in: workspaceIndex)
        }

        var documents = symbolNavigationOpenDocuments(in: workspaceIndex)
        if let existingIndex = documents.firstIndex(where: { document in
            FileURLRewriter.urlsMatch(document.url, sourceDocument.url)
        }) {
            documents[existingIndex] = sourceDocument
        } else {
            documents.append(sourceDocument)
        }
        return documents
    }

    private func tab(containing url: URL, in workspaceIndex: Int) -> EditorTab? {
        if let exactMatch = workspaces[workspaceIndex].tabStore.tab(containing: url) {
            return exactMatch
        }

        return workspaces[workspaceIndex].tabStore.tabs.first { tab in
            FileURLRewriter.urlsMatch(tab.documentID, url)
        }
    }

    private func clampedRange(_ range: NSRange, toUTF16Length length: Int) -> NSRange {
        let rawLocation = range.location == NSNotFound ? length : range.location
        let location = min(max(0, rawLocation), length)
        let maxLength = max(0, length - location)
        return NSRange(location: location, length: min(max(0, range.length), maxLength))
    }

    private func openLoadedFile(
        url: URL,
        text: String,
        signature: ProjectFileSignature?,
        in workspaceID: ProjectWorkspaceSnapshot.ID,
        tabPolicy: OpenFileTabPolicy
    ) -> ClosedEditorDocument? {
        guard let index = workspaceIndex(for: workspaceID) else { return nil }

        let shouldReplaceSelectedTab: Bool
        switch tabPolicy {
        case .replaceUneditedSelectedTab:
            shouldReplaceSelectedTab = workspaces[index].tabStore.selectedMainTab().flatMap { selectedTab in
                workspaces[index].documentStore.document(for: selectedTab.documentID)
            }?.hasUserEdited == false
        case .preserveSelectedTab:
            shouldReplaceSelectedTab = false
        }

        let documentID = workspaces[index].documentStore.openDocument(
            url: url,
            text: text,
            signature: signature
        )
        let result = workspaces[index].tabStore.openTab(
            for: documentID,
            replaceSelectedMainTab: shouldReplaceSelectedTab
        )

        if let replacedDocumentID = result.replacedDocumentID {
            workspaces[index].documentStore.closeDocument(replacedDocumentID)
            return ClosedEditorDocument(workspaceID: workspaceID, documentID: replacedDocumentID)
        }

        return nil
    }

    private func refreshWorkspaceFileSystem(
        _ workspaceID: ProjectWorkspaceSnapshot.ID,
        change: ProjectFileWatcher.Change
    ) async {
        guard let index = workspaceIndex(for: workspaceID) else { return }

        let plan = WorkspaceFileSystemRefreshPlan.make(
            change: change,
            workspaceURL: workspaces[index].url,
            loadedDirectoryURLs: workspaces[index].projectTree.refreshDirectoryURLs()
        )
        let documents = workspaces[index].documentStore.documents
        let workspaceURL = workspaces[index].url
        let directorySnapshots = await loadDirectorySnapshots(
            for: plan.treeDirectoryURLs,
            projectRootURL: workspaceURL
        )
        let documentRefreshes = await loadDocumentRefreshes(
            for: documents,
            change: plan.documentRefreshChange
        )

        guard let currentIndex = workspaceIndex(for: workspaceID) else { return }

        if plan.hasTreeRefresh, directorySnapshots[workspaceURL.standardizedFileURL] != nil {
            workspaces[currentIndex].projectTree.refreshLoadedDirectories(directorySnapshots)
        }

        for refresh in documentRefreshes {
            applyOrDeferDocumentRefresh(refresh, in: currentIndex)
        }

        if activeProjectID == workspaceID {
            publishProjectState()
            publishTabState()
        }

        publishFileChangeNotification(for: workspaces[currentIndex].url)
        await refreshSymbolIndex(for: workspaceID, change: plan.symbolChange)

        if plan.requiresFullGitRefresh {
            await refreshGitState(for: workspaceID)
        } else {
            let didRefreshGitIncrementally = await refreshGitStateForChangedPaths(
                plan.gitChange.changedPaths,
                in: workspaceID
            )
            if !didRefreshGitIncrementally {
                await refreshGitState(for: workspaceID)
            }
        }
    }

    private enum DocumentRefresh: Sendable {
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

    private struct WorkspaceFileSystemRefreshPlan {
        let change: ProjectFileWatcher.Change
        let treeDirectoryURLs: [URL]
        let documentRefreshChange: ProjectFileWatcher.Change
        let symbolChange: ProjectFileWatcher.Change
        let gitChange: ProjectFileWatcher.Change
        let requiresFullGitRefresh: Bool

        var hasTreeRefresh: Bool {
            !treeDirectoryURLs.isEmpty
        }

        static func make(
            change: ProjectFileWatcher.Change,
            workspaceURL: URL,
            loadedDirectoryURLs: [URL]
        ) -> WorkspaceFileSystemRefreshPlan {
            let treeDirectoryURLs = treeRefreshURLs(
                from: loadedDirectoryURLs,
                workspaceURL: workspaceURL,
                change: change
            )
            let requiresFullGitRefresh = change.requiresFullGitRefresh
                || change.requiresWorkspaceRescan
                || !change.dirtyRecursivePaths.isEmpty
                || change.changedPaths.count > 64

            return WorkspaceFileSystemRefreshPlan(
                change: change,
                treeDirectoryURLs: treeDirectoryURLs,
                documentRefreshChange: change,
                symbolChange: change,
                gitChange: change,
                requiresFullGitRefresh: requiresFullGitRefresh
            )
        }

        private static func treeRefreshURLs(
            from loadedDirectoryURLs: [URL],
            workspaceURL: URL,
            change: ProjectFileWatcher.Change
        ) -> [URL] {
            guard change.requiresWorkspaceRescan
                    || !change.dirtyDirectoryPaths.isEmpty
                    || !change.dirtyRecursivePaths.isEmpty else {
                return []
            }

            let standardizedWorkspaceURL = workspaceURL.standardizedFileURL
            let rootPath = FileURLRewriter.normalizedPath(standardizedWorkspaceURL)

            if change.requiresWorkspaceRescan {
                return uniqueRefreshURLs([standardizedWorkspaceURL] + loadedDirectoryURLs)
            }

            let dirtyDirectoryPaths = normalizedChangedPaths(change.dirtyDirectoryPaths)
            let dirtyRecursivePaths = normalizedChangedPaths(change.dirtyRecursivePaths)
            let matchedLoadedDirectories = loadedDirectoryURLs.filter { directoryURL in
                let directoryPath = FileURLRewriter.normalizedPath(directoryURL)
                if directoryPath == rootPath { return false }

                if dirtyDirectoryPaths.contains(directoryPath) {
                    return true
                }

                return dirtyRecursivePaths.contains { dirtyPath in
                    if dirtyPath == directoryPath { return true }

                    let dirtyPrefix = dirtyPath.hasSuffix("/") ? dirtyPath : "\(dirtyPath)/"
                    let directoryPrefix = directoryPath.hasSuffix("/") ? directoryPath : "\(directoryPath)/"
                    return directoryPath.hasPrefix(dirtyPrefix) || dirtyPath.hasPrefix(directoryPrefix)
                }
            }

            return uniqueRefreshURLs([standardizedWorkspaceURL] + matchedLoadedDirectories)
        }

        private static func uniqueRefreshURLs(_ urls: [URL]) -> [URL] {
            var seenPaths = Set<String>()
            var result: [URL] = []

            for url in urls {
                let standardizedURL = url.standardizedFileURL
                let path = FileURLRewriter.normalizedPath(standardizedURL)
                guard !seenPaths.contains(path) else { continue }

                seenPaths.insert(path)
                result.append(standardizedURL)
            }

            return result
        }

        private static func normalizedChangedPaths(_ paths: Set<String>) -> Set<String> {
            Set(paths.map { FileURLRewriter.normalizedPath(URL(filePath: $0)) })
        }
    }

    private func loadDirectorySnapshots(
        for directoryURLs: [URL],
        projectRootURL: URL
    ) async -> [URL: [FileNode]] {
        guard !directoryURLs.isEmpty else { return [:] }

        let uniqueURLs = uniqueURLs(directoryURLs)
        let fileService = fileService

        return await withTaskGroup(of: (URL, [FileNode]?).self) { group in
            for url in uniqueURLs {
                group.addTask {
                    do {
                        return (
                            url,
                            try await fileService.loadDirectory(
                                at: url,
                                projectRootURL: projectRootURL
                            )
                        )
                    } catch {
                        if FileURLRewriter.urlsMatch(url, projectRootURL),
                           !Self.directoryExists(at: url) {
                            return (url, [])
                        }
                        return (url, nil)
                    }
                }
            }

            var snapshots: [URL: [FileNode]] = [:]

            for await (url, nodes) in group {
                if let nodes {
                    snapshots[url] = nodes
                }
            }

            return snapshots
        }
    }

    private func loadDocumentRefreshes(
        for documents: [OpenDocument],
        change: ProjectFileWatcher.Change
    ) async -> [DocumentRefresh] {
        guard !documents.isEmpty else { return [] }

        let fileService = fileService
        let normalizedDirtyFilePaths = normalizedChangedPaths(change.dirtyFilePaths)
        let normalizedDirtyRecursivePaths = normalizedChangedPaths(change.dirtyRecursivePaths)

        return await withTaskGroup(of: DocumentRefresh.self) { group in
            for document in documents {
                group.addTask {
                    let signature: ProjectFileSignature?

                    do {
                        signature = try await fileService.fileSignature(at: document.url)
                    } catch {
                        signature = nil
                    }

                    guard let signature else {
                        return .deleted(document.id)
                    }

                    let shouldCompareContents = change.requiresWorkspaceRescan
                        || Self.changedPaths(normalizedDirtyFilePaths, mayAffect: document.url)
                        || Self.changedPaths(normalizedDirtyRecursivePaths, mayAffect: document.url)
                    let signatureMatches = signature == document.lastKnownFileSignature

                    guard document.lastKnownFileSignature == nil
                            || !signatureMatches
                            || document.externalStatus == .deleted
                            || shouldCompareContents else {
                        return .unchanged
                    }

                    do {
                        let snapshot = try await fileService.readUTF8FileSnapshot(at: document.url)
                        if signatureMatches,
                           shouldCompareContents,
                           snapshot.text == document.lastSavedText {
                            return .unchanged
                        }
                        return .snapshot(document.id, snapshot)
                    } catch ProjectFileError.unreadableUTF8File {
                        return .unreadable(document.id, signature)
                    } catch {
                        return .unchanged
                    }
                }
            }

            var refreshes: [DocumentRefresh] = []
            for await refresh in group {
                refreshes.append(refresh)
            }
            return refreshes
        }
    }

    private func applyDocumentRefresh(_ refresh: DocumentRefresh, in workspaceIndex: Int) {
        switch refresh {
        case .unchanged:
            return

        case .deleted(let documentID):
            workspaces[workspaceIndex].documentStore.markExternalFileDeleted(documentID)

        case .snapshot(let documentID, let snapshot):
            workspaces[workspaceIndex].documentStore.applyExternalFileSnapshot(snapshot, to: documentID)

        case .unreadable(let documentID, let signature):
            workspaces[workspaceIndex].documentStore.markExternalFileUnreadable(
                documentID,
                signature: signature
            )
        }
    }

    private func applyOrDeferDocumentRefresh(_ refresh: DocumentRefresh, in workspaceIndex: Int) {
        guard let documentID = refresh.documentID else { return }

        if shouldDeferDocumentRefresh() {
            workspaces[workspaceIndex].pendingDocumentRefreshes[documentID] = refresh
        } else {
            applyDocumentRefresh(refresh, in: workspaceIndex)
            workspaces[workspaceIndex].pendingDocumentRefreshes[documentID] = nil
        }
    }

    @discardableResult
    private func applyPendingDocumentRefresh(for documentID: OpenDocument.ID, in workspaceIndex: Int) -> Bool {
        guard let refresh = workspaces[workspaceIndex].pendingDocumentRefreshes.removeValue(forKey: documentID) else {
            return false
        }

        applyDocumentRefresh(refresh, in: workspaceIndex)
        return true
    }

    private func shouldDeferDocumentRefresh() -> Bool {
        editorMode == .edit
    }

    private func refreshSymbolIndex(
        for workspaceID: ProjectWorkspaceSnapshot.ID,
        change: ProjectFileWatcher.Change
    ) async {
        guard let index = workspaceIndex(for: workspaceID) else { return }

        let shouldReindex = change.requiresWorkspaceRescan || change.dirtyRecursivePaths.count > 4
        if shouldReindex {
            scheduleSymbolReindex(for: workspaceID)
            return
        }

        let changedPaths = change.dirtyFilePaths
            .union(change.dirtyDirectoryPaths)
            .union(change.dirtyRecursivePaths)
        await symbolNavigationService.refreshChangedFiles(
            projectURL: workspaces[index].url,
            changedPaths: changedPaths,
            startIndexingIfMissing: activeProjectID == workspaceID
        )
    }

    private func scheduleSymbolReindex(for workspaceID: ProjectWorkspaceSnapshot.ID) {
        symbolReindexTasksByWorkspaceID[workspaceID]?.cancel()
        symbolReindexTasksByWorkspaceID[workspaceID] = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(nanoseconds: 1_500_000_000)
            } catch {
                return
            }

            guard let self,
                  let index = self.workspaceIndex(for: workspaceID) else {
                return
            }

            self.symbolReindexTasksByWorkspaceID[workspaceID] = nil
            self.symbolNavigationService.startIndexing(projectURL: self.workspaces[index].url)
        }
    }

    private func publishFileChangeNotification(for projectURL: URL) {
        fileChangeSequence += 1
        fileChangeNotification = ProjectFileChangeNotification(
            sequence: fileChangeSequence,
            projectURL: projectURL
        )
    }

    private func gitMetadataWorkspaceIDs(
        for changedPaths: Set<String>,
        fallbackWorkspaceID: ProjectWorkspaceSnapshot.ID
    ) -> [ProjectWorkspaceSnapshot.ID] {
        var targetWorkspaceIDs = Set<ProjectWorkspaceSnapshot.ID>()

        for changedPath in changedPaths {
            if let workspaceID = gitMetadataWorkspaceID(for: changedPath) {
                targetWorkspaceIDs.insert(workspaceID)
            } else {
                targetWorkspaceIDs.insert(fallbackWorkspaceID)
            }
        }

        return workspaces.map(\.id).filter { targetWorkspaceIDs.contains($0) }
    }

    private func gitMetadataWorkspaceID(for changedPath: String) -> ProjectWorkspaceSnapshot.ID? {
        let changedURL = URL(filePath: changedPath).standardizedFileURL
        return workspaces.compactMap { workspace -> (ProjectWorkspaceSnapshot.ID, Int)? in
            guard let gitDirectoryURL = workspace.gitSnapshot?.gitDirectoryURL,
                  Self.isDescendantOrSame(changedURL, of: gitDirectoryURL) else {
                return nil
            }

            return (
                workspace.id,
                FileURLRewriter.normalizedPath(gitDirectoryURL).count
            )
        }
        .max { lhs, rhs in lhs.1 < rhs.1 }?
        .0
    }

    private func uniqueURLs(_ urls: [URL]) -> [URL] {
        var seenPaths = Set<String>()
        var result: [URL] = []

        for url in urls {
            let standardizedURL = url.standardizedFileURL
            let path = FileURLRewriter.normalizedPath(standardizedURL)
            guard !seenPaths.contains(path) else { continue }

            seenPaths.insert(path)
            result.append(standardizedURL)
        }

        return result
    }

    private func normalizedChangedPaths(_ paths: Set<String>) -> Set<String> {
        Set(paths.map { path in
            var normalizedPath = NSString(string: path).standardizingPath

            while normalizedPath.count > 1 && normalizedPath.hasSuffix("/") {
                normalizedPath.removeLast()
            }

            return normalizedPath
        })
    }

    nonisolated private static func changedPaths(_ changedPaths: Set<String>, mayAffect url: URL) -> Bool {
        guard !changedPaths.isEmpty else { return false }

        let documentPath = FileURLRewriter.normalizedPath(url)

        return changedPaths.contains { changedPath in
            if changedPath == documentPath {
                return true
            }

            let changedPathPrefix = changedPath.hasSuffix("/") ? changedPath : "\(changedPath)/"
            return documentPath.hasPrefix(changedPathPrefix)
        }
    }

    nonisolated private static func isDescendantOrSame(_ url: URL, of rootURL: URL) -> Bool {
        let path = FileURLRewriter.normalizedPath(url)
        let rootPath = FileURLRewriter.normalizedPath(rootURL)

        if path == rootPath {
            return true
        }

        let rootPathPrefix = rootPath.hasSuffix("/") ? rootPath : "\(rootPath)/"
        return path.hasPrefix(rootPathPrefix)
    }

    nonisolated private static func directoryExists(at url: URL) -> Bool {
        let path = url.path(percentEncoded: false)
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: path),
              let fileType = attributes[.type] as? FileAttributeType else {
            return false
        }

        return fileType == .typeDirectory
    }

    private func directoryAncestors(of fileURL: URL, within rootURL: URL) -> [URL] {
        let rootURL = rootURL.standardizedFileURL
        var currentURL = fileURL.standardizedFileURL.deletingLastPathComponent().standardizedFileURL
        var ancestors: [URL] = []

        while !FileURLRewriter.urlsMatch(currentURL, rootURL) {
            guard Self.isDescendantOrSame(currentURL, of: rootURL) else {
                return []
            }

            ancestors.append(currentURL)

            let parentURL = currentURL.deletingLastPathComponent().standardizedFileURL
            guard !FileURLRewriter.urlsMatch(parentURL, currentURL) else {
                return []
            }

            currentURL = parentURL
        }

        return ancestors.reversed()
    }

    private func publishAllState() {
        projectWorkspaces = workspaces.map(\.snapshot)
        publishProjectState()
        publishTabState()
        publishGitState()
    }

    private func publishProjectState() {
        guard let index = activeWorkspaceIndex else {
            projectName = nil
            projectURL = nil
            fileTree = []
            selectedFileTreeURL = nil
            isFileTreeShowingChangedFilesOnly = false
            symbolIndexStatus = .inactive
            gitRepositoryStatus = .inactive
            gitSnapshot = nil
            githubPullRequestLoadingProjectIDs = []
            githubPullRequestStatus = nil
            return
        }

        projectName = projectName(for: workspaces[index])
        projectURL = workspaces[index].projectTree.projectURL
        let workspaceGitSnapshot = workspaces[index].gitSnapshot
        fileTree = workspaces[index].projectTree.displayFileTree(gitSnapshot: workspaceGitSnapshot)
        selectedFileTreeURL = workspaces[index].projectTree.selectedDisplayURL(
            gitSnapshot: workspaceGitSnapshot
        )
        isFileTreeShowingChangedFilesOnly = workspaceGitSnapshot != nil
            && workspaces[index].projectTree.showsChangedFilesOnly
    }

    private func projectName(for workspace: ProjectWorkspace) -> String {
        if let snapshot = workspace.gitSnapshot,
           let baseURL = ruriStyleBaseURL(in: snapshot) {
            return ProjectWorkspaceSnapshot.projectName(for: baseURL)
        }

        return workspace.snapshot.projectName
    }

    private func ruriStyleBaseURL(in snapshot: GitRepositorySnapshot) -> URL? {
        if snapshot.worktreeRootURL.standardizedFileURL.lastPathComponent == "ruri-base" {
            return snapshot.worktreeRootURL
        }

        return snapshot.worktrees.first { worktree in
            worktree.kind == .main
                && worktree.rootURL.standardizedFileURL.lastPathComponent == "ruri-base"
        }?.rootURL
    }

    private func publishTabState() {
        guard let index = activeWorkspaceIndex else {
            tabs = []
            selectedTabID = nil
            symbolIndexStatus = .inactive
            gitRepositoryStatus = .inactive
            gitSnapshot = nil
            githubPullRequestLoadingProjectIDs = []
            githubPullRequestStatus = nil
            return
        }

        tabs = workspaces[index].tabStore.tabs.compactMap { workspaces[index].documentStore.snapshot(for: $0) }
        selectedTabID = workspaces[index].tabStore.selectedTabID
        refreshSymbolIndexStatus()
    }

    private func publishGitState() {
        gitBranchesByProjectID = Dictionary(
            uniqueKeysWithValues: workspaces.compactMap { workspace in
                guard let branch = workspace.gitSnapshot?.branch else { return nil }
                return (workspace.id, branch)
            }
        )
        githubPullRequestStatusesByProjectID = Dictionary(
            uniqueKeysWithValues: workspaces.compactMap { workspace in
                guard let status = workspace.githubPullRequestStatus else { return nil }
                return (workspace.id, status)
            }
        )
        githubPullRequestLoadingProjectIDs = Set(workspaces.compactMap { workspace in
            isGitHubPullRequestLoading(for: workspace) ? workspace.id : nil
        })

        guard let index = activeWorkspaceIndex else {
            gitRepositoryStatus = .inactive
            gitSnapshot = nil
            githubPullRequestStatus = nil
            reconcileReviewModeAvailability()
            return
        }

        gitRepositoryStatus = workspaces[index].gitRepositoryStatus
        gitSnapshot = workspaces[index].gitSnapshot
        githubPullRequestStatus = workspaces[index].githubPullRequestStatus
        refreshReviewDiffBaseSelection()
        reconcileReviewModeAvailability()
    }

    private func isGitHubPullRequestLoading(for workspace: ProjectWorkspace) -> Bool {
        if workspace.githubPullRequestRefreshRequestID != nil {
            return true
        }

        guard let expectedKey = githubPullRequestLookupKey(for: workspace) else {
            return false
        }

        return workspace.githubPullRequestLookupKey != expectedKey
    }

    private var reviewDiffRequestContext: ReviewDiffRequestContext? {
        guard let activeIndex = activeWorkspaceIndex,
              let activeSnapshot = workspaces[activeIndex].gitSnapshot else {
            return nil
        }

        guard reviewBasePersistenceKey(forActiveWorkspace: true) != nil else {
            return nil
        }

        let selectedBase = reviewDiffBase ?? defaultReviewDiffBase(for: activeSnapshot)
        let options = GitReviewDiffOptions(hideWhitespace: reviewDiffHideWhitespace)

        if let baseWorkspace = workspaces.first(where: { workspace in
            workspace.gitSnapshot?.isRuriStyleWorktree == true
        }),
           let baseSnapshot = baseWorkspace.gitSnapshot,
           FileURLRewriter.urlsMatch(
                activeSnapshot.gitCommonDirectoryURL,
                baseSnapshot.gitCommonDirectoryURL
           ) {
            return ReviewDiffRequestContext(
                baseWorkspaceID: baseWorkspace.id,
                targetWorkspaceID: workspaces[activeIndex].id,
                targetWorkspaceURL: workspaces[activeIndex].url,
                base: selectedBase,
                options: options
            )
        }

        return ReviewDiffRequestContext(
            baseWorkspaceID: workspaces[activeIndex].id,
            targetWorkspaceID: workspaces[activeIndex].id,
            targetWorkspaceURL: workspaces[activeIndex].url,
            base: selectedBase,
            options: options
        )
    }

    private func refreshReviewDiffBaseSelection() {
        guard let key = reviewBasePersistenceKey(forActiveWorkspace: true),
              let activeIndex = activeWorkspaceIndex,
              let snapshot = workspaces[activeIndex].gitSnapshot else {
            reviewBaseLoadTask?.cancel()
            reviewBaseSaveTask?.cancel()
            reviewBasePersistenceKey = nil
            reviewDiffBase = nil
            reviewDiffRemoteBranches = []
            reviewDiffRemoteBranchErrorMessage = nil
            isLoadingReviewDiffRemoteBranches = false
            reviewDiffRemoteBranchLoadTask?.cancel()
            return
        }

        guard reviewBasePersistenceKey != key else {
            if reviewDiffBase == nil {
                reviewDiffBase = defaultReviewDiffBase(for: snapshot)
            }
            return
        }

        reviewBasePersistenceKey = key
        reviewDiffBase = defaultReviewDiffBase(for: snapshot)
        reviewDiffRemoteBranches = []
        reviewDiffRemoteBranchErrorMessage = nil
        isLoadingReviewDiffRemoteBranches = false
        reviewDiffRemoteBranchLoadTask?.cancel()
        reviewBaseLoadTask?.cancel()
        reviewBaseLoadTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let storedBase = await self.worktreeMetadataStore.reviewBase(
                forBranch: key.branchName,
                metadataDirectoryURL: key.metadataDirectoryURL
            )
            guard !Task.isCancelled,
                  self.reviewBasePersistenceKey == key else {
                return
            }

            if let storedBase {
                self.reviewDiffBase = Self.normalizedReviewDiffBase(storedBase)
                if self.editorMode == .review {
                    self.startReviewDiffRefresh(force: true)
                }
            }
            self.reviewBaseLoadTask = nil
        }
    }

    private func reviewBasePersistenceKey(forActiveWorkspace: Bool) -> ReviewBasePersistenceKey? {
        guard forActiveWorkspace,
              let workspaceID = activeProjectID,
              let index = workspaceIndex(for: workspaceID),
              let snapshot = workspaces[index].gitSnapshot else {
            return nil
        }

        let branchName: String
        switch snapshot.branch {
        case .branch(let name):
            branchName = name
        case .unborn, .detached:
            return nil
        }

        return ReviewBasePersistenceKey(
            branchName: branchName,
            metadataDirectoryURL: metadataDirectoryURL(for: workspaceID, snapshot: snapshot),
            repositoryRootURL: metadataRepositoryRootURL(for: workspaceID, snapshot: snapshot)
        )
    }

    private func defaultReviewDiffBase(for snapshot: GitRepositorySnapshot) -> GitReviewDiffBase {
        if let activeProjectID,
           let baseWorkspace = ruriStyleBaseWorkspace(matching: snapshot, excluding: activeProjectID),
           case .branch(let baseBranch) = baseWorkspace.gitSnapshot?.branch {
            return .branch(baseBranch)
        }

        if snapshot.isRuriStyleWorktree,
           case .branch(let baseBranch) = snapshot.branch {
            return .branch(baseBranch)
        }

        return .uncommitted
    }

    private static func normalizedReviewDiffBase(_ base: GitReviewDiffBase) -> GitReviewDiffBase {
        switch base {
        case .branch(let branchName):
            .branch(branchName.trimmingCharacters(in: .whitespacesAndNewlines))
        case .uncommitted:
            .uncommitted
        }
    }

    private func reconcileReviewModeAvailability() {
        guard reviewDiffRequestContext != nil else {
            if editorMode == .review {
                editorMode = .edit
            }
            reviewDiffState = .unavailable
            cancelReviewDiffRefresh()
            return
        }

        guard editorMode == .review else { return }
        startReviewDiffRefresh(force: false)
    }

    private func startReviewDiffRefresh(force: Bool) {
        guard editorMode == .review else { return }

        guard let context = reviewDiffRequestContext else {
            editorMode = .edit
            reviewDiffState = .unavailable
            cancelReviewDiffRefresh()
            return
        }

        if !force,
           currentReviewDiffContext == context,
           reviewDiffState != .unavailable {
            return
        }

        let requestID = UUID()
        let shouldShowLoading: Bool
        if currentReviewDiffContext == context,
           case .loaded = reviewDiffState {
            shouldShowLoading = false
        } else {
            shouldShowLoading = true
        }
        currentReviewDiffContext = context
        reviewDiffRefreshRequestID = requestID
        reviewDiffRefreshTask?.cancel()
        if shouldShowLoading {
            reviewDiffState = .loading
        }

        reviewDiffRefreshTask = Task { @MainActor [weak self] in
            await self?.performReviewDiffRefresh(
                context: context,
                requestID: requestID
            )
        }
    }

    private func performReviewDiffRefresh(
        context: ReviewDiffRequestContext,
        requestID: UUID
    ) async {
        do {
            let snapshot = try await gitService.reviewDiff(
                base: context.base,
                options: context.options,
                openedRootURL: context.targetWorkspaceURL
            )

            guard !Task.isCancelled,
                  reviewDiffRefreshRequestID == requestID,
                  currentReviewDiffContext == context else {
                return
            }

            reviewDiffState = .loaded(snapshot)
            reviewDiffRefreshTask = nil
            reviewDiffRefreshRequestID = nil
        } catch {
            guard !Task.isCancelled,
                  reviewDiffRefreshRequestID == requestID,
                  currentReviewDiffContext == context else {
                return
            }

            reviewDiffState = .failed(error.localizedDescription)
            reviewDiffRefreshTask = nil
            reviewDiffRefreshRequestID = nil
        }
    }

    private func cancelReviewDiffRefresh() {
        reviewDiffRefreshTask?.cancel()
        reviewDiffRefreshTask = nil
        reviewDiffRefreshRequestID = nil
        currentReviewDiffContext = nil
    }

    private func openRelatedWorktreesIfNeeded(
        for snapshot: GitRepositorySnapshot,
        activeWorkspaceID: ProjectWorkspaceSnapshot.ID
    ) async {
        guard snapshot.worktreeKind == .main,
              snapshot.hasOtherWorktrees else {
            return
        }

        let relatedWorktrees = snapshot.worktrees.filter { worktree in
            !FileURLRewriter.urlsMatch(worktree.rootURL, snapshot.worktreeRootURL)
        }
        guard !relatedWorktrees.isEmpty else { return }

        for worktree in relatedWorktrees {
            await openRelatedWorktree(worktree, activeWorkspaceID: activeWorkspaceID)
        }

        if activeProjectID == activeWorkspaceID {
            publishAllState()
        }
    }

    private func openRelatedWorktree(
        _ worktree: GitWorktreeInfo,
        activeWorkspaceID: ProjectWorkspaceSnapshot.ID
    ) async {
        let workspaceID = normalizedProjectID(for: worktree.rootURL)

        if let index = workspaceIndex(for: workspaceID) {
            workspaces[index].displayNameOverride = worktree.displayName
            projectWorkspaces = workspaces.map(\.snapshot)
            return
        }

        var workspace = ProjectWorkspace(
            url: worktree.rootURL,
            displayNameOverride: worktree.displayName
        )
        let requestID = UUID()
        workspace.rootRequestID = requestID
        workspace.gitRepositoryStatus = .checking
        workspaces.append(workspace)

        if isFileWatchingEnabled {
            fileWatcher.startWatching(workspace.url)
            hasStartedFileWatcher = true
        }

        if activeProjectID == activeWorkspaceID {
            projectWorkspaces = workspaces.map(\.snapshot)
        }

        do {
            let nodes = try await fileService.loadDirectory(
                at: workspace.url,
                projectRootURL: workspace.url
            )
            guard let index = workspaceIndex(for: workspace.id),
                  workspaces[index].rootRequestID == requestID else {
                return
            }

            workspaces[index].projectTree.replaceRootChildren(nodes)
            workspaces[index].rootRequestID = nil
        } catch {
            guard let index = workspaceIndex(for: workspace.id),
                  workspaces[index].rootRequestID == requestID else {
                return
            }

            workspaces[index].projectTree.replaceRootChildren([])
            workspaces[index].rootRequestID = nil
        }

        await refreshGitState(for: workspaceID)
    }

    private func scheduleGitStateRefresh(for workspaceID: ProjectWorkspaceSnapshot.ID) {
        let requestID = UUID()
        let delay = gitSnapshotRefreshDelayNanoseconds

        gitSnapshotRefreshTasks[workspaceID]?.cancel()
        gitSnapshotRefreshRequestIDs[workspaceID] = requestID
        gitSnapshotRefreshTasks[workspaceID] = Task { @MainActor [weak self] in
            if delay > 0 {
                do {
                    try await Task.sleep(nanoseconds: delay)
                } catch {
                    return
                }
            }

            await self?.performScheduledGitStateRefresh(
                for: workspaceID,
                requestID: requestID
            )
        }
    }

    private func performScheduledGitStateRefresh(
        for workspaceID: ProjectWorkspaceSnapshot.ID,
        requestID: UUID
    ) async {
        guard gitSnapshotRefreshRequestIDs[workspaceID] == requestID else { return }

        gitSnapshotRefreshTasks.removeValue(forKey: workspaceID)
        gitSnapshotRefreshRequestIDs.removeValue(forKey: workspaceID)
        await refreshGitState(for: workspaceID)
    }

    private func refreshGitFileState(
        for fileURL: URL,
        in workspaceID: ProjectWorkspaceSnapshot.ID
    ) async {
        guard let index = workspaceIndex(for: workspaceID) else { return }

        guard workspaces[index].gitSnapshot != nil else {
            await refreshGitState(for: workspaceID)
            return
        }

        let requestURL = fileURL.standardizedFileURL
        let requestID = UUID()
        let workspaceURL = workspaces[index].url
        gitFileRefreshRequestIDs[requestURL] = requestID

        let fileSnapshot = await gitService.fileSnapshot(
            for: requestURL,
            openedRootURL: workspaceURL
        )

        guard let currentIndex = workspaceIndex(for: workspaceID),
              gitFileRefreshRequestIDs[requestURL] == requestID else {
            return
        }

        gitFileRefreshRequestIDs.removeValue(forKey: requestURL)

        guard let fileSnapshot,
              let currentSnapshot = workspaces[currentIndex].gitSnapshot else {
            return
        }

        workspaces[currentIndex].gitSnapshot = currentSnapshot.updating(fileSnapshot: fileSnapshot)

        if activeProjectID == workspaceID {
            publishGitState()
        }

        if editorMode == .review,
           reviewDiffRequestContext?.involves(workspaceID) == true {
            startReviewDiffRefresh(force: true)
        }
    }

    private func refreshGitStateForChangedPaths(
        _ changedPaths: Set<String>,
        in workspaceID: ProjectWorkspaceSnapshot.ID
    ) async -> Bool {
        guard !changedPaths.isEmpty,
              let index = workspaceIndex(for: workspaceID),
              workspaces[index].gitSnapshot != nil else {
            return false
        }

        let fileURLs = changedPaths
            .map { URL(filePath: $0).standardizedFileURL }
            .filter { Self.isDescendantOrSame($0, of: workspaces[index].url) }
        guard !fileURLs.isEmpty else { return false }

        let workspaceURL = workspaces[index].url
        var fileSnapshots: [GitFileSnapshot] = []
        for fileURL in fileURLs {
            guard let fileSnapshot = await gitService.fileSnapshot(
                for: fileURL,
                openedRootURL: workspaceURL
            ) else {
                return false
            }
            fileSnapshots.append(fileSnapshot)
        }

        guard let currentIndex = workspaceIndex(for: workspaceID),
              let currentSnapshot = workspaces[currentIndex].gitSnapshot else {
            return false
        }

        workspaces[currentIndex].gitSnapshot = fileSnapshots.reduce(currentSnapshot) { snapshot, fileSnapshot in
            snapshot.updating(fileSnapshot: fileSnapshot)
        }

        if activeProjectID == workspaceID {
            publishGitState()
        }

        if editorMode == .review,
           reviewDiffRequestContext?.involves(workspaceID) == true {
            return await refreshReviewDiffForChangedFiles(fileURLs, in: workspaceID)
        }

        return true
    }

    private func refreshReviewDiffForChangedFiles(
        _ fileURLs: [URL],
        in workspaceID: ProjectWorkspaceSnapshot.ID
    ) async -> Bool {
        guard editorMode == .review,
              let context = reviewDiffRequestContext,
              context.targetWorkspaceID == workspaceID,
              case .loaded(let snapshot) = reviewDiffState,
              currentReviewDiffContext == context else {
            return false
        }

        let requestID = UUID()
        reviewDiffRefreshRequestID = requestID
        reviewDiffRefreshTask?.cancel()

        do {
            let update = try await gitService.reviewDiffUpdate(
                base: context.base,
                options: context.options,
                fileURLs: fileURLs,
                openedRootURL: context.targetWorkspaceURL
            )

            guard !Task.isCancelled,
                  reviewDiffRefreshRequestID == requestID,
                  currentReviewDiffContext == context else {
                return true
            }

            guard let updatedSnapshot = snapshot.applying(update) else {
                reviewDiffRefreshTask = nil
                reviewDiffRefreshRequestID = nil
                startReviewDiffRefresh(force: true)
                return true
            }

            reviewDiffState = .loaded(updatedSnapshot)
            reviewDiffRefreshTask = nil
            reviewDiffRefreshRequestID = nil
            return true
        } catch {
            guard reviewDiffRefreshRequestID == requestID,
                  currentReviewDiffContext == context else {
                return true
            }

            reviewDiffRefreshTask = nil
            reviewDiffRefreshRequestID = nil
            startReviewDiffRefresh(force: true)
            return true
        }
    }

    @discardableResult
    private func refreshGitState(
        for workspaceID: ProjectWorkspaceSnapshot.ID,
        showsChecking: Bool = true,
        publishesUnchanged: Bool = true
    ) async -> GitRepositoryStatus? {
        guard let index = workspaceIndex(for: workspaceID) else { return nil }

        let requestID = UUID()
        let workspaceURL = workspaces[index].url
        let previousStatus = workspaces[index].gitRepositoryStatus
        workspaces[index].gitRefreshRequestID = requestID

        if showsChecking {
            workspaces[index].gitRepositoryStatus = .checking
        }

        if showsChecking && activeProjectID == workspaceID {
            publishGitState()
        }

        let status = await gitService.repositoryStatus(for: workspaceURL)

        guard let currentIndex = workspaceIndex(for: workspaceID),
              workspaces[currentIndex].gitRefreshRequestID == requestID else {
            return nil
        }

        let currentURL = workspaces[currentIndex].url
        let didChange = previousStatus != status
        workspaces[currentIndex].gitRepositoryStatus = status
        workspaces[currentIndex].gitSnapshot = status.snapshot
        workspaces[currentIndex].displayNameOverride = status.snapshot.flatMap { snapshot in
            displayName(for: currentURL, in: snapshot)
        }
        workspaces[currentIndex].gitRefreshRequestID = nil

        if publishesUnchanged || didChange {
            projectWorkspaces = workspaces.map(\.snapshot)
            if activeProjectID == workspaceID {
                publishProjectState()
            }
            publishGitState()
        }

        if (publishesUnchanged || didChange),
           editorMode == .review,
           reviewDiffRequestContext?.involves(workspaceID) == true {
            startReviewDiffRefresh(force: true)
        }

        refreshWorktreeMemo(for: workspaceID)
        startGitHubPullRequestRefresh(for: workspaceID, force: false)

        return status
    }

    private func startGitHubPullRequestRefresh(
        for workspaceID: ProjectWorkspaceSnapshot.ID,
        force: Bool
    ) {
        guard let index = workspaceIndex(for: workspaceID) else { return }

        guard let lookupKey = githubPullRequestLookupKey(for: workspaces[index]) else {
            clearGitHubPullRequest(for: workspaceID)
            return
        }
        if !force,
           workspaces[index].githubPullRequestLookupKey == lookupKey {
            return
        }

        let requestID = UUID()
        workspaces[index].githubPullRequestLookupKey = lookupKey
        workspaces[index].githubPullRequestStatus = nil
        workspaces[index].githubPullRequestRefreshRequestID = requestID
        githubPullRequestRefreshTasks[workspaceID]?.cancel()
        publishGitState()

        let branchName = lookupKey.branchName
        let baseBranchName = lookupKey.baseBranchName
        let worktreeRootURL = lookupKey.worktreeRootURL
        githubPullRequestRefreshTasks[workspaceID] = Task { @MainActor [weak self] in
            await self?.performGitHubPullRequestRefresh(
                for: workspaceID,
                branchName: branchName,
                baseBranchName: baseBranchName,
                worktreeRootURL: worktreeRootURL,
                requestID: requestID
            )
        }
    }

    private func githubPullRequestLookupKey(
        for workspace: ProjectWorkspace
    ) -> GitHubPullRequestLookupKey? {
        guard let snapshot = workspace.gitSnapshot,
              case .branch(let branchName) = snapshot.branch,
              !snapshot.isRuriStyleWorktree else {
            return nil
        }

        return GitHubPullRequestLookupKey(
            worktreeRootURL: snapshot.worktreeRootURL,
            branchName: branchName,
            baseBranchName: githubPullRequestBaseBranch(
                for: workspace.id,
                snapshot: snapshot
            )
        )
    }

    private func githubPullRequestBaseBranch(
        for workspaceID: ProjectWorkspaceSnapshot.ID,
        snapshot: GitRepositorySnapshot
    ) -> String? {
        workspaces.first { workspace in
            workspace.id != workspaceID
                && workspace.gitSnapshot?.isRuriStyleWorktree == true
                && workspace.gitSnapshot.map { baseSnapshot in
                    FileURLRewriter.urlsMatch(
                        baseSnapshot.gitCommonDirectoryURL,
                        snapshot.gitCommonDirectoryURL
                    )
                } == true
        }?.gitSnapshot.flatMap { baseSnapshot in
            if case .branch(let branchName) = baseSnapshot.branch {
                return branchName
            }

            return nil
        }
    }

    private func performGitHubPullRequestRefresh(
        for workspaceID: ProjectWorkspaceSnapshot.ID,
        branchName: String,
        baseBranchName: String?,
        worktreeRootURL: URL,
        requestID: UUID
    ) async {
        let pullRequestStatus = await githubPullRequestService.pullRequestStatus(
            forBranch: branchName,
            baseBranch: baseBranchName,
            openedRootURL: worktreeRootURL
        )

        guard let currentIndex = workspaceIndex(for: workspaceID),
              workspaces[currentIndex].githubPullRequestRefreshRequestID == requestID else {
            return
        }

        githubPullRequestRefreshTasks.removeValue(forKey: workspaceID)
        workspaces[currentIndex].githubPullRequestStatus = pullRequestStatus
        workspaces[currentIndex].githubPullRequestRefreshRequestID = nil
        publishGitState()
    }

    private func clearGitHubPullRequest(for workspaceID: ProjectWorkspaceSnapshot.ID) {
        guard let index = workspaceIndex(for: workspaceID) else { return }

        let hadState = workspaces[index].githubPullRequestStatus != nil
            || workspaces[index].githubPullRequestLookupKey != nil
            || workspaces[index].githubPullRequestRefreshRequestID != nil
        workspaces[index].githubPullRequestStatus = nil
        workspaces[index].githubPullRequestLookupKey = nil
        workspaces[index].githubPullRequestRefreshRequestID = nil
        githubPullRequestRefreshTasks.removeValue(forKey: workspaceID)?.cancel()
        if hadState {
            publishGitState()
        }
    }

    private func refreshWorktreeMemo(for workspaceID: ProjectWorkspaceSnapshot.ID) {
        guard let key = worktreeMemoPersistenceKey(for: workspaceID) else {
            worktreeMemoLoadTasks.removeValue(forKey: workspaceID)?.cancel()
            worktreeMemoSaveTasks.removeValue(forKey: workspaceID)?.cancel()
            worktreeMemoKeysByProjectID.removeValue(forKey: workspaceID)
            worktreeMemosByProjectID.removeValue(forKey: workspaceID)
            return
        }

        guard worktreeMemoKeysByProjectID[workspaceID] != key else { return }

        worktreeMemoKeysByProjectID[workspaceID] = key
        worktreeMemoLoadTasks[workspaceID]?.cancel()
        worktreeMemoLoadTasks[workspaceID] = Task { @MainActor [weak self] in
            guard let self else { return }
            let memo = await self.worktreeMetadataStore.memo(
                forBranch: key.branchName,
                metadataDirectoryURL: key.metadataDirectoryURL
            )
            guard !Task.isCancelled,
                  self.worktreeMemoKeysByProjectID[workspaceID] == key else {
                return
            }

            self.worktreeMemosByProjectID[workspaceID] = memo
            self.worktreeMemoLoadTasks[workspaceID] = nil
        }
    }

    private func worktreeMemoPersistenceKey(
        for workspaceID: ProjectWorkspaceSnapshot.ID
    ) -> WorktreeMemoPersistenceKey? {
        guard let index = workspaceIndex(for: workspaceID),
              let snapshot = workspaces[index].gitSnapshot else {
            return nil
        }

        let branchName: String
        switch snapshot.branch {
        case .branch(let name), .unborn(let name):
            branchName = name
        case .detached:
            return nil
        }

        return WorktreeMemoPersistenceKey(
            branchName: branchName,
            metadataDirectoryURL: metadataDirectoryURL(for: workspaceID, snapshot: snapshot),
            repositoryRootURL: metadataRepositoryRootURL(for: workspaceID, snapshot: snapshot)
        )
    }

    private func metadataDirectoryURL(
        for workspaceID: ProjectWorkspaceSnapshot.ID,
        snapshot: GitRepositorySnapshot
    ) -> URL {
        if snapshot.isRuriStyleWorktree {
            return snapshot.worktreeRootURL
                .deletingLastPathComponent()
                .appending(path: ".ruri", directoryHint: .isDirectory)
                .standardizedFileURL
        }

        if let baseWorkspace = ruriStyleBaseWorkspace(matching: snapshot, excluding: workspaceID) {
            return baseWorkspace.url
                .deletingLastPathComponent()
                .appending(path: ".ruri", directoryHint: .isDirectory)
                .standardizedFileURL
        }

        return snapshot.worktreeRootURL
            .appending(path: ".ruri", directoryHint: .isDirectory)
            .standardizedFileURL
    }

    private func fallbackMetadataDirectoryURL(for workspaceURL: URL) -> URL {
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
        if FileManager.default.fileExists(atPath: siblingBaseURL.path(percentEncoded: false)) {
            return workspaceURL
                .deletingLastPathComponent()
                .appending(path: ".ruri", directoryHint: .isDirectory)
                .standardizedFileURL
        }

        return workspaceURL
            .appending(path: ".ruri", directoryHint: .isDirectory)
            .standardizedFileURL
    }

    private func metadataRepositoryRootURL(
        for workspaceID: ProjectWorkspaceSnapshot.ID,
        snapshot: GitRepositorySnapshot
    ) -> URL? {
        if snapshot.isRuriStyleWorktree
            || ruriStyleBaseWorkspace(matching: snapshot, excluding: workspaceID) != nil {
            return nil
        }

        return snapshot.worktreeRootURL
    }

    private func ruriStyleBaseWorkspace(
        matching snapshot: GitRepositorySnapshot,
        excluding workspaceID: ProjectWorkspaceSnapshot.ID
    ) -> ProjectWorkspace? {
        workspaces.first { workspace in
            workspace.id != workspaceID
                && workspace.gitSnapshot?.isRuriStyleWorktree == true
                && workspace.gitSnapshot.map { baseSnapshot in
                    FileURLRewriter.urlsMatch(
                        baseSnapshot.gitCommonDirectoryURL,
                        snapshot.gitCommonDirectoryURL
                    )
                } == true
        }
    }

    private func displayName(for url: URL, in snapshot: GitRepositorySnapshot) -> String? {
        snapshot.worktrees.first { worktree in
            FileURLRewriter.urlsMatch(worktree.rootURL, url)
        }?.displayName ?? snapshot.branch.displayName
    }

    private func refreshSymbolIndexStatus() {
        symbolIndexStatus = symbolNavigationService.currentStatus(for: projectURL)
    }

    private func startSymbolIndexingForActiveWorkspace() {
        guard let index = activeWorkspaceIndex else {
            symbolIndexStatus = .inactive
            return
        }

        symbolNavigationService.ensureIndexing(projectURL: workspaces[index].url)
        refreshSymbolIndexStatus()
    }

    private func workspaceIndex(for id: ProjectWorkspaceSnapshot.ID) -> Int? {
        workspaces.firstIndex { $0.id == id }
    }

    private func normalizedProjectID(for url: URL) -> ProjectWorkspaceSnapshot.ID {
        url.standardizedFileURL
    }
}
