//
//  ProjectTreeStateTests.swift
//  ruriTests
//

import XCTest
@testable import ruri

final class ProjectTreeStateTests: XCTestCase {
    func testToggleDirectoryRequestsChildrenTheFirstTime() {
        let directoryURL = URL(filePath: "/tmp/project/Sources")
        var state = ProjectTreeState()
        state.replaceRootChildren([
            FileNode(url: directoryURL, name: "Sources", isDirectory: true)
        ])

        let result = state.toggleDirectory(at: directoryURL)

        XCTAssertEqual(result, .needsChildren(directoryURL))
        XCTAssertTrue(state.fileTree[0].isExpanded)
        XCTAssertTrue(state.fileTree[0].isLoadingChildren)
    }

    func testFinishLoadingChildrenStoresChildrenAndClearsLoading() {
        let directoryURL = URL(filePath: "/tmp/project/Sources")
        let childURL = directoryURL.appending(path: "App.swift")
        var state = ProjectTreeState()
        state.replaceRootChildren([
            FileNode(url: directoryURL, name: "Sources", isDirectory: true)
        ])

        _ = state.toggleDirectory(at: directoryURL)
        state.finishLoadingChildren([
            FileNode(url: childURL, name: "App.swift", isDirectory: false)
        ], for: directoryURL)

        XCTAssertEqual(state.fileTree[0].children?.map(\.name), ["App.swift"])
        XCTAssertTrue(state.fileTree[0].isExpanded)
        XCTAssertFalse(state.fileTree[0].isLoadingChildren)
    }

    func testChainedExpansionCandidateReturnsSingleDirectoryChild() {
        let directoryURL = URL(filePath: "/tmp/project/Sources")
        let childURL = directoryURL.appending(path: "Main")
        var state = ProjectTreeState()
        state.replaceRootChildren([
            FileNode(
                url: directoryURL,
                name: "Sources",
                isDirectory: true,
                children: [
                    FileNode(url: childURL, name: "Main", isDirectory: true)
                ],
                isExpanded: true
            )
        ])

        XCTAssertEqual(state.chainedExpansionCandidate(afterExpanding: directoryURL), childURL)
    }

    func testChainedExpansionCandidateIgnoresNonSingleDirectoryContents() {
        let rootURL = URL(filePath: "/tmp/project")
        let emptyURL = rootURL.appending(path: "Empty")
        let fileOnlyURL = rootURL.appending(path: "FileOnly")
        let mixedURL = rootURL.appending(path: "Mixed")
        let multipleURL = rootURL.appending(path: "Multiple")
        let alreadyExpandedURL = rootURL.appending(path: "AlreadyExpanded")
        var state = ProjectTreeState()
        state.replaceRootChildren([
            FileNode(
                url: emptyURL,
                name: "Empty",
                isDirectory: true,
                children: [],
                isExpanded: true
            ),
            FileNode(
                url: fileOnlyURL,
                name: "FileOnly",
                isDirectory: true,
                children: [
                    FileNode(
                        url: fileOnlyURL.appending(path: "README.md"),
                        name: "README.md",
                        isDirectory: false
                    )
                ],
                isExpanded: true
            ),
            FileNode(
                url: mixedURL,
                name: "Mixed",
                isDirectory: true,
                children: [
                    FileNode(url: mixedURL.appending(path: "Nested"), name: "Nested", isDirectory: true),
                    FileNode(url: mixedURL.appending(path: "README.md"), name: "README.md", isDirectory: false)
                ],
                isExpanded: true
            ),
            FileNode(
                url: multipleURL,
                name: "Multiple",
                isDirectory: true,
                children: [
                    FileNode(url: multipleURL.appending(path: "First"), name: "First", isDirectory: true),
                    FileNode(url: multipleURL.appending(path: "Second"), name: "Second", isDirectory: true)
                ],
                isExpanded: true
            ),
            FileNode(
                url: alreadyExpandedURL,
                name: "AlreadyExpanded",
                isDirectory: true,
                children: [
                    FileNode(
                        url: alreadyExpandedURL.appending(path: "Nested"),
                        name: "Nested",
                        isDirectory: true,
                        children: [],
                        isExpanded: true
                    )
                ],
                isExpanded: true
            )
        ])

        XCTAssertNil(state.chainedExpansionCandidate(afterExpanding: emptyURL))
        XCTAssertNil(state.chainedExpansionCandidate(afterExpanding: fileOnlyURL))
        XCTAssertNil(state.chainedExpansionCandidate(afterExpanding: mixedURL))
        XCTAssertNil(state.chainedExpansionCandidate(afterExpanding: multipleURL))
        XCTAssertNil(state.chainedExpansionCandidate(afterExpanding: alreadyExpandedURL))
    }

