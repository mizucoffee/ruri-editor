//
//  GitService.swift
//  ruri
//

import Foundation

nonisolated protocol GitServiceProtocol {
    func repositoryStatus(for openedRootURL: URL) async -> GitRepositoryStatus
    func fileSnapshot(for fileURL: URL, openedRootURL: URL) async -> GitFileSnapshot?
    func createWorktree(
        branchName: String,
        baseBranch: String?,
        openedRootURL: URL
    ) async throws -> GitWorktreeInfo
    func remoteBranches(
        openedRootURL: URL,
        refresh: Bool
    ) async throws -> [GitRemoteBranchInfo]
    func createWorktree(
        fromRemoteBranch remoteBranchFullName: String,
        openedRootURL: URL
    ) async throws -> GitWorktreeInfo
    func deleteWorktree(openedRootURL: URL) async throws
    func pull(openedRootURL: URL) async throws
    func switchBranch(named branchName: String, openedRootURL: URL) async throws
    func githubRepositoryIdentities(openedRootURL: URL) async -> [GitHubRepositoryIdentity]
    func reviewDiff(
        base: GitReviewDiffBase,
        options: GitReviewDiffOptions,
        openedRootURL: URL
    ) async throws -> GitReviewDiffSnapshot
    func reviewDiffUpdate(
        base: GitReviewDiffBase,
        options: GitReviewDiffOptions,
        fileURLs: [URL],
        openedRootURL: URL
    ) async throws -> GitReviewDiffUpdate
    func fileContents(
        at revision: String,
        relativePath: String,
        openedRootURL: URL
    ) async throws -> String
}

extension GitServiceProtocol {
    nonisolated func snapshot(for openedRootURL: URL) async -> GitRepositorySnapshot? {
        await repositoryStatus(for: openedRootURL).snapshot
    }

    nonisolated func remoteBranches(
        openedRootURL: URL,
        refresh: Bool
    ) async throws -> [GitRemoteBranchInfo] {
        throw GitWorktreeCreationError.notRepository(openedRootURL.standardizedFileURL)
    }

    nonisolated func createWorktree(
        fromRemoteBranch remoteBranchFullName: String,
        openedRootURL: URL
    ) async throws -> GitWorktreeInfo {
        throw GitWorktreeCreationError.notRepository(openedRootURL.standardizedFileURL)
    }

    nonisolated func pull(openedRootURL: URL) async throws {
        throw GitPullError.notRepository(openedRootURL.standardizedFileURL)
    }

    nonisolated func githubRepositoryIdentities(openedRootURL: URL) async -> [GitHubRepositoryIdentity] {
        []
    }

    nonisolated func reviewDiff(
        base: GitReviewDiffBase,
        options: GitReviewDiffOptions,
        openedRootURL: URL
    ) async throws -> GitReviewDiffSnapshot {
        throw GitReviewDiffError.notRepository(openedRootURL.standardizedFileURL)
    }

    nonisolated func reviewDiff(
        base: GitReviewDiffBase,
        openedRootURL: URL
    ) async throws -> GitReviewDiffSnapshot {
        try await reviewDiff(base: base, options: .default, openedRootURL: openedRootURL)
    }

    nonisolated func reviewDiff(
        baseBranch: String,
        openedRootURL: URL
    ) async throws -> GitReviewDiffSnapshot {
        try await reviewDiff(base: .branch(baseBranch), openedRootURL: openedRootURL)
    }

    nonisolated func reviewDiffUpdate(
        base: GitReviewDiffBase,
        options: GitReviewDiffOptions,
        fileURLs: [URL],
        openedRootURL: URL
    ) async throws -> GitReviewDiffUpdate {
        throw GitReviewDiffError.notRepository(openedRootURL.standardizedFileURL)
    }

    nonisolated func fileContents(
        at revision: String,
        relativePath: String,
        openedRootURL: URL
    ) async throws -> String {
        throw GitReviewDiffError.notRepository(openedRootURL.standardizedFileURL)
    }
}

