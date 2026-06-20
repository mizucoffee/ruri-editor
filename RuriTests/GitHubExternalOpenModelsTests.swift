//
//  GitHubExternalOpenModelsTests.swift
//  ruriTests
//

import XCTest
@testable import ruri

final class GitHubExternalOpenModelsTests: XCTestCase {
    func testParsesRuriGitHubPullRequestURL() {
        let reference = GitHubExternalURLParser.pullRequestReference(
            from: URL(string: "ruri://github.com/owner/repo/pull/123")!
        )

        XCTAssertEqual(reference?.repository, GitHubRepositoryIdentity(owner: "owner", name: "repo"))
        XCTAssertEqual(reference?.number, 123)
    }

    func testRejectsNonPullRequestURLs() {
        XCTAssertNil(GitHubExternalURLParser.pullRequestReference(
            from: URL(string: "https://github.com/owner/repo/pull/123")!
        ))
        XCTAssertNil(GitHubExternalURLParser.pullRequestReference(
            from: URL(string: "ruri://github.com/owner/repo/issues/123")!
        ))
        XCTAssertNil(GitHubExternalURLParser.pullRequestReference(
            from: URL(string: "ruri://github.com/owner/repo/pull/not-a-number")!
        ))
    }

    func testParsesGitHubRemoteURLs() {
        let identities = GitHubRemoteListOutputParser.parse("""
        origin\thttps://github.com/Owner/Repo.git (fetch)
        origin\thttps://github.com/Owner/Repo.git (push)
        upstream\tgit@github.com:other/project.git (fetch)
        local\tfile:///tmp/repo.git (fetch)
        """)

        XCTAssertEqual(identities, [
            GitHubRepositoryIdentity(owner: "Owner", name: "Repo"),
            GitHubRepositoryIdentity(owner: "other", name: "project")
        ])
    }
}