    func testToggleLoadedDirectoryCollapsesWithoutDiscardingChildren() {
        let directoryURL = URL(filePath: "/tmp/project/Sources")
        let childURL = directoryURL.appending(path: "App.swift")
        var state = ProjectTreeState()
        state.replaceRootChildren([
            FileNode(
                url: directoryURL,
                name: "Sources",
                isDirectory: true,
                children: [
                    FileNode(url: childURL, name: "App.swift", isDirectory: false)
                ],
                isExpanded: true
            )
        ])

        let result = state.toggleDirectory(at: directoryURL)

        XCTAssertEqual(result, .updated)
        XCTAssertFalse(state.fileTree[0].isExpanded)
        XCTAssertEqual(state.fileTree[0].children?.count, 1)
    }

    func testSelectionMovesThroughVisibleNodes() {
        let directoryURL = URL(filePath: "/tmp/project/Sources")
        let childURL = directoryURL.appending(path: "App.swift")
        let readmeURL = URL(filePath: "/tmp/project/README.md")
        var state = ProjectTreeState()
        state.replaceRootChildren([
            FileNode(
                url: directoryURL,
                name: "Sources",
                isDirectory: true,
                children: [
                    FileNode(url: childURL, name: "App.swift", isDirectory: false)
                ],
                isExpanded: true
            ),
            FileNode(url: readmeURL, name: "README.md", isDirectory: false)
        ])

        XCTAssertEqual(state.moveSelection(by: 1), directoryURL)
        XCTAssertEqual(state.moveSelection(by: 1), childURL)
        XCTAssertEqual(state.moveSelection(by: 1), readmeURL)
        XCTAssertEqual(state.moveSelection(by: 1), readmeURL)
        XCTAssertEqual(state.moveSelection(by: -1), childURL)
    }

    func testChangedFilesOnlyFiltersCleanNodesAndKeepsChangedAncestors() throws {
        let rootURL = URL(filePath: "/tmp/project")
        let sourcesURL = rootURL.appending(path: "Sources")
        let changedURL = sourcesURL.appending(path: "Changed.swift")
        let cleanURL = sourcesURL.appending(path: "Clean.swift")
        let readmeURL = rootURL.appending(path: "README.md")
        let snapshot = makeGitSnapshot(
            rootURL: rootURL,
            changes: [
                GitFileChange(
                    url: changedURL,
                    relativePath: "Sources/Changed.swift",
                    worktreeStatus: "M"
                )
            ]
        )
        var state = ProjectTreeState()
        state.reset(to: rootURL)
        state.replaceRootChildren([
            FileNode(
                url: sourcesURL,
                name: "Sources",
                isDirectory: true,
                children: [
                    FileNode(url: cleanURL, name: "Clean.swift", isDirectory: false),
                    FileNode(url: changedURL, name: "Changed.swift", isDirectory: false)
                ],
                isExpanded: true
            ),
            FileNode(url: readmeURL, name: "README.md", isDirectory: false)
        ])

        state.setShowsChangedFilesOnly(true, gitSnapshot: snapshot)

        let filteredRoot = state.displayFileTree(gitSnapshot: snapshot)
        XCTAssertEqual(filteredRoot.map(\.name), ["Sources"])
        let sourcesNode = try XCTUnwrap(filteredRoot.first)
        XCTAssertEqual(sourcesNode.children?.map(\.name), ["Changed.swift"])
        XCTAssertFalse(state.selectNode(at: cleanURL, gitSnapshot: snapshot))
        XCTAssertEqual(state.moveSelection(by: 1, gitSnapshot: snapshot), sourcesURL)
        XCTAssertEqual(state.moveSelection(by: 1, gitSnapshot: snapshot), changedURL)
    }