nonisolated struct GitService: GitServiceProtocol, Sendable {
    private static let maximumSyntheticDiffBytes = 1_000_000

    private let executableURL: URL?
    private let commandTimeout: TimeInterval

    init(
        executableURL: URL? = GitExecutableResolver().executableURL(named: "git"),
        commandTimeout: TimeInterval = 8
    ) {
        self.executableURL = executableURL
        self.commandTimeout = commandTimeout
    }

    nonisolated func repositoryStatus(for openedRootURL: URL) async -> GitRepositoryStatus {
        guard let executableURL else {
            return .notRepository(openedRootURL.standardizedFileURL)
        }

        let openedRootURL = openedRootURL.standardizedFileURL

        do {
            let metadata = try await repositoryMetadata(
                for: openedRootURL,
                executableURL: executableURL
            )
            let statusResult = try await runGit(
                ["status", "--porcelain=v2", "--branch", "-z", "--untracked-files=all"],
                in: metadata.worktreeRootURL,
                executableURL: executableURL
            )
            guard statusResult.exitCode == 0,
                  let parsedStatus = GitStatusOutputParser.parse(
                    statusResult.stdout,
                    worktreeRootURL: metadata.worktreeRootURL
                  ) else {
                return .notRepository(openedRootURL)
            }

            let openedChanges = parsedStatus.changes.filter { change in
                Self.change(change, belongsTo: openedRootURL)
            }
            let changesByURL = Dictionary(uniqueKeysWithValues: openedChanges.map { ($0.url, $0) })
            var diffsByURL = await trackedDiffs(
                in: metadata.worktreeRootURL,
                openedRootURL: openedRootURL,
                executableURL: executableURL
            )

            for change in openedChanges where change.isUntracked {
                guard diffsByURL[change.url] == nil,
                      let syntheticDiff = Self.syntheticUntrackedDiff(for: change) else {
                    continue
                }

                diffsByURL[change.url] = syntheticDiff
            }

            let worktrees = await worktrees(
                in: metadata.worktreeRootURL,
                metadata: metadata,
                executableURL: executableURL
            )
            let worktreeRootURLs = worktrees.map(\.rootURL)
            let localBranches = await localBranches(
                in: metadata.worktreeRootURL,
                executableURL: executableURL
            )

            return .repository(GitRepositorySnapshot(
                repositoryRootURL: metadata.worktreeRootURL,
                worktreeRootURL: metadata.worktreeRootURL,
                openedRootURL: openedRootURL,
                gitDirectoryURL: metadata.gitDirectoryURL,
                gitCommonDirectoryURL: metadata.gitCommonDirectoryURL,
                worktreeKind: metadata.worktreeKind,
                worktreeRootURLs: worktreeRootURLs.isEmpty ? [metadata.worktreeRootURL] : worktreeRootURLs,
                worktrees: worktrees.isEmpty ? [
                    GitWorktreeInfo(
                        rootURL: metadata.worktreeRootURL,
                        branch: parsedStatus.branch,
                        headRevision: nil,
                        kind: metadata.worktreeKind
                    )
                ] : worktrees,
                isRuriStyleWorktree: Self.isRuriStyleWorktree(openedRootURL),
                localBranches: localBranches,
                branch: parsedStatus.branch,
                changesByURL: changesByURL,
                diffsByURL: diffsByURL
            ))
        } catch {
            return .notRepository(openedRootURL)
        }
    }

    nonisolated func fileSnapshot(for fileURL: URL, openedRootURL: URL) async -> GitFileSnapshot? {
        guard let executableURL else { return nil }

        let openedRootURL = openedRootURL.standardizedFileURL
        let fileURL = fileURL.standardizedFileURL

        do {
            let metadata = try await repositoryMetadata(
                for: openedRootURL,
                executableURL: executableURL
            )
            guard let relativePath = Self.relativePath(for: fileURL, worktreeRootURL: metadata.worktreeRootURL) else {
                return nil
            }

            let statusResult = try await runGit(
                ["status", "--porcelain=v2", "--branch", "-z", "--untracked-files=all", "--", relativePath],
                in: metadata.worktreeRootURL,
                executableURL: executableURL
            )
            guard statusResult.exitCode == 0,
                  let parsedStatus = GitStatusOutputParser.parse(
                    statusResult.stdout,
                    worktreeRootURL: metadata.worktreeRootURL
                  ) else {
                return nil
            }

            let change = parsedStatus.changes.first { change in
                Self.change(change, belongsTo: fileURL)
            }
            let diff = await trackedDiff(
                forRelativePath: relativePath,
                fileURL: fileURL,
                in: metadata.worktreeRootURL,
                executableURL: executableURL
            ) ?? change.flatMap { $0.isUntracked ? Self.syntheticUntrackedDiff(for: $0) : nil }

            return GitFileSnapshot(url: fileURL, change: change, diff: diff)
        } catch {
            return nil
        }
    }

    nonisolated func createWorktree(
        branchName: String,
        baseBranch: String? = nil,
        openedRootURL: URL
    ) async throws -> GitWorktreeInfo {
        guard let executableURL else {
            throw GitWorktreeCreationError.gitUnavailable
        }

        let openedRootURL = openedRootURL.standardizedFileURL
        let metadata: GitRepositoryMetadata
        do {
            metadata = try await repositoryMetadata(
                for: openedRootURL,
                executableURL: executableURL
            )
        } catch {
            throw GitWorktreeCreationError.notRepository(openedRootURL)
        }

        let trimmedBranchName = branchName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedBranchName.isEmpty else {
            throw GitWorktreeCreationError.invalidBranchName(branchName)
        }

        let validationResult: GitCommandResult
        do {
            validationResult = try await runGit(
                ["check-ref-format", "--branch", trimmedBranchName],
                in: metadata.worktreeRootURL,
                executableURL: executableURL
            )
        } catch GitServiceError.timedOut {
            throw GitWorktreeCreationError.timedOut
        } catch {
            throw GitWorktreeCreationError.gitCommandFailed(error.localizedDescription)
        }
        guard validationResult.exitCode == 0 else {
            throw GitWorktreeCreationError.invalidBranchName(trimmedBranchName)
        }

        let worktreeParentURL = metadata.worktreeRootURL
            .deletingLastPathComponent()
            .standardizedFileURL
        let worktreeURL = worktreeParentURL
            .appending(path: trimmedBranchName, directoryHint: .isDirectory)
            .standardizedFileURL

        guard Self.isDescendantOrSame(worktreeURL, of: worktreeParentURL),
              !FileURLRewriter.urlsMatch(worktreeURL, worktreeParentURL) else {
            throw GitWorktreeCreationError.worktreePathOutsideParent(worktreeURL)
        }

        if FileManager.default.fileExists(atPath: worktreeURL.path(percentEncoded: false)) {
            throw GitWorktreeCreationError.worktreePathAlreadyExists(worktreeURL)
        }

        let parentDirectoryURL = worktreeURL.deletingLastPathComponent()
        if !FileURLRewriter.urlsMatch(parentDirectoryURL, worktreeParentURL) {
            do {
                try FileManager.default.createDirectory(
                    at: parentDirectoryURL,
                    withIntermediateDirectories: true
                )
            } catch {
                throw GitWorktreeCreationError.gitCommandFailed(error.localizedDescription)
            }
        }

        await pullCleanRuriBaseIfNeeded(metadata: metadata, executableURL: executableURL)

        var arguments = [
            "worktree",
            "add",
            "-b",
            trimmedBranchName,
            worktreeURL.path(percentEncoded: false)
        ]
        if let baseBranch,
           !baseBranch.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            arguments.append(baseBranch)
        }

        let result: GitCommandResult
        do {
            result = try await runGit(
                arguments,
                in: metadata.worktreeRootURL,
                executableURL: executableURL
            )
        } catch GitServiceError.timedOut {
            throw GitWorktreeCreationError.timedOut
        } catch {
            throw GitWorktreeCreationError.gitCommandFailed(error.localizedDescription)
        }

        guard result.exitCode == 0 else {
            throw GitWorktreeCreationError.gitCommandFailed(Self.commandErrorMessage(from: result))
        }

        let updatedWorktrees = await worktrees(
            in: metadata.worktreeRootURL,
            metadata: metadata,
            executableURL: executableURL
        )
        if let createdWorktree = updatedWorktrees.first(where: { worktree in
            FileURLRewriter.urlsMatch(worktree.rootURL, worktreeURL)
        }) {
            return createdWorktree
        }

        return GitWorktreeInfo(
            rootURL: worktreeURL,
            branch: .branch(trimmedBranchName),
            headRevision: nil,
            kind: .linked
        )
    }

    nonisolated func remoteBranches(
        openedRootURL: URL,
        refresh: Bool
    ) async throws -> [GitRemoteBranchInfo] {
        guard let executableURL else {
            throw GitWorktreeCreationError.gitUnavailable
        }

        let openedRootURL = openedRootURL.standardizedFileURL
        let metadata: GitRepositoryMetadata
        do {
            metadata = try await repositoryMetadata(
                for: openedRootURL,
                executableURL: executableURL
            )
        } catch GitServiceError.timedOut {
            throw GitWorktreeCreationError.timedOut
        } catch {
            throw GitWorktreeCreationError.notRepository(openedRootURL)
        }

        do {
            if refresh {
                try await fetchRemotes(in: metadata.worktreeRootURL, executableURL: executableURL)
            }

            return try await remoteBranches(
                in: metadata.worktreeRootURL,
                executableURL: executableURL
            )
        } catch let error as GitWorktreeCreationError {
            throw error
        } catch GitServiceError.timedOut {
            throw GitWorktreeCreationError.timedOut
        } catch {
            throw GitWorktreeCreationError.gitCommandFailed(error.localizedDescription)
        }
    }

    nonisolated func createWorktree(
        fromRemoteBranch remoteBranchFullName: String,
        openedRootURL: URL
    ) async throws -> GitWorktreeInfo {
        guard let executableURL else {
            throw GitWorktreeCreationError.gitUnavailable
        }

        guard let remoteBranch = GitRemoteBranchInfo(fullName: remoteBranchFullName) else {
            throw GitWorktreeCreationError.invalidBranchName(remoteBranchFullName)
        }

        let openedRootURL = openedRootURL.standardizedFileURL
        let metadata: GitRepositoryMetadata
        do {
            metadata = try await repositoryMetadata(
                for: openedRootURL,
                executableURL: executableURL
            )
        } catch GitServiceError.timedOut {
            throw GitWorktreeCreationError.timedOut
        } catch {
            throw GitWorktreeCreationError.notRepository(openedRootURL)
        }

        let validationResult: GitCommandResult
        do {
            validationResult = try await runGit(
                ["check-ref-format", "--branch", remoteBranch.branchName],
                in: metadata.worktreeRootURL,
                executableURL: executableURL
            )
        } catch GitServiceError.timedOut {
            throw GitWorktreeCreationError.timedOut
        } catch {
            throw GitWorktreeCreationError.gitCommandFailed(error.localizedDescription)
        }
        guard validationResult.exitCode == 0 else {
            throw GitWorktreeCreationError.invalidBranchName(remoteBranch.branchName)
        }

        do {
            try await fetchRemotes(in: metadata.worktreeRootURL, executableURL: executableURL)
            let remoteBranches = try await remoteBranches(
                in: metadata.worktreeRootURL,
                executableURL: executableURL
            )
            guard remoteBranches.contains(where: { $0.fullName == remoteBranch.fullName }) else {
                throw GitWorktreeCreationError.remoteBranchNotFound(remoteBranch.fullName)
            }
        } catch let error as GitWorktreeCreationError {
            throw error
        } catch GitServiceError.timedOut {
            throw GitWorktreeCreationError.timedOut
        } catch {
            throw GitWorktreeCreationError.gitCommandFailed(error.localizedDescription)
        }

        let localBranches = await localBranches(
            in: metadata.worktreeRootURL,
            executableURL: executableURL
        )
        if localBranches.contains(where: { $0.name == remoteBranch.branchName }) {
            throw GitWorktreeCreationError.branchAlreadyExists(remoteBranch.branchName)
        }

        let worktreeParentURL = metadata.worktreeRootURL
            .deletingLastPathComponent()
            .standardizedFileURL
        let worktreeURL = worktreeParentURL
            .appending(path: remoteBranch.branchName, directoryHint: .isDirectory)
            .standardizedFileURL

        guard Self.isDescendantOrSame(worktreeURL, of: worktreeParentURL),
              !FileURLRewriter.urlsMatch(worktreeURL, worktreeParentURL) else {
            throw GitWorktreeCreationError.worktreePathOutsideParent(worktreeURL)
        }

        if FileManager.default.fileExists(atPath: worktreeURL.path(percentEncoded: false)) {
            throw GitWorktreeCreationError.worktreePathAlreadyExists(worktreeURL)
        }

        let parentDirectoryURL = worktreeURL.deletingLastPathComponent()
        if !FileURLRewriter.urlsMatch(parentDirectoryURL, worktreeParentURL) {
            do {
                try FileManager.default.createDirectory(
                    at: parentDirectoryURL,
                    withIntermediateDirectories: true
                )
            } catch {
                throw GitWorktreeCreationError.gitCommandFailed(error.localizedDescription)
            }
        }

        await pullCleanRuriBaseIfNeeded(metadata: metadata, executableURL: executableURL)

        let result: GitCommandResult
        do {
            result = try await runGit(
                [
                    "worktree",
                    "add",
                    "--track",
                    "-b",
                    remoteBranch.branchName,
                    worktreeURL.path(percentEncoded: false),
                    remoteBranch.fullName
                ],
                in: metadata.worktreeRootURL,
                executableURL: executableURL
            )
        } catch GitServiceError.timedOut {
            throw GitWorktreeCreationError.timedOut
        } catch {
            throw GitWorktreeCreationError.gitCommandFailed(error.localizedDescription)
        }

        guard result.exitCode == 0 else {
            throw GitWorktreeCreationError.gitCommandFailed(Self.commandErrorMessage(from: result))
        }

        let updatedWorktrees = await worktrees(
            in: metadata.worktreeRootURL,
            metadata: metadata,
            executableURL: executableURL
        )
        if let createdWorktree = updatedWorktrees.first(where: { worktree in
            FileURLRewriter.urlsMatch(worktree.rootURL, worktreeURL)
        }) {
            return createdWorktree
        }

        return GitWorktreeInfo(
            rootURL: worktreeURL,
            branch: .branch(remoteBranch.branchName),
            headRevision: nil,
            kind: .linked
        )
    }

    nonisolated func deleteWorktree(openedRootURL: URL) async throws {
        guard let executableURL else {
            throw GitWorktreeDeletionError.gitUnavailable
        }

        let openedRootURL = openedRootURL.standardizedFileURL
        let metadata: GitRepositoryMetadata
        do {
            metadata = try await repositoryMetadata(
                for: openedRootURL,
                executableURL: executableURL
            )
        } catch {
            throw GitWorktreeDeletionError.notRepository(openedRootURL)
        }

        guard metadata.worktreeKind == .linked else {
            throw GitWorktreeDeletionError.cannotDeleteMainWorktree(metadata.worktreeRootURL)
        }

        let existingWorktrees = await worktrees(
            in: metadata.worktreeRootURL,
            metadata: metadata,
            executableURL: executableURL
        )
        if let listedWorktree = existingWorktrees.first(where: { worktree in
            FileURLRewriter.urlsMatch(worktree.rootURL, metadata.worktreeRootURL)
        }), listedWorktree.kind != .linked {
            throw GitWorktreeDeletionError.cannotDeleteMainWorktree(listedWorktree.rootURL)
        }
        let deletedBranchName = existingWorktrees.compactMap { worktree -> String? in
            guard FileURLRewriter.urlsMatch(worktree.rootURL, metadata.worktreeRootURL),
                  case .branch(let branchName) = worktree.branch else {
                return nil
            }

            return branchName
        }.first

        let commandRootURL = existingWorktrees.first { worktree in
            worktree.kind == .main
        }?.rootURL ?? metadata.gitCommonDirectoryURL.deletingLastPathComponent().standardizedFileURL

        guard !FileURLRewriter.urlsMatch(commandRootURL, metadata.worktreeRootURL) else {
            throw GitWorktreeDeletionError.cannotDeleteMainWorktree(metadata.worktreeRootURL)
        }

        let result: GitCommandResult
        do {
            result = try await runGit(
                [
                    "worktree",
                    "remove",
                    "--force",
                    metadata.worktreeRootURL.path(percentEncoded: false)
                ],
                in: commandRootURL,
                executableURL: executableURL
            )
        } catch GitServiceError.timedOut {
            throw GitWorktreeDeletionError.timedOut
        } catch {
            throw GitWorktreeDeletionError.gitCommandFailed(error.localizedDescription)
        }

        guard result.exitCode == 0 else {
            throw GitWorktreeDeletionError.gitCommandFailed(Self.commandErrorMessage(from: result))
        }

        if let deletedBranchName {
            let branchResult: GitCommandResult
            do {
                branchResult = try await runGit(
                    ["branch", "-D", deletedBranchName],
                    in: commandRootURL,
                    executableURL: executableURL
                )
            } catch GitServiceError.timedOut {
                throw GitWorktreeDeletionError.timedOut
            } catch {
                throw GitWorktreeDeletionError.gitCommandFailed(error.localizedDescription)
            }

            guard branchResult.exitCode == 0 else {
                throw GitWorktreeDeletionError.gitCommandFailed(Self.commandErrorMessage(from: branchResult))
            }
        }
    }

    nonisolated func pull(openedRootURL: URL) async throws {
        guard let executableURL else {
            throw GitPullError.gitUnavailable
        }

        let openedRootURL = openedRootURL.standardizedFileURL
        let metadata: GitRepositoryMetadata
        do {
            metadata = try await repositoryMetadata(
                for: openedRootURL,
                executableURL: executableURL
            )
        } catch {
            throw GitPullError.notRepository(openedRootURL)
        }

        let result: GitCommandResult
        do {
            result = try await runGit(
                ["pull", "--rebase"],
                in: metadata.worktreeRootURL,
                executableURL: executableURL
            )
        } catch GitServiceError.timedOut {
            throw GitPullError.timedOut
        } catch {
            throw GitPullError.gitCommandFailed(error.localizedDescription)
        }

        guard result.exitCode == 0 else {
            throw GitPullError.gitCommandFailed(Self.commandErrorMessage(from: result))
        }
    }

    nonisolated func githubRepositoryIdentities(openedRootURL: URL) async -> [GitHubRepositoryIdentity] {
        guard let executableURL else { return [] }

        do {
            let result = try await runGit(
                ["remote", "-v"],
                in: openedRootURL.standardizedFileURL,
                executableURL: executableURL
            )
            guard result.exitCode == 0,
                  let output = String(data: result.stdout, encoding: .utf8) else {
                return []
            }

            return GitHubRemoteListOutputParser.parse(output)
        } catch {
            return []
        }
    }

    nonisolated func switchBranch(named branchName: String, openedRootURL: URL) async throws {
        guard let executableURL else {
            throw GitBranchSwitchError.gitUnavailable
        }

        let openedRootURL = openedRootURL.standardizedFileURL
        guard Self.isRuriStyleWorktree(openedRootURL) else {
            throw GitBranchSwitchError.notRuriStyleWorktree(openedRootURL)
        }

        let metadata: GitRepositoryMetadata
        do {
            metadata = try await repositoryMetadata(
                for: openedRootURL,
                executableURL: executableURL
            )
        } catch {
            throw GitBranchSwitchError.notRepository(openedRootURL)
        }

        let trimmedBranchName = branchName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedBranchName.isEmpty else {
            throw GitBranchSwitchError.invalidBranchName(branchName)
        }

        let validationResult: GitCommandResult
        do {
            validationResult = try await runGit(
                ["check-ref-format", "--branch", trimmedBranchName],
                in: metadata.worktreeRootURL,
                executableURL: executableURL
            )
        } catch GitServiceError.timedOut {
            throw GitBranchSwitchError.timedOut
        } catch {
            throw GitBranchSwitchError.gitCommandFailed(error.localizedDescription)
        }
        guard validationResult.exitCode == 0 else {
            throw GitBranchSwitchError.invalidBranchName(trimmedBranchName)
        }

        let branches = await localBranches(
            in: metadata.worktreeRootURL,
            executableURL: executableURL
        )
        guard let branch = branches.first(where: { $0.name == trimmedBranchName }) else {
            throw GitBranchSwitchError.branchNotFound(trimmedBranchName)
        }

        if let checkedOutWorktreeURL = branch.checkedOutWorktreeURL {
            if FileURLRewriter.urlsMatch(checkedOutWorktreeURL, metadata.worktreeRootURL) {
                return
            }

            throw GitBranchSwitchError.branchAlreadyCheckedOut(trimmedBranchName, checkedOutWorktreeURL)
        }

        let result: GitCommandResult
        do {
            result = try await runGit(
                ["switch", trimmedBranchName],
                in: metadata.worktreeRootURL,
                executableURL: executableURL
            )
        } catch GitServiceError.timedOut {
            throw GitBranchSwitchError.timedOut
        } catch {
            throw GitBranchSwitchError.gitCommandFailed(error.localizedDescription)
        }

        guard result.exitCode == 0 else {
            let message = Self.commandErrorMessage(from: result)
            let updatedBranches = await localBranches(
                in: metadata.worktreeRootURL,
                executableURL: executableURL
            )
            if let checkedOutWorktreeURL = updatedBranches
                .first(where: { $0.name == trimmedBranchName })?
                .checkedOutWorktreeURL,
               !FileURLRewriter.urlsMatch(checkedOutWorktreeURL, metadata.worktreeRootURL) {
                throw GitBranchSwitchError.branchAlreadyCheckedOut(trimmedBranchName, checkedOutWorktreeURL)
            }

            throw GitBranchSwitchError.gitCommandFailed(message)
        }
    }

    nonisolated func reviewDiff(
        base: GitReviewDiffBase,
        options: GitReviewDiffOptions,
        openedRootURL: URL
    ) async throws -> GitReviewDiffSnapshot {
        guard let executableURL else {
            throw GitReviewDiffError.gitUnavailable
        }

        let openedRootURL = openedRootURL.standardizedFileURL
        let metadata: GitRepositoryMetadata
        do {
            metadata = try await repositoryMetadata(
                for: openedRootURL,
                executableURL: executableURL
            )
        } catch GitServiceError.timedOut {
            throw GitReviewDiffError.timedOut
        } catch {
            throw GitReviewDiffError.notRepository(openedRootURL)
        }

        do {
            let baseRevision = try await reviewBaseRevision(
                for: base,
                in: metadata.worktreeRootURL,
                executableURL: executableURL
            )

            let statusResult = try await runGit(
                ["status", "--porcelain=v2", "--branch", "-z", "--untracked-files=all"],
                in: metadata.worktreeRootURL,
                executableURL: executableURL
            )
            guard statusResult.exitCode == 0,
                  let parsedStatus = GitStatusOutputParser.parse(
                    statusResult.stdout,
                    worktreeRootURL: metadata.worktreeRootURL
                  ) else {
                throw GitReviewDiffError.gitCommandFailed(Self.commandErrorMessage(from: statusResult))
            }

            let diffResult = try await runGit(
                reviewDiffArguments(
                    baseRevision: baseRevision,
                    options: options,
                    format: .patch
                ),
                in: metadata.worktreeRootURL,
                executableURL: executableURL
            )
            guard diffResult.exitCode == 0,
                  let diffText = String(data: diffResult.stdout, encoding: .utf8) else {
                throw GitReviewDiffError.gitCommandFailed(Self.commandErrorMessage(from: diffResult))
            }

            let nameStatusResult = try await runGit(
                reviewDiffArguments(
                    baseRevision: baseRevision,
                    options: options,
                    format: .nameStatus
                ),
                in: metadata.worktreeRootURL,
                executableURL: executableURL
            )
            guard nameStatusResult.exitCode == 0,
                  let nameStatusText = String(data: nameStatusResult.stdout, encoding: .utf8) else {
                throw GitReviewDiffError.gitCommandFailed(Self.commandErrorMessage(from: nameStatusResult))
            }

            let changedContentPaths: Set<String>?
            if options.hideWhitespace {
                let numstatResult = try await runGit(
                    reviewDiffArguments(
                        baseRevision: baseRevision,
                        options: options,
                        format: .numstat
                    ),
                    in: metadata.worktreeRootURL,
                    executableURL: executableURL
                )
                guard numstatResult.exitCode == 0,
                      let numstatText = String(data: numstatResult.stdout, encoding: .utf8) else {
                    throw GitReviewDiffError.gitCommandFailed(Self.commandErrorMessage(from: numstatResult))
                }
                changedContentPaths = GitDiffNumstatOutputParser.parseChangedPaths(numstatText)
            } else {
                changedContentPaths = nil
            }

            let parsedDiffs = GitDiffOutputParser.parse(diffText)
            let nameStatuses = GitDiffNameStatusOutputParser.parse(nameStatusText)
            let files = Self.reviewFiles(
                parsedDiffs: parsedDiffs,
                nameStatuses: nameStatuses,
                changedContentPaths: changedContentPaths,
                untrackedChanges: parsedStatus.changes.filter(\.isUntracked),
                worktreeRootURL: metadata.worktreeRootURL,
                openedRootURL: openedRootURL
            )

            return GitReviewDiffSnapshot(
                base: Self.normalizedReviewBase(base),
                targetBranch: parsedStatus.branch,
                targetWorktreeRootURL: metadata.worktreeRootURL,
                baseRevision: baseRevision,
                files: files
            )
        } catch let error as GitReviewDiffError {
            throw error
        } catch GitServiceError.timedOut {
            throw GitReviewDiffError.timedOut
        } catch {
            throw GitReviewDiffError.gitCommandFailed(error.localizedDescription)
        }
    }

    nonisolated func reviewDiffUpdate(
        base: GitReviewDiffBase,
        options: GitReviewDiffOptions,
        fileURLs: [URL],
        openedRootURL: URL
    ) async throws -> GitReviewDiffUpdate {
        guard let executableURL else {
            throw GitReviewDiffError.gitUnavailable
        }

        let openedRootURL = openedRootURL.standardizedFileURL
        let metadata: GitRepositoryMetadata
        do {
            metadata = try await repositoryMetadata(
                for: openedRootURL,
                executableURL: executableURL
            )
        } catch GitServiceError.timedOut {
            throw GitReviewDiffError.timedOut
        } catch {
            throw GitReviewDiffError.notRepository(openedRootURL)
        }

        let relativePaths = Set(fileURLs.compactMap { fileURL in
            Self.relativePath(
                for: fileURL.standardizedFileURL,
                worktreeRootURL: metadata.worktreeRootURL
            )
        })

        do {
            let baseRevision = try await reviewBaseRevision(
                for: base,
                in: metadata.worktreeRootURL,
                executableURL: executableURL
            )

            guard !relativePaths.isEmpty else {
                let statusResult = try await runGit(
                    ["status", "--porcelain=v2", "--branch", "-z", "--untracked-files=all"],
                    in: metadata.worktreeRootURL,
                    executableURL: executableURL
                )
                guard statusResult.exitCode == 0,
                      let parsedStatus = GitStatusOutputParser.parse(
                        statusResult.stdout,
                        worktreeRootURL: metadata.worktreeRootURL
                      ) else {
                    throw GitReviewDiffError.gitCommandFailed(Self.commandErrorMessage(from: statusResult))
                }

                return GitReviewDiffUpdate(
                    base: Self.normalizedReviewBase(base),
                    targetBranch: parsedStatus.branch,
                    targetWorktreeRootURL: metadata.worktreeRootURL,
                    baseRevision: baseRevision,
                    requestedRelativePaths: [],
                    files: []
                )
            }

            let sortedRelativePaths = relativePaths.sorted()
            let statusResult = try await runGit(
                ["status", "--porcelain=v2", "--branch", "-z", "--untracked-files=all", "--"] + sortedRelativePaths,
                in: metadata.worktreeRootURL,
                executableURL: executableURL
            )
            guard statusResult.exitCode == 0,
                  let parsedStatus = GitStatusOutputParser.parse(
                    statusResult.stdout,
                    worktreeRootURL: metadata.worktreeRootURL
                  ) else {
                throw GitReviewDiffError.gitCommandFailed(Self.commandErrorMessage(from: statusResult))
            }

            let diffResult = try await runGit(
                reviewDiffArguments(
                    baseRevision: baseRevision,
                    options: options,
                    format: .patch,
                    pathspecs: sortedRelativePaths
                ),
                in: metadata.worktreeRootURL,
                executableURL: executableURL
            )
            guard diffResult.exitCode == 0,
                  let diffText = String(data: diffResult.stdout, encoding: .utf8) else {
                throw GitReviewDiffError.gitCommandFailed(Self.commandErrorMessage(from: diffResult))
            }

            let nameStatusResult = try await runGit(
                reviewDiffArguments(
                    baseRevision: baseRevision,
                    options: options,
                    format: .nameStatus,
                    pathspecs: sortedRelativePaths
                ),
                in: metadata.worktreeRootURL,
                executableURL: executableURL
            )
            guard nameStatusResult.exitCode == 0,
                  let nameStatusText = String(data: nameStatusResult.stdout, encoding: .utf8) else {
                throw GitReviewDiffError.gitCommandFailed(Self.commandErrorMessage(from: nameStatusResult))
            }

            let changedContentPaths: Set<String>?
            if options.hideWhitespace {
                let numstatResult = try await runGit(
                    reviewDiffArguments(
                        baseRevision: baseRevision,
                        options: options,
                        format: .numstat,
                        pathspecs: sortedRelativePaths
                    ),
                    in: metadata.worktreeRootURL,
                    executableURL: executableURL
                )
                guard numstatResult.exitCode == 0,
                      let numstatText = String(data: numstatResult.stdout, encoding: .utf8) else {
                    throw GitReviewDiffError.gitCommandFailed(Self.commandErrorMessage(from: numstatResult))
                }
                changedContentPaths = GitDiffNumstatOutputParser.parseChangedPaths(numstatText)
            } else {
                changedContentPaths = nil
            }

            let parsedDiffs = GitDiffOutputParser.parse(diffText)
            let nameStatuses = GitDiffNameStatusOutputParser.parse(nameStatusText)
            let files = Self.reviewFiles(
                parsedDiffs: parsedDiffs,
                nameStatuses: nameStatuses,
                changedContentPaths: changedContentPaths,
                untrackedChanges: parsedStatus.changes.filter(\.isUntracked),
                worktreeRootURL: metadata.worktreeRootURL,
                openedRootURL: openedRootURL
            )

            return GitReviewDiffUpdate(
                base: Self.normalizedReviewBase(base),
                targetBranch: parsedStatus.branch,
                targetWorktreeRootURL: metadata.worktreeRootURL,
                baseRevision: baseRevision,
                requestedRelativePaths: relativePaths,
                files: files
            )
        } catch let error as GitReviewDiffError {
            throw error
        } catch GitServiceError.timedOut {
            throw GitReviewDiffError.timedOut
        } catch {
            throw GitReviewDiffError.gitCommandFailed(error.localizedDescription)
        }
    }

    private nonisolated func reviewDiffArguments(
        baseRevision: String,
        options: GitReviewDiffOptions,
        format: ReviewDiffCommandFormat,
        pathspecs: [String] = []
    ) -> [String] {
        var arguments = ["diff"]
        switch format {
        case .patch:
            arguments.append("--unified=3")
        case .nameStatus:
            arguments += ["--name-status", "-z"]
        case .numstat:
            arguments += ["--numstat", "-z"]
        }
        arguments += ["--no-color", "--no-ext-diff", "--find-renames"]
        if options.hideWhitespace {
            arguments += ["--ignore-all-space", "--ignore-blank-lines"]
        }
        arguments += [baseRevision, "--"]
        arguments += pathspecs
        return arguments
    }

    private enum ReviewDiffCommandFormat {
        case patch
        case nameStatus
        case numstat
    }

    private nonisolated func reviewBaseRevision(
        for base: GitReviewDiffBase,
        in worktreeRootURL: URL,
        executableURL: URL
    ) async throws -> String {
        switch base {
        case .branch(let branchName):
            let trimmedBranchName = branchName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedBranchName.isEmpty else {
                throw GitReviewDiffError.invalidBaseBranch(branchName)
            }

            let baseValidation = try await runGit(
                ["rev-parse", "--verify", "\(trimmedBranchName)^{commit}"],
                in: worktreeRootURL,
                executableURL: executableURL
            )
            guard baseValidation.exitCode == 0 else {
                throw GitReviewDiffError.invalidBaseBranch(trimmedBranchName)
            }

            let mergeBaseResult = try await runGit(
                ["merge-base", trimmedBranchName, "HEAD"],
                in: worktreeRootURL,
                executableURL: executableURL
            )
            guard mergeBaseResult.exitCode == 0,
                  let mergeBaseRevision = String(data: mergeBaseResult.stdout, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                  !mergeBaseRevision.isEmpty else {
                throw GitReviewDiffError.mergeBaseNotFound(trimmedBranchName)
            }

            return mergeBaseRevision

        case .uncommitted:
            let headResult = try await runGit(
                ["rev-parse", "--verify", "HEAD^{commit}"],
                in: worktreeRootURL,
                executableURL: executableURL
            )
            guard headResult.exitCode == 0,
                  let headRevision = String(data: headResult.stdout, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                  !headRevision.isEmpty else {
                throw GitReviewDiffError.mergeBaseNotFound("HEAD")
            }

            return headRevision
        }
    }

    private nonisolated static func normalizedReviewBase(_ base: GitReviewDiffBase) -> GitReviewDiffBase {
        switch base {
        case .branch(let branchName):
            .branch(branchName.trimmingCharacters(in: .whitespacesAndNewlines))
        case .uncommitted:
            .uncommitted
        }
    }

    nonisolated func fileContents(
        at revision: String,
        relativePath: String,
        openedRootURL: URL
    ) async throws -> String {
        guard let executableURL else {
            throw GitReviewDiffError.gitUnavailable
        }

        let trimmedRevision = revision.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedRevision.isEmpty,
              !relativePath.isEmpty,
              !relativePath.contains("\u{0}") else {
            throw GitReviewDiffError.gitCommandFailed("Invalid Git file revision or path.")
        }

        let openedRootURL = openedRootURL.standardizedFileURL
        let metadata: GitRepositoryMetadata
        do {
            metadata = try await repositoryMetadata(
                for: openedRootURL,
                executableURL: executableURL
            )
        } catch GitServiceError.timedOut {
            throw GitReviewDiffError.timedOut
        } catch {
            throw GitReviewDiffError.notRepository(openedRootURL)
        }

        do {
            let result = try await runGit(
                ["show", "--no-ext-diff", "\(trimmedRevision):\(relativePath)"],
                in: metadata.worktreeRootURL,
                executableURL: executableURL
            )
            guard result.exitCode == 0,
                  let text = String(data: result.stdout, encoding: .utf8) else {
                throw GitReviewDiffError.gitCommandFailed(Self.commandErrorMessage(from: result))
            }

            return text
        } catch let error as GitReviewDiffError {
            throw error
        } catch GitServiceError.timedOut {
            throw GitReviewDiffError.timedOut
        } catch {
            throw GitReviewDiffError.gitCommandFailed(error.localizedDescription)
        }
    }

    private nonisolated func repositoryMetadata(
        for openedRootURL: URL,
        executableURL: URL
    ) async throws -> GitRepositoryMetadata {
        let result = try await runGit(
            [
                "rev-parse",
                "--path-format=absolute",
                "--show-toplevel",
                "--git-dir",
                "--git-common-dir",
                "--is-inside-work-tree"
            ],
            in: openedRootURL,
            executableURL: executableURL
        )
        guard result.exitCode == 0,
              let output = String(data: result.stdout, encoding: .utf8) else {
            throw GitServiceError.notRepository
        }

        let lines = output
            .split(whereSeparator: \.isNewline)
            .map(String.init)
        guard lines.count >= 4,
              lines[3] == "true" else {
            throw GitServiceError.notRepository
        }

        let worktreeRootURL = URL(filePath: lines[0], directoryHint: .isDirectory).standardizedFileURL
        let gitDirectoryURL = URL(filePath: lines[1], directoryHint: .isDirectory).standardizedFileURL
        let gitCommonDirectoryURL = URL(filePath: lines[2], directoryHint: .isDirectory).standardizedFileURL
        let worktreeKind: GitWorktreeKind = FileURLRewriter.urlsMatch(gitDirectoryURL, gitCommonDirectoryURL)
            ? .main
            : .linked

        return GitRepositoryMetadata(
            worktreeRootURL: worktreeRootURL,
            gitDirectoryURL: gitDirectoryURL,
            gitCommonDirectoryURL: gitCommonDirectoryURL,
            worktreeKind: worktreeKind
        )
    }

    private nonisolated func worktrees(
        in worktreeRootURL: URL,
        metadata: GitRepositoryMetadata,
        executableURL: URL
    ) async -> [GitWorktreeInfo] {
        do {
            let result = try await runGit(
                ["worktree", "list", "--porcelain", "-z"],
                in: worktreeRootURL,
                executableURL: executableURL
            )
            guard result.exitCode == 0,
                  let output = String(data: result.stdout, encoding: .utf8) else {
                return []
            }

            return GitWorktreeListOutputParser.parse(output, gitCommonDirectoryURL: metadata.gitCommonDirectoryURL)
        } catch {
            return []
        }
    }

    private nonisolated func localBranches(
        in worktreeRootURL: URL,
        executableURL: URL
    ) async -> [GitLocalBranchInfo] {
        do {
            let result = try await runGit(
                [
                    "for-each-ref",
                    "--sort=refname",
                    "--format=%(refname:short)%09%(worktreepath)",
                    "refs/heads"
                ],
                in: worktreeRootURL,
                executableURL: executableURL
            )
            guard result.exitCode == 0,
                  let output = String(data: result.stdout, encoding: .utf8) else {
                return []
            }

            return GitLocalBranchListOutputParser.parse(output)
        } catch {
            return []
        }
    }

    private nonisolated func fetchRemotes(
        in worktreeRootURL: URL,
        executableURL: URL
    ) async throws {
        let result = try await runGit(
            ["fetch", "--all", "--prune"],
            in: worktreeRootURL,
            executableURL: executableURL
        )
        guard result.exitCode == 0 else {
            throw GitWorktreeCreationError.gitCommandFailed(Self.commandErrorMessage(from: result))
        }
    }

    private nonisolated func remoteBranches(
        in worktreeRootURL: URL,
        executableURL: URL
    ) async throws -> [GitRemoteBranchInfo] {
        let result = try await runGit(
            [
                "for-each-ref",
                "--sort=refname",
                "--format=%(refname:short)%09%(symref)",
                "refs/remotes"
            ],
            in: worktreeRootURL,
            executableURL: executableURL
        )
        guard result.exitCode == 0,
              let output = String(data: result.stdout, encoding: .utf8) else {
            throw GitWorktreeCreationError.gitCommandFailed(Self.commandErrorMessage(from: result))
        }

        return GitRemoteBranchListOutputParser.parse(output)
    }

    private nonisolated func pullCleanRuriBaseIfNeeded(
        metadata: GitRepositoryMetadata,
        executableURL: URL
    ) async {
        guard Self.isRuriStyleWorktree(metadata.worktreeRootURL) else { return }

        do {
            let statusResult = try await runGit(
                ["status", "--porcelain=v2", "--branch", "-z", "--untracked-files=all"],
                in: metadata.worktreeRootURL,
                executableURL: executableURL
            )
            guard statusResult.exitCode == 0,
                  let parsedStatus = GitStatusOutputParser.parse(
                    statusResult.stdout,
                    worktreeRootURL: metadata.worktreeRootURL
                  ),
                  parsedStatus.changes.isEmpty else {
                return
            }

            _ = try await runGit(
                ["pull", "--rebase"],
                in: metadata.worktreeRootURL,
                executableURL: executableURL
            )
        } catch {
            return
        }
    }

    private nonisolated func trackedDiffs(
        in worktreeRootURL: URL,
        openedRootURL: URL,
        executableURL: URL
    ) async -> [URL: SourceFileDiff] {
        do {
            let result = try await runGit(
                ["diff", "HEAD", "--unified=0", "--no-color", "--no-ext-diff", "--find-renames", "--"],
                in: worktreeRootURL,
                executableURL: executableURL
            )
            guard result.exitCode == 0,
                  let diffText = String(data: result.stdout, encoding: .utf8) else {
                return [:]
            }

            let diffs = GitDiffOutputParser.parse(diffText)
            return Dictionary(uniqueKeysWithValues: diffs.compactMap { diff in
                guard let url = Self.url(for: diff, worktreeRootURL: worktreeRootURL),
                      Self.isDescendantOrSame(url, of: openedRootURL) else {
                    return nil
                }

                return (url, diff)
            })
        } catch {
            return [:]
        }
    }

    private nonisolated func trackedDiff(
        forRelativePath relativePath: String,
        fileURL: URL,
        in worktreeRootURL: URL,
        executableURL: URL
    ) async -> SourceFileDiff? {
        do {
            let result = try await runGit(
                ["diff", "HEAD", "--unified=0", "--no-color", "--no-ext-diff", "--find-renames", "--", relativePath],
                in: worktreeRootURL,
                executableURL: executableURL
            )
            guard result.exitCode == 0,
                  let diffText = String(data: result.stdout, encoding: .utf8) else {
                return nil
            }

            return GitDiffOutputParser.parse(diffText).first { diff in
                guard let url = Self.url(for: diff, worktreeRootURL: worktreeRootURL) else {
                    return false
                }

                return FileURLRewriter.urlsMatch(url, fileURL)
            }
        } catch {
            return nil
        }
    }

    private nonisolated func runGit(
        _ arguments: [String],
        in directoryURL: URL,
        executableURL: URL
    ) async throws -> GitCommandResult {
        let commandTimeout = commandTimeout

        return try await Task.detached(priority: .utility) {
            try GitCommandRunner.run(
                executableURL: executableURL,
                arguments: [
                    "--no-optional-locks",
                    "-C",
                    directoryURL.path(percentEncoded: false),
                    "-c",
                    "color.ui=false",
                    "-c",
                    "core.quotePath=false"
                ] + arguments,
                timeout: commandTimeout
            )
        }.value
    }

    private nonisolated static func reviewFiles(
        parsedDiffs: [SourceFileDiff],
        nameStatuses: [GitDiffNameStatusEntry],
        changedContentPaths: Set<String>?,
        untrackedChanges: [GitFileChange],
        worktreeRootURL: URL,
        openedRootURL: URL
    ) -> [GitReviewFileDiff] {
        var diffByKey: [String: SourceFileDiff] = [:]
        for diff in parsedDiffs {
            diffByKey[reviewFileKey(oldPath: diff.oldRelativePath, newPath: diff.newRelativePath)] = diff
        }

        var files: [GitReviewFileDiff] = []
        var seenKeys = Set<String>()

        for entry in nameStatuses where reviewEntry(entry, belongsTo: openedRootURL, worktreeRootURL: worktreeRootURL) {
            if entry.status == .modified,
               let changedContentPaths,
               !reviewEntry(entry, hasPathIn: changedContentPaths) {
                continue
            }

            let key = reviewFileKey(oldPath: entry.oldRelativePath, newPath: entry.newRelativePath)
            let diff = diffByKey[key] ?? SourceFileDiff(
                oldRelativePath: entry.oldRelativePath,
                newRelativePath: entry.newRelativePath,
                hunks: []
            )
            files.append(GitReviewFileDiff(
                diff: diff,
                status: entry.status,
                isBinary: diffByKey[key] == nil
            ))
            seenKeys.insert(key)
        }

        for diff in parsedDiffs {
            let key = reviewFileKey(oldPath: diff.oldRelativePath, newPath: diff.newRelativePath)
            guard !seenKeys.contains(key),
                  let url = url(for: diff, worktreeRootURL: worktreeRootURL),
                  isDescendantOrSame(url, of: openedRootURL) else {
                continue
            }

            files.append(GitReviewFileDiff(diff: diff))
            seenKeys.insert(key)
        }

        for change in untrackedChanges where Self.change(change, belongsTo: openedRootURL) {
            let key = reviewFileKey(oldPath: nil, newPath: change.relativePath)
            guard !seenKeys.contains(key) else { continue }

            let syntheticDiff = syntheticUntrackedDiff(for: change)
            let diff = syntheticDiff ?? SourceFileDiff(
                oldRelativePath: nil,
                newRelativePath: change.relativePath,
                hunks: []
            )
            files.append(GitReviewFileDiff(
                diff: diff,
                status: .untracked,
                isBinary: syntheticDiff == nil
            ))
            seenKeys.insert(key)
        }

        return files.sorted { lhs, rhs in
            lhs.displayRelativePath.localizedStandardCompare(rhs.displayRelativePath) == .orderedAscending
        }
    }

    private nonisolated static func reviewEntry(
        _ entry: GitDiffNameStatusEntry,
        hasPathIn paths: Set<String>
    ) -> Bool {
        [entry.oldRelativePath, entry.newRelativePath].contains { relativePath in
            relativePath.map { paths.contains($0) } == true
        }
    }

    private nonisolated static func reviewEntry(
        _ entry: GitDiffNameStatusEntry,
        belongsTo openedRootURL: URL,
        worktreeRootURL: URL
    ) -> Bool {
        [entry.oldRelativePath, entry.newRelativePath].compactMap { relativePath in
            guard let relativePath,
                  !isRuriMetadataRelativePath(relativePath) else {
                return nil
            }

            return worktreeRootURL.appending(path: relativePath).standardizedFileURL
        }
        .contains { url in
            isDescendantOrSame(url, of: openedRootURL)
        }
    }

    private nonisolated static func reviewFileKey(oldPath: String?, newPath: String?) -> String {
        "\(oldPath ?? "")\u{0}\(newPath ?? "")"
    }

    private nonisolated static func syntheticUntrackedDiff(for change: GitFileChange) -> SourceFileDiff? {
        let path = change.url.path(percentEncoded: false)
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: path),
              attributes[.type] as? FileAttributeType == .typeRegular,
              let fileSize = (attributes[.size] as? NSNumber)?.intValue,
              fileSize <= maximumSyntheticDiffBytes,
              let data = try? Data(contentsOf: change.url),
              let text = String(data: data, encoding: .utf8) else {
            return nil
        }

        let contentLines = lines(in: text)
        guard !contentLines.isEmpty else {
            return SourceFileDiff(
                oldRelativePath: nil,
                newRelativePath: change.relativePath,
                hunks: []
            )
        }

        let lines = contentLines.enumerated().map { offset, content in
            SourceDiffLine(
                kind: .addition,
                oldLineNumber: nil,
                newLineNumber: offset + 1,
                content: content
            )
        }
        return SourceFileDiff(
            oldRelativePath: nil,
            newRelativePath: change.relativePath,
            hunks: [
                SourceDiffHunk(
                    oldStart: 0,
                    oldLineCount: 0,
                    newStart: 1,
                    newLineCount: contentLines.count,
                    lines: lines
                )
            ]
        )
    }

    private nonisolated static func lines(in text: String) -> [String] {
        guard !text.isEmpty else { return [] }

        var lines = text
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
        if text.hasSuffix("\n") {
            _ = lines.popLast()
        }

        return lines
    }

    private nonisolated static func url(for diff: SourceFileDiff, worktreeRootURL: URL) -> URL? {
        guard let relativePath = diff.newRelativePath ?? diff.oldRelativePath,
              !relativePath.isEmpty else {
            return nil
        }

        return worktreeRootURL.appending(path: relativePath).standardizedFileURL
    }

    private nonisolated static func change(_ change: GitFileChange, belongsTo openedRootURL: URL) -> Bool {
        guard !isRuriMetadataRelativePath(change.relativePath) else { return false }

        return isDescendantOrSame(change.url, of: openedRootURL)
            || change.originalURL.map { isDescendantOrSame($0, of: openedRootURL) } == true
    }

    private nonisolated static func isRuriMetadataRelativePath(_ relativePath: String) -> Bool {
        relativePath == ".ruri" || relativePath.hasPrefix(".ruri/")
    }

    private nonisolated static func isDescendantOrSame(_ url: URL, of rootURL: URL) -> Bool {
        let path = FileURLRewriter.normalizedPath(url)
        let rootPath = FileURLRewriter.normalizedPath(rootURL)

        if path == rootPath {
            return true
        }

        let rootPathPrefix = rootPath.hasSuffix("/") ? rootPath : "\(rootPath)/"
        return path.hasPrefix(rootPathPrefix)
    }

    private nonisolated static func relativePath(for url: URL, worktreeRootURL: URL) -> String? {
        let path = FileURLRewriter.normalizedPath(url)
        let rootPath = FileURLRewriter.normalizedPath(worktreeRootURL)
        let rootPathPrefix = rootPath.hasSuffix("/") ? rootPath : "\(rootPath)/"

        guard path.hasPrefix(rootPathPrefix) else {
            return nil
        }

        return String(path.dropFirst(rootPathPrefix.count))
    }

    private nonisolated static func isRuriStyleWorktree(_ openedRootURL: URL) -> Bool {
        openedRootURL.standardizedFileURL.lastPathComponent == "ruri-base"
    }

    private nonisolated static func commandErrorMessage(from result: GitCommandResult) -> String {
        if let stderr = String(data: result.stderr, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !stderr.isEmpty {
            return stderr
        }

        if let stdout = String(data: result.stdout, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !stdout.isEmpty {
            return stdout
        }

        return "Git command failed with exit code \(result.exitCode)."
    }
}

nonisolated private enum GitServiceError: Error {
    case notRepository
    case timedOut
}

nonisolated private struct GitRepositoryMetadata: Sendable {
    let worktreeRootURL: URL
    let gitDirectoryURL: URL
    let gitCommonDirectoryURL: URL
    let worktreeKind: GitWorktreeKind
}

nonisolated private struct GitExecutableResolver {
    var environment: [String: String] = ProcessInfo.processInfo.environment
    var fallbackDirectories: [String] = [
        "/opt/homebrew/bin",
        "/usr/local/bin",
        "/usr/bin"
    ]

    func executableURL(named executableName: String) -> URL? {
        for directory in searchDirectories {
            let url = URL(filePath: directory).appending(path: executableName)
            if FileManager.default.isExecutableFile(atPath: url.path(percentEncoded: false)) {
                return url.standardizedFileURL
            }
        }

        return nil
    }

    private var searchDirectories: [String] {
        let pathDirectories = (environment["PATH"] ?? "")
            .split(separator: ":")
            .map(String.init)

        var seen = Set<String>()
        return (pathDirectories + fallbackDirectories).filter { directory in
            guard !directory.isEmpty else { return false }
            return seen.insert(directory).inserted
        }
    }
}

nonisolated private struct GitCommandResult: Sendable {
    let stdout: Data
    let stderr: Data
    let exitCode: Int32
}

nonisolated private enum GitCommandRunner {
    static func run(
        executableURL: URL,
        arguments: [String],
        timeout: TimeInterval
    ) throws -> GitCommandResult {
        let process = Process()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        let stdout = LockedData()
        let stderr = LockedData()
        let terminationSemaphore = DispatchSemaphore(value: 0)

        process.executableURL = executableURL
        process.arguments = arguments
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        process.environment = ProcessInfo.processInfo.environment.merging([
            "LC_ALL": "C",
            "LANG": "C",
            "GIT_OPTIONAL_LOCKS": "0"
        ]) { _, newValue in newValue }
        process.terminationHandler = { _ in
            terminationSemaphore.signal()
        }

        stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if !data.isEmpty {
                stdout.append(data)
            }
        }
        stderrPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if !data.isEmpty {
                stderr.append(data)
            }
        }

        do {
            try SafeProcessLauncher.run(process)
        } catch {
            stdoutPipe.fileHandleForReading.readabilityHandler = nil
            stderrPipe.fileHandleForReading.readabilityHandler = nil
            throw error
        }

        let timeoutResult = terminationSemaphore.wait(timeout: .now() + timeout)
        if timeoutResult == .timedOut {
            process.terminate()
            process.waitUntilExit()
            stdoutPipe.fileHandleForReading.readabilityHandler = nil
            stderrPipe.fileHandleForReading.readabilityHandler = nil
            throw GitServiceError.timedOut
        }

        stdoutPipe.fileHandleForReading.readabilityHandler = nil
        stderrPipe.fileHandleForReading.readabilityHandler = nil

        let remainingStdout = stdoutPipe.fileHandleForReading.availableData
        if !remainingStdout.isEmpty {
            stdout.append(remainingStdout)
        }
        let remainingStderr = stderrPipe.fileHandleForReading.availableData
        if !remainingStderr.isEmpty {
            stderr.append(remainingStderr)
        }

        return GitCommandResult(
            stdout: stdout.data(),
            stderr: stderr.data(),
            exitCode: process.terminationStatus
        )
    }
}

