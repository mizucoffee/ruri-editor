//
//  GitHubPullRequestModelsTests.swift
//  ruriTests
//

import Foundation
import XCTest
@testable import ruri

final class GitHubPullRequestModelsTests: XCTestCase {
    private let pullRequestURL = URL(string: "https://github.com/owner/repo/pull/123")!

    // MARK: - GitHubPullRequestMergeableState

    func testMergeableStateMapsRawValues() {
        XCTAssertEqual(GitHubPullRequestMergeableState(rawValue: "MERGEABLE"), .mergeable)
        XCTAssertEqual(GitHubPullRequestMergeableState(rawValue: "CONFLICTING"), .conflicting)
        XCTAssertEqual(GitHubPullRequestMergeableState(rawValue: "UNKNOWN"), .unknown)
        XCTAssertEqual(GitHubPullRequestMergeableState(rawValue: "mergeable"), .mergeable)
        XCTAssertEqual(GitHubPullRequestMergeableState(rawValue: " conflicting \n"), .conflicting)
        XCTAssertEqual(GitHubPullRequestMergeableState(rawValue: ""), .unknown)
        XCTAssertEqual(GitHubPullRequestMergeableState(rawValue: "SOMETHING_NEW"), .unknown)
    }

    func testMergeableStateIsDeterminate() {
        XCTAssertTrue(GitHubPullRequestMergeableState.mergeable.isDeterminate)
        XCTAssertTrue(GitHubPullRequestMergeableState.conflicting.isDeterminate)
        XCTAssertFalse(GitHubPullRequestMergeableState.unknown.isDeterminate)
    }

    // MARK: - displayStateDescription / showsConflicts

    func testDisplayStateDescriptionAppendsConflictsForOpenConflictingPullRequest() {
        let pullRequest = GitHubPullRequestInfo(
            number: 123,
            url: pullRequestURL,
            lifecycleState: .open,
            mergeableState: .conflicting
        )

        XCTAssertTrue(pullRequest.showsConflicts)
        XCTAssertEqual(pullRequest.displayStateDescription, "Open, Conflicts")
    }

    func testDisplayStateDescriptionAppendsConflictsAfterDraft() {
        let pullRequest = GitHubPullRequestInfo(
            number: 123,
            url: pullRequestURL,
            isDraft: true,
            lifecycleState: .open,
            mergeableState: .conflicting
        )

        XCTAssertEqual(pullRequest.displayStateDescription, "Draft, Open, Conflicts")
    }

    func testDisplayStateDescriptionOmitsConflictsForMergeableAndUnknown() {
        for state in [GitHubPullRequestMergeableState.mergeable, .unknown] {
            let pullRequest = GitHubPullRequestInfo(
                number: 123,
                url: pullRequestURL,
                lifecycleState: .open,
                mergeableState: state
            )

            XCTAssertFalse(pullRequest.showsConflicts)
            XCTAssertEqual(pullRequest.displayStateDescription, "Open")
        }
    }

    func testShowsConflictsIsFalseForClosedAndMergedPullRequests() {
        for lifecycleState in [GitHubPullRequestLifecycleState.closed, .merged] {
            let pullRequest = GitHubPullRequestInfo(
                number: 123,
                url: pullRequestURL,
                lifecycleState: lifecycleState,
                mergeableState: .conflicting
            )

            XCTAssertFalse(pullRequest.showsConflicts)
        }
    }

    // MARK: - preservingDeterminateMergeableState

    private func status(
        number: Int = 123,
        mergeableState: GitHubPullRequestMergeableState
    ) -> GitHubPullRequestStatus {
        .pullRequest(GitHubPullRequestInfo(
            number: number,
            url: pullRequestURL,
            lifecycleState: .open,
            mergeableState: mergeableState
        ))
    }

    func testPreservingKeepsPreviousDeterminateStateWhenNewIsUnknown() {
        let resolved = status(mergeableState: .unknown)
            .preservingDeterminateMergeableState(from: status(mergeableState: .conflicting))

        XCTAssertEqual(resolved, status(mergeableState: .conflicting))
    }

    func testPreservingDoesNotInheritAcrossDifferentPullRequestNumbers() {
        let resolved = status(number: 124, mergeableState: .unknown)
            .preservingDeterminateMergeableState(from: status(number: 123, mergeableState: .mergeable))

        XCTAssertEqual(resolved, status(number: 124, mergeableState: .unknown))
    }

    func testPreservingKeepsUnknownWhenPreviousIsNil() {
        let resolved = status(mergeableState: .unknown)
            .preservingDeterminateMergeableState(from: nil)

        XCTAssertEqual(resolved, status(mergeableState: .unknown))
    }

    func testPreservingPrefersNewDeterminateState() {
        let resolved = status(mergeableState: .mergeable)
            .preservingDeterminateMergeableState(from: status(mergeableState: .conflicting))

        XCTAssertEqual(resolved, status(mergeableState: .mergeable))
    }

    func testPreservingKeepsUnknownWhenPreviousIsAlsoUnknown() {
        let resolved = status(mergeableState: .unknown)
            .preservingDeterminateMergeableState(from: status(mergeableState: .unknown))

        XCTAssertEqual(resolved, status(mergeableState: .unknown))
    }

    func testPreservingPassesThroughCreateStatus() {
        let creationStatus = GitHubPullRequestStatus.create(GitHubPullRequestCreationLink(
            baseBranch: "main",
            headBranch: "feature/status-pr",
            url: URL(string: "https://github.com/owner/repo/compare/main...feature/status-pr?expand=1")!
        ))

        let resolved = creationStatus
            .preservingDeterminateMergeableState(from: status(mergeableState: .conflicting))

        XCTAssertEqual(resolved, creationStatus)
    }
}