    func testChangedFilesOnlyKeepsDirectoryWithSyntheticDeletedDescendant() throws {
        let rootURL = URL(filePath: "/tmp/project")
        let sourcesURL = rootURL.appending(path: "Sources")
        let cleanURL = sourcesURL.appending(path: "Clean.swift")
        let deletedURL = sourcesURL.appending(path: "Deleted.swift")
        let snapshot = makeGitSnapshot(
            rootURL: rootURL,
            changes: [
                GitFileChange(
                    url: deletedURL,
                    relativePath: "Sources/Deleted.swift",
                    worktreeStatus: "D"
                )
            ]
        )
        var state = ProjectTreeState()
        state.reset(to: rootURL)
        state.replaceRootChildren([
            FileNode(
                url: sourcesURL,
                name: "Sources",
                isDirectory: true,
                children: [
                    FileNode(url: cleanURL, name: "Clean.swift", isDirectory: false)
                ],
                isExpanded: true
            )
        ])

        state.setShowsChangedFilesOnly(true, gitSnapshot: snapshot)

        let sourcesNode = try XCTUnwrap(state.displayFileTree(gitSnapshot: snapshot).first)
        XCTAssertEqual(sourcesNode.name, "Sources")
        XCTAssertEqual(sourcesNode.children?.map(\.name), [])
        XCTAssertEqual(
            snapshot.deletedChanges(in: sourcesURL, excluding: Set(sourcesNode.children?.map(\.url) ?? []))
                .map(\.url),
            [deletedURL.standardizedFileURL]
        )
    }

    func testChangedFilesOnlyPreservesIgnoredFlagOnIncludedNodes() throws {
        let rootURL = URL(filePath: "/tmp/project")
        let generatedURL = rootURL.appending(path: "Generated.swift")
        let snapshot = makeGitSnapshot(
            rootURL: rootURL,
            changes: [
                GitFileChange(
                    url: generatedURL,
                    relativePath: "Generated.swift",
                    worktreeStatus: "M"
                )
            ]
        )
        var state = ProjectTreeState()
        state.reset(to: rootURL)
        state.replaceRootChildren([
            FileNode(
                url: generatedURL,
                name: "Generated.swift",
                isDirectory: false,
                isIgnored: true
            )
        ])

        state.setShowsChangedFilesOnly(true, gitSnapshot: snapshot)

        XCTAssertTrue(try XCTUnwrap(state.displayFileTree(gitSnapshot: snapshot).first).isIgnored)
    }

    func testDirectorySelectionExpandsThenMovesToFirstChild() {
        let directoryURL = URL(filePath: "/tmp/project/Sources")
        let childURL = directoryURL.appending(path: "App.swift")
        var state = ProjectTreeState()
        state.replaceRootChildren([
            FileNode(
                url: directoryURL,
                name: "Sources",
                isDirectory: true,
                children: [
                    FileNode(url: childURL, name: "App.swift", isDirectory: false)
                ]
            )
        ])

        XCTAssertTrue(state.selectNode(at: directoryURL))
        XCTAssertEqual(state.expandSelectedDirectoryOrSelectFirstChild(), .updated)
        XCTAssertTrue(state.fileTree[0].isExpanded)
        XCTAssertEqual(state.selectedURL, directoryURL)

        XCTAssertEqual(state.expandSelectedDirectoryOrSelectFirstChild(), .updated)
        XCTAssertEqual(state.selectedURL, childURL)
    }

    func testCollapseSelectionMovesToParentThenCollapsesDirectory() {
        let directoryURL = URL(filePath: "/tmp/project/Sources")
        let childURL = directoryURL.appending(path: "App.swift")
        var state = ProjectTreeState()
        state.replaceRootChildren([
            FileNode(
                url: directoryURL,
                name: "Sources",
                isDirectory: true,
                children: [
                    FileNode(url: childURL, name: "App.swift", isDirectory: false)
                ],
                isExpanded: true
            )
        ])

        XCTAssertTrue(state.selectNode(at: childURL))
        XCTAssertEqual(state.collapseSelectedDirectoryOrSelectParent(), .updated)
        XCTAssertEqual(state.selectedURL, directoryURL)

        XCTAssertEqual(state.collapseSelectedDirectoryOrSelectParent(), .updated)
        XCTAssertFalse(state.fileTree[0].isExpanded)
        XCTAssertEqual(state.selectedURL, directoryURL)
    }

    func testExpandDirectoryIfNeededDoesNotCollapseExpandedDirectory() {
        let directoryURL = URL(filePath: "/tmp/project/Sources")
        let childURL = directoryURL.appending(path: "App.swift")
        var state = ProjectTreeState()
        state.replaceRootChildren([
            FileNode(
                url: directoryURL,
                name: "Sources",
                isDirectory: true,
                children: [
                    FileNode(url: childURL, name: "App.swift", isDirectory: false)
                ],
                isExpanded: true
            )
        ])

        XCTAssertEqual(state.expandDirectoryIfNeeded(at: directoryURL), .updated)
        XCTAssertTrue(state.fileTree[0].isExpanded)
        XCTAssertEqual(state.fileTree[0].children?.map(\.name), ["App.swift"])
    }