nonisolated private final class LockedData: @unchecked Sendable {
    private let lock = NSLock()
    private var storedData = Data()

    func append(_ data: Data) {
        lock.lock()
        storedData.append(data)
        lock.unlock()
    }

    func data() -> Data {
        lock.lock()
        let data = storedData
        lock.unlock()
        return data
    }
}

nonisolated private struct ParsedGitStatus {
    let branch: GitBranchState
    let changes: [GitFileChange]
}

nonisolated private enum GitWorktreeListOutputParser {
    static func parse(_ output: String, gitCommonDirectoryURL: URL) -> [GitWorktreeInfo] {
        let records = output
            .split(separator: "\0", omittingEmptySubsequences: true)
            .map(String.init)
        var worktrees: [GitWorktreeInfo] = []
        var rootURL: URL?
        var headRevision: String?
        var branch: GitBranchState?

        func appendCurrent() {
            guard let rootURL else { return }

            let kind: GitWorktreeKind = FileURLRewriter.urlsMatch(
                rootURL,
                gitCommonDirectoryURL.deletingLastPathComponent()
            ) ? .main : .linked
            let resolvedBranch = branch ?? headRevision.map { revision in
                GitBranchState.detached(String(revision.prefix(7)))
            }

            worktrees.append(
                GitWorktreeInfo(
                    rootURL: rootURL,
                    branch: resolvedBranch,
                    headRevision: headRevision,
                    kind: kind
                )
            )
        }

        for record in records {
            if let path = record.removingPrefix("worktree ") {
                appendCurrent()
                rootURL = URL(filePath: path, directoryHint: .isDirectory).standardizedFileURL
                headRevision = nil
                branch = nil
                continue
            }

            if let revision = record.removingPrefix("HEAD ") {
                headRevision = revision
                continue
            }

            if let branchRef = record.removingPrefix("branch ") {
                if let branchName = branchRef.removingPrefix("refs/heads/") {
                    branch = .branch(branchName)
                } else {
                    branch = .branch(branchRef)
                }
                continue
            }
        }

        appendCurrent()
        return worktrees
    }
}