    func testRenameDirectoryRewritesLoadedDescendantURLsAndSelection() throws {
        let directoryURL = URL(filePath: "/tmp/project/Sources")
        let childURL = directoryURL.appending(path: "App.swift")
        let renamedDirectoryURL = URL(filePath: "/tmp/project/Core")
        let renamedChildURL = renamedDirectoryURL.appending(path: "App.swift").standardizedFileURL
        var state = ProjectTreeState()
        state.replaceRootChildren([
            FileNode(
                url: directoryURL,
                name: "Sources",
                isDirectory: true,
                children: [
                    FileNode(url: childURL, name: "App.swift", isDirectory: false)
                ],
                isExpanded: true
            )
        ])

        XCTAssertTrue(state.selectNode(at: childURL))
        XCTAssertTrue(state.renameNode(at: directoryURL, to: renamedDirectoryURL))

        let renamedDirectory = state.fileTree[0]
        XCTAssertEqual(renamedDirectory.url, renamedDirectoryURL.standardizedFileURL)
        XCTAssertEqual(renamedDirectory.name, "Core")
        XCTAssertEqual(try XCTUnwrap(renamedDirectory.children?.first).url, renamedChildURL)
        XCTAssertEqual(state.selectedURL, renamedChildURL)
    }

    func testRenameDirectoryPreservesIgnoredFlags() throws {
        let directoryURL = URL(filePath: "/tmp/project/Build")
        let childURL = directoryURL.appending(path: "Generated.swift")
        let renamedDirectoryURL = URL(filePath: "/tmp/project/Output")
        var state = ProjectTreeState()
        state.replaceRootChildren([
            FileNode(
                url: directoryURL,
                name: "Build",
                isDirectory: true,
                children: [
                    FileNode(
                        url: childURL,
                        name: "Generated.swift",
                        isDirectory: false,
                        isIgnored: true
                    )
                ],
                isExpanded: true,
                isIgnored: true
            )
        ])

        XCTAssertTrue(state.renameNode(at: directoryURL, to: renamedDirectoryURL))

        let renamedDirectory = try XCTUnwrap(state.node(at: renamedDirectoryURL))
        XCTAssertTrue(renamedDirectory.isIgnored)
        XCTAssertTrue(try XCTUnwrap(renamedDirectory.children?.first).isIgnored)
    }

    func testRefreshLoadedDirectoriesPreservesExpandedDirectoriesOnly() throws {
        let rootURL = URL(filePath: "/tmp/project")
        let sourcesURL = rootURL.appending(path: "Sources")
        let nestedURL = sourcesURL.appending(path: "Nested")
        let collapsedURL = rootURL.appending(path: "Collapsed")
        let packageURL = rootURL.appending(path: "Package.swift")
        let appURL = sourcesURL.appending(path: "App.swift")
        let oldURL = sourcesURL.appending(path: "Old.swift")
        let staleURL = collapsedURL.appending(path: "Stale.swift")
        var state = ProjectTreeState()
        state.reset(to: rootURL)
        state.replaceRootChildren([
            FileNode(
                url: sourcesURL,
                name: "Sources",
                isDirectory: true,
                children: [
                    FileNode(url: oldURL, name: "Old.swift", isDirectory: false)
                ],
                isExpanded: true
            ),
            FileNode(
                url: nestedURL,
                name: "Nested",
                isDirectory: true
            ),
            FileNode(
                url: collapsedURL,
                name: "Collapsed",
                isDirectory: true,
                children: [
                    FileNode(url: staleURL, name: "Stale.swift", isDirectory: false)
                ],
                isExpanded: false
            )
        ])
        XCTAssertTrue(state.selectNode(at: oldURL))

        XCTAssertEqual(state.refreshDirectoryURLs(), [rootURL, sourcesURL])

        state.refreshLoadedDirectories([
            rootURL: [
                FileNode(url: sourcesURL, name: "Sources", isDirectory: true),
                FileNode(url: collapsedURL, name: "Collapsed", isDirectory: true),
                FileNode(url: nestedURL, name: "Nested", isDirectory: true),
                FileNode(url: packageURL, name: "Package.swift", isDirectory: false)
            ],
            sourcesURL: [
                FileNode(url: appURL, name: "App.swift", isDirectory: false)
            ]
        ])

        XCTAssertEqual(state.fileTree.map(\.name), ["Collapsed", "Nested", "Sources", "Package.swift"])
        let sourcesNode = try XCTUnwrap(state.node(at: sourcesURL))
        let nestedNode = try XCTUnwrap(state.node(at: nestedURL))
        let collapsedNode = try XCTUnwrap(state.node(at: collapsedURL))
        XCTAssertTrue(sourcesNode.isExpanded)
        XCTAssertEqual(sourcesNode.children?.map(\.name), ["App.swift"])
        XCTAssertFalse(nestedNode.isExpanded)
        XCTAssertNil(nestedNode.children)
        XCTAssertFalse(collapsedNode.isExpanded)
        XCTAssertNil(collapsedNode.children)
        XCTAssertNil(state.selectedURL)
    }