nonisolated private enum GitLocalBranchListOutputParser {
    static func parse(_ output: String) -> [GitLocalBranchInfo] {
        output
            .split(whereSeparator: \.isNewline)
            .compactMap { line -> GitLocalBranchInfo? in
                let fields = line.split(
                    separator: "\t",
                    maxSplits: 1,
                    omittingEmptySubsequences: false
                )
                guard let name = fields.first.map(String.init),
                      !name.isEmpty else {
                    return nil
                }

                let worktreePath = fields.count > 1 ? String(fields[1]) : ""
                let checkedOutWorktreeURL = worktreePath.isEmpty
                    ? nil
                    : URL(filePath: worktreePath, directoryHint: .isDirectory).standardizedFileURL

                return GitLocalBranchInfo(
                    name: name,
                    checkedOutWorktreeURL: checkedOutWorktreeURL
                )
            }
    }
}

nonisolated private enum GitRemoteBranchListOutputParser {
    static func parse(_ output: String) -> [GitRemoteBranchInfo] {
        output
            .split(whereSeparator: \.isNewline)
            .compactMap { line -> GitRemoteBranchInfo? in
                let fields = line.split(
                    separator: "\t",
                    maxSplits: 1,
                    omittingEmptySubsequences: false
                )
                guard let fullName = fields.first.map(String.init),
                      !fullName.isEmpty else {
                    return nil
                }

                let symref = fields.count > 1 ? String(fields[1]) : ""
                guard symref.isEmpty else { return nil }

                return GitRemoteBranchInfo(fullName: fullName)
            }
    }
}

nonisolated private struct GitDiffNameStatusEntry: Equatable, Sendable {
    let status: GitFileDisplayStatus
    let oldRelativePath: String?
    let newRelativePath: String?
}

nonisolated private enum GitDiffNameStatusOutputParser {
    static func parse(_ output: String) -> [GitDiffNameStatusEntry] {
        let records = output
            .split(separator: "\0", omittingEmptySubsequences: true)
            .map(String.init)
        var entries: [GitDiffNameStatusEntry] = []
        var index = 0

        while index < records.count {
            let statusToken = records[index]
            index += 1
            guard let statusCharacter = statusToken.first else { continue }

            switch statusCharacter {
            case "R":
                guard index + 1 < records.count else {
                    index = records.count
                    continue
                }
                let oldPath = records[index]
                let newPath = records[index + 1]
                index += 2
                entries.append(GitDiffNameStatusEntry(
                    status: .renamed,
                    oldRelativePath: oldPath,
                    newRelativePath: newPath
                ))

            case "C":
                guard index + 1 < records.count else {
                    index = records.count
                    continue
                }
                let oldPath = records[index]
                let newPath = records[index + 1]
                index += 2
                entries.append(GitDiffNameStatusEntry(
                    status: .copied,
                    oldRelativePath: oldPath,
                    newRelativePath: newPath
                ))

            default:
                guard index < records.count else { continue }
                let path = records[index]
                index += 1
                entries.append(GitDiffNameStatusEntry(
                    status: displayStatus(for: statusCharacter),
                    oldRelativePath: statusCharacter == "A" ? nil : path,
                    newRelativePath: statusCharacter == "D" ? nil : path
                ))
            }
        }

        return entries
    }

    private static func displayStatus(for status: Character) -> GitFileDisplayStatus {
        switch status {
        case "A":
            .added
        case "D":
            .deleted
        case "U":
            .conflicted
        default:
            .modified
        }
    }
}