    func testRefreshLoadedDirectoriesUpdatesIgnoredFlags() throws {
        let rootURL = URL(filePath: "/tmp/project")
        let buildURL = rootURL.appending(path: "Build")
        var state = ProjectTreeState()
        state.reset(to: rootURL)
        state.replaceRootChildren([
            FileNode(
                url: buildURL,
                name: "Build",
                isDirectory: true,
                isIgnored: false
            )
        ])

        state.refreshLoadedDirectories([
            rootURL: [
                FileNode(
                    url: buildURL,
                    name: "Build",
                    isDirectory: true,
                    isIgnored: true
                )
            ]
        ])

        XCTAssertTrue(try XCTUnwrap(state.node(at: buildURL)).isIgnored)
    }

    func testRefreshLoadedDirectoriesAppliesNestedSnapshotWithoutIntermediateSnapshot() throws {
        let rootURL = URL(filePath: "/tmp/project")
        let outerURL = rootURL.appending(path: "Outer")
        let innerURL = outerURL.appending(path: "Inner")
        let oldURL = innerURL.appending(path: "Old.swift")
        let newURL = innerURL.appending(path: "New.swift")
        var state = ProjectTreeState()
        state.reset(to: rootURL)
        state.replaceRootChildren([
            FileNode(
                url: outerURL,
                name: "Outer",
                isDirectory: true,
                children: [
                    FileNode(
                        url: innerURL,
                        name: "Inner",
                        isDirectory: true,
                        children: [
                            FileNode(url: oldURL, name: "Old.swift", isDirectory: false)
                        ],
                        isExpanded: true
                    )
                ],
                isExpanded: true
            )
        ])

        state.refreshLoadedDirectories([
            rootURL: [
                FileNode(url: outerURL, name: "Outer", isDirectory: true)
            ],
            innerURL: [
                FileNode(url: newURL, name: "New.swift", isDirectory: false)
            ]
        ])

        let outerNode = try XCTUnwrap(state.node(at: outerURL))
        let innerNode = try XCTUnwrap(state.node(at: innerURL))
        XCTAssertTrue(outerNode.isExpanded)
        XCTAssertTrue(innerNode.isExpanded)
        XCTAssertEqual(innerNode.children?.map(\.name), ["New.swift"])
    }

    func testRefreshLoadedDirectoriesKeepsCachedChildrenInPreservedSubtree() throws {
        let rootURL = URL(filePath: "/tmp/project")
        let outerURL = rootURL.appending(path: "Outer")
        let collapsedURL = outerURL.appending(path: "Collapsed")
        let cachedURL = collapsedURL.appending(path: "Cached.swift")
        var state = ProjectTreeState()
        state.reset(to: rootURL)
        state.replaceRootChildren([
            FileNode(
                url: outerURL,
                name: "Outer",
                isDirectory: true,
                children: [
                    FileNode(
                        url: collapsedURL,
                        name: "Collapsed",
                        isDirectory: true,
                        children: [
                            FileNode(url: cachedURL, name: "Cached.swift", isDirectory: false)
                        ],
                        isExpanded: false
                    )
                ],
                isExpanded: true
            )
        ])

        state.refreshLoadedDirectories([
            rootURL: [
                FileNode(url: outerURL, name: "Outer", isDirectory: true)
            ]
        ])

        let collapsedNode = try XCTUnwrap(state.node(at: collapsedURL))
        XCTAssertFalse(collapsedNode.isExpanded)
        XCTAssertEqual(collapsedNode.children?.map(\.name), ["Cached.swift"])
    }

    private func makeGitSnapshot(rootURL: URL, changes: [GitFileChange]) -> GitRepositorySnapshot {
        GitRepositorySnapshot(
            repositoryRootURL: rootURL,
            worktreeRootURL: rootURL,
            openedRootURL: rootURL,
            gitDirectoryURL: rootURL.appending(path: ".git", directoryHint: .isDirectory),
            gitCommonDirectoryURL: rootURL.appending(path: ".git", directoryHint: .isDirectory),
            worktreeKind: .main,
            worktreeRootURLs: [rootURL],
            branch: .branch("main"),
            changesByURL: Dictionary(uniqueKeysWithValues: changes.map { ($0.url, $0) }),
            diffsByURL: [:]
        )
    }
}