nonisolated private enum GitStatusOutputParser {
    static func parse(_ data: Data, worktreeRootURL: URL) -> ParsedGitStatus? {
        guard let output = String(data: data, encoding: .utf8) else { return nil }

        let records = output
            .split(separator: "\0", omittingEmptySubsequences: true)
            .map(String.init)
        var branchHead: String?
        var branchOID: String?
        var changes: [GitFileChange] = []
        var index = 0

        while index < records.count {
            let record = records[index]

            if let value = record.removingPrefix("# branch.head ") {
                branchHead = value
                index += 1
                continue
            }

            if let value = record.removingPrefix("# branch.oid ") {
                branchOID = value
                index += 1
                continue
            }

            if let change = parseOrdinaryChange(record, worktreeRootURL: worktreeRootURL) {
                changes.append(change)
                index += 1
                continue
            }

            if let change = parseRenameChange(
                record,
                originalPathRecord: records[safe: index + 1],
                worktreeRootURL: worktreeRootURL
            ) {
                changes.append(change)
                index += 2
                continue
            }

            if let change = parseUnmergedChange(record, worktreeRootURL: worktreeRootURL) {
                changes.append(change)
                index += 1
                continue
            }

            if let relativePath = record.removingPrefix("? ") {
                changes.append(
                    GitFileChange(
                        url: worktreeRootURL.appending(path: relativePath),
                        relativePath: relativePath,
                        isUntracked: true
                    )
                )
                index += 1
                continue
            }

            index += 1
        }

        guard let branch = branchState(head: branchHead, oid: branchOID) else {
            return nil
        }

        return ParsedGitStatus(branch: branch, changes: changes)
    }

    private static func parseOrdinaryChange(
        _ record: String,
        worktreeRootURL: URL
    ) -> GitFileChange? {
        guard record.hasPrefix("1 ") else { return nil }

        let fields = record.split(separator: " ", maxSplits: 8, omittingEmptySubsequences: false)
        guard fields.count == 9 else { return nil }

        let xy = String(fields[1])
        let relativePath = String(fields[8])
        return GitFileChange(
            url: worktreeRootURL.appending(path: relativePath),
            relativePath: relativePath,
            indexStatus: statusCharacter(at: 0, in: xy),
            worktreeStatus: statusCharacter(at: 1, in: xy)
        )
    }

    private static func parseRenameChange(
        _ record: String,
        originalPathRecord: String?,
        worktreeRootURL: URL
    ) -> GitFileChange? {
        guard record.hasPrefix("2 "),
              let originalPathRecord else {
            return nil
        }

        let fields = record.split(separator: " ", maxSplits: 9, omittingEmptySubsequences: false)
        guard fields.count == 10 else { return nil }

        let xy = String(fields[1])
        let relativePath = String(fields[9])
        return GitFileChange(
            url: worktreeRootURL.appending(path: relativePath),
            relativePath: relativePath,
            originalURL: worktreeRootURL.appending(path: originalPathRecord),
            originalRelativePath: originalPathRecord,
            indexStatus: statusCharacter(at: 0, in: xy),
            worktreeStatus: statusCharacter(at: 1, in: xy)
        )
    }

    private static func parseUnmergedChange(
        _ record: String,
        worktreeRootURL: URL
    ) -> GitFileChange? {
        guard record.hasPrefix("u ") else { return nil }

        let fields = record.split(separator: " ", maxSplits: 10, omittingEmptySubsequences: false)
        guard fields.count == 11 else { return nil }

        let xy = String(fields[1])
        let relativePath = String(fields[10])
        return GitFileChange(
            url: worktreeRootURL.appending(path: relativePath),
            relativePath: relativePath,
            indexStatus: statusCharacter(at: 0, in: xy),
            worktreeStatus: statusCharacter(at: 1, in: xy),
            isUnmerged: true
        )
    }

    private static func branchState(head: String?, oid: String?) -> GitBranchState? {
        guard let head else { return nil }

        if head == "(detached)" {
            let revision = oid.map { String($0.prefix(7)) } ?? ""
            return .detached(revision)
        }

        if oid == "(initial)" {
            return .unborn(head)
        }

        return .branch(head)
    }

    private static func statusCharacter(at offset: Int, in status: String) -> Character? {
        guard status.count > offset else { return nil }

        let index = status.index(status.startIndex, offsetBy: offset)
        let character = status[index]
        return character == "." || character == " " ? nil : character
    }
}

nonisolated private enum GitDiffNumstatOutputParser {
    static func parseChangedPaths(_ output: String) -> Set<String> {
        let records = output
            .split(separator: "\0", omittingEmptySubsequences: true)
            .map(String.init)
        var paths = Set<String>()
        var index = 0

        while index < records.count {
            let record = records[index]
            index += 1
            let fields = record.split(separator: "\t", omittingEmptySubsequences: false)
            guard fields.count >= 3 else { continue }

            let path = String(fields[2])
            if path.isEmpty {
                guard index + 1 < records.count else {
                    index = records.count
                    continue
                }
                paths.insert(records[index])
                paths.insert(records[index + 1])
                index += 2
            } else {
                paths.insert(path)
            }
        }

        return paths
    }
}

nonisolated private enum GitDiffOutputParser {
    static func parse(_ output: String) -> [SourceFileDiff] {
        let lines = output.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var diffs: [SourceFileDiff] = []
        var oldPath: String?
        var newPath: String?
        var hunks: [SourceDiffHunk] = []
        var hunkBuilder: HunkBuilder?

        func finishHunk() {
            if let hunk = hunkBuilder?.build() {
                hunks.append(hunk)
            }
            hunkBuilder = nil
        }

        func finishDiff() {
            finishHunk()
            guard oldPath != nil || newPath != nil else { return }

            diffs.append(
                SourceFileDiff(
                    oldRelativePath: oldPath,
                    newRelativePath: newPath,
                    hunks: hunks
                )
            )
            oldPath = nil
            newPath = nil
            hunks = []
        }

        for line in lines {
            if line.hasPrefix("diff --git ") {
                finishDiff()
                continue
            }

            if let header = parseHunkHeader(line) {
                finishHunk()
                hunkBuilder = HunkBuilder(header: header)
                continue
            }

            if hunkBuilder != nil {
                hunkBuilder?.append(line)
                continue
            }

            if let parsedOldPath = parseFileHeaderPath(line, marker: "--- ", prefix: "a/") {
                oldPath = parsedOldPath
                continue
            }

            if let parsedNewPath = parseFileHeaderPath(line, marker: "+++ ", prefix: "b/") {
                newPath = parsedNewPath
                continue
            }
        }

        finishDiff()
        return diffs
    }

    private static func parseFileHeaderPath(
        _ line: String,
        marker: String,
        prefix: String
    ) -> String?? {
        guard line.hasPrefix(marker) else { return nil }

        let rawPath = String(line.dropFirst(marker.count))
        guard rawPath != "/dev/null" else { return .some(nil) }

        if rawPath.hasPrefix(prefix) {
            return .some(String(rawPath.dropFirst(prefix.count)))
        }

        return .some(rawPath)
    }

    private static func parseHunkHeader(_ line: String) -> HunkHeader? {
        guard line.hasPrefix("@@ ") else { return nil }

        let fields = line.split(separator: " ", omittingEmptySubsequences: true)
        guard fields.count >= 3,
              let oldRange = parseRange(String(fields[1]), expectedPrefix: "-"),
              let newRange = parseRange(String(fields[2]), expectedPrefix: "+") else {
            return nil
        }

        return HunkHeader(
            oldStart: oldRange.start,
            oldLineCount: oldRange.count,
            newStart: newRange.start,
            newLineCount: newRange.count
        )
    }

    private static func parseRange(
        _ token: String,
        expectedPrefix: Character
    ) -> (start: Int, count: Int)? {
        guard token.first == expectedPrefix else { return nil }

        let body = token.dropFirst()
        let parts = body.split(separator: ",", maxSplits: 1, omittingEmptySubsequences: false)
        guard let start = Int(parts[0]) else { return nil }

        if parts.count == 2 {
            return Int(parts[1]).map { (start, $0) }
        }

        return (start, 1)
    }

    private struct HunkHeader {
        let oldStart: Int
        let oldLineCount: Int
        let newStart: Int
        let newLineCount: Int
    }

    private struct HunkBuilder {
        let header: HunkHeader
        var lines: [SourceDiffLine] = []
        var oldLineNumber: Int
        var newLineNumber: Int

        init(header: HunkHeader) {
            self.header = header
            oldLineNumber = max(1, header.oldStart)
            newLineNumber = max(1, header.newStart)
        }

        mutating func append(_ rawLine: String) {
            guard let marker = rawLine.first else { return }

            switch marker {
            case "+":
                lines.append(
                    SourceDiffLine(
                        kind: .addition,
                        oldLineNumber: nil,
                        newLineNumber: newLineNumber,
                        content: String(rawLine.dropFirst())
                    )
                )
                newLineNumber += 1

            case "-":
                lines.append(
                    SourceDiffLine(
                        kind: .deletion,
                        oldLineNumber: oldLineNumber,
                        newLineNumber: nil,
                        content: String(rawLine.dropFirst())
                    )
                )
                oldLineNumber += 1

            case " ":
                lines.append(
                    SourceDiffLine(
                        kind: .context,
                        oldLineNumber: oldLineNumber,
                        newLineNumber: newLineNumber,
                        content: String(rawLine.dropFirst())
                    )
                )
                oldLineNumber += 1
                newLineNumber += 1

            default:
                return
            }
        }

        func build() -> SourceDiffHunk {
            SourceDiffHunk(
                oldStart: header.oldStart,
                oldLineCount: header.oldLineCount,
                newStart: header.newStart,
                newLineCount: header.newLineCount,
                lines: lines
            )
        }
    }
}

private extension String {
    nonisolated func removingPrefix(_ prefix: String) -> String? {
        guard hasPrefix(prefix) else { return nil }
        return String(dropFirst(prefix.count))
    }
}

private extension Array {
    nonisolated subscript(safe index: Int) -> Element? {
        guard indices.contains(index) else { return nil }
        return self[index]
    }
}
