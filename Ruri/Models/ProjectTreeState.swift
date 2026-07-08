//
//  ProjectTreeState.swift
//  ruri
//

import Foundation

struct ProjectTreeState {
    enum ToggleResult: Equatable {
        case updated
        case needsChildren(URL)
        case notFound
    }

    private struct VisibleNode {
        let node: FileNode
        let parentURL: URL?
    }

    private struct DirectoryState {
        let node: FileNode
        let isExpanded: Bool
        let isLoadingChildren: Bool
    }

    private(set) var projectURL: URL?
    private(set) var fileTree: [FileNode] = []
    private(set) var selectedURL: URL?
    private(set) var showsChangedFilesOnly = false

    mutating func reset(to url: URL?) {
        projectURL = url
        fileTree = []
        selectedURL = nil
        showsChangedFilesOnly = false
    }

    mutating func setShowsChangedFilesOnly(_ isEnabled: Bool, gitSnapshot: GitRepositorySnapshot?) {
        showsChangedFilesOnly = isEnabled
        repairSelection(gitSnapshot: gitSnapshot)
    }

    func displayFileTree(gitSnapshot: GitRepositorySnapshot?) -> [FileNode] {
        guard showsChangedFilesOnly,
              let gitSnapshot else {
            return fileTree
        }

        return filteredChangedNodes(fileTree, gitSnapshot: gitSnapshot)
    }

    func selectedDisplayURL(gitSnapshot: GitRepositorySnapshot?) -> URL? {
        guard let selectedURL else { return nil }

        return visibleNodes(gitSnapshot: gitSnapshot).first {
            FileURLRewriter.urlsMatch($0.node.url, selectedURL)
        }?.node.url
    }

    mutating func replaceRootChildren(_ nodes: [FileNode]) {
        fileTree = nodes
        repairSelection(gitSnapshot: nil)
    }

    func refreshDirectoryURLs() -> [URL] {
        guard let projectURL else { return [] }

        return [projectURL] + expandedDirectoryURLs(in: fileTree)
    }

    mutating func refreshLoadedDirectories(_ childrenByDirectoryURL: [URL: [FileNode]]) {
        guard let projectURL else {
            fileTree = []
            selectedURL = nil
            return
        }

        let childrenByPath = Dictionary(
            uniqueKeysWithValues: childrenByDirectoryURL.map {
                (FileURLRewriter.normalizedPath($0.key), $0.value)
            }
        )
        let directoryStates = directoryStates(in: fileTree)
        let rootPath = FileURLRewriter.normalizedPath(projectURL)

        guard let rootChildren = childrenByPath[rootPath] else {
            fileTree = []
            repairSelection(gitSnapshot: nil)
            return
        }

        fileTree = Self.refreshedNodes(
            rootChildren,
            childrenByPath: childrenByPath,
            directoryStates: directoryStates
        )
        repairSelection(gitSnapshot: nil)
    }

    mutating func toggleDirectory(at url: URL, gitSnapshot: GitRepositorySnapshot? = nil) -> ToggleResult {
        let result = updateNode(at: url) { node in
            guard node.isDirectory else { return .notFound }

            if node.isExpanded {
                node.isExpanded = false
                return .updated
            }

            node.isExpanded = true

            if node.children == nil {
                node.isLoadingChildren = true
                return .needsChildren(url)
            }

            return .updated
        } ?? .notFound

        repairSelection(gitSnapshot: gitSnapshot)
        return result
    }

    mutating func expandDirectoryIfNeeded(
        at url: URL,
        gitSnapshot: GitRepositorySnapshot? = nil
    ) -> ToggleResult {
        let result = updateNode(at: url) { node in
            guard node.isDirectory else { return .notFound }

            if node.isExpanded {
                return .updated
            }

            node.isExpanded = true

            if node.children == nil {
                node.isLoadingChildren = true
                return .needsChildren(url)
            }

            return .updated
        } ?? .notFound

        repairSelection(gitSnapshot: gitSnapshot)
        return result
    }

    mutating func finishLoadingChildren(_ children: [FileNode], for url: URL) {
        _ = updateNode(at: url) { node in
            guard node.isDirectory else { return ToggleResult.notFound }
            node.children = children
            node.isExpanded = true
            node.isLoadingChildren = false
            return .updated
        }
        repairSelection(gitSnapshot: nil)
    }

    mutating func failLoadingChildren(for url: URL) {
        _ = updateNode(at: url) { node in
            guard node.isDirectory else { return ToggleResult.notFound }
            node.isLoadingChildren = false
            node.isExpanded = false
            return .updated
        }
        repairSelection(gitSnapshot: nil)
    }

    @discardableResult
    mutating func selectNode(at url: URL, gitSnapshot: GitRepositorySnapshot? = nil) -> Bool {
        guard let visibleNode = visibleNodes(gitSnapshot: gitSnapshot).first(where: {
            FileURLRewriter.urlsMatch($0.node.url, url)
        }) else {
            return false
        }

        selectedURL = visibleNode.node.url
        return true
    }

    @discardableResult
    mutating func moveSelection(by offset: Int, gitSnapshot: GitRepositorySnapshot? = nil) -> URL? {
        let visibleNodes = visibleNodes(gitSnapshot: gitSnapshot)
        guard !visibleNodes.isEmpty else {
            selectedURL = nil
            return nil
        }

        guard let selectedURL,
              let currentIndex = visibleNodes.firstIndex(where: { FileURLRewriter.urlsMatch($0.node.url, selectedURL) }) else {
            selectedURL = offset < 0 ? visibleNodes[visibleNodes.count - 1].node.url : visibleNodes[0].node.url
            return selectedURL
        }

        let nextIndex = min(max(currentIndex + offset, 0), visibleNodes.count - 1)
        self.selectedURL = visibleNodes[nextIndex].node.url
        return self.selectedURL
    }

    mutating func expandSelectedDirectoryOrSelectFirstChild(
        gitSnapshot: GitRepositorySnapshot? = nil
    ) -> ToggleResult {
        guard let selectedURL,
              let visibleNode = visibleNodes(gitSnapshot: gitSnapshot).first(where: {
                FileURLRewriter.urlsMatch($0.node.url, selectedURL)
              }),
              visibleNode.node.isDirectory else {
            return .notFound
        }

        if !visibleNode.node.isExpanded {
            return toggleDirectory(at: selectedURL, gitSnapshot: gitSnapshot)
        }

        if let firstChild = visibleNodes(gitSnapshot: gitSnapshot).first(where: {
            $0.parentURL.map { FileURLRewriter.urlsMatch($0, selectedURL) } == true
        }) {
            self.selectedURL = firstChild.node.url
        }

        return .updated
    }

    mutating func collapseSelectedDirectoryOrSelectParent(
        gitSnapshot: GitRepositorySnapshot? = nil
    ) -> ToggleResult {
        guard let selectedURL,
              let visibleNode = visibleNodes(gitSnapshot: gitSnapshot).first(where: {
                FileURLRewriter.urlsMatch($0.node.url, selectedURL)
              }) else {
            return .notFound
        }

        if visibleNode.node.isDirectory, visibleNode.node.isExpanded {
            return toggleDirectory(at: selectedURL, gitSnapshot: gitSnapshot)
        }

        if let parentURL = visibleNode.parentURL {
            self.selectedURL = parentURL
        }

        return .updated
    }

    func node(at url: URL) -> FileNode? {
        node(in: fileTree, at: url)
    }

    func selectedNode() -> FileNode? {
        selectedURL.flatMap { node(at: $0) }
    }

    func chainedExpansionCandidate(afterExpanding url: URL) -> URL? {
        guard let node = node(at: url),
              node.isDirectory,
              node.isExpanded,
              !node.isLoadingChildren,
              let children = node.children,
              children.count == 1,
              let child = children.first,
              child.isDirectory,
              !child.isExpanded,
              !child.isLoadingChildren else {
            return nil
        }

        return child.url
    }

    @discardableResult
    mutating func renameNode(at oldURL: URL, to newURL: URL) -> Bool {
        guard Self.renameNode(in: &fileTree, oldURL: oldURL, newURL: newURL) else {
            return false
        }

        if let selectedURL,
           let rewrittenSelectedURL = FileURLRewriter.rewrittenURL(
            selectedURL,
            replacing: oldURL,
            with: newURL
           ) {
            self.selectedURL = rewrittenSelectedURL
        }

        fileTree = Self.sortedNodes(fileTree)
        repairSelection(gitSnapshot: nil)
        return true
    }

    private mutating func updateNode(
        at url: URL,
        update: (inout FileNode) -> ToggleResult
    ) -> ToggleResult? {
        updateNode(in: &fileTree, at: url, update: update)
    }

    private func updateNode(
        in nodes: inout [FileNode],
        at url: URL,
        update: (inout FileNode) -> ToggleResult
    ) -> ToggleResult? {
        for index in nodes.indices {
            if FileURLRewriter.urlsMatch(nodes[index].url, url) {
                return update(&nodes[index])
            }

            if nodes[index].isDirectory,
               nodes[index].children != nil,
               let result = updateNode(in: &nodes[index].children!, at: url, update: update) {
                return result
            }
        }

        return nil
    }

    private func visibleNodes(gitSnapshot: GitRepositorySnapshot?) -> [VisibleNode] {
        visibleNodes(in: displayFileTree(gitSnapshot: gitSnapshot), parentURL: nil)
    }

    private func expandedDirectoryURLs(in nodes: [FileNode]) -> [URL] {
        nodes.flatMap { node -> [URL] in
            guard node.isDirectory else { return [] }

            let childURLs = expandedDirectoryURLs(in: node.children ?? [])
            if node.isExpanded {
                return [node.url] + childURLs
            }

            return childURLs
        }
    }

    private func directoryStates(in nodes: [FileNode]) -> [String: DirectoryState] {
        var states: [String: DirectoryState] = [:]
        collectDirectoryStates(in: nodes, into: &states)
        return states
    }

    private func collectDirectoryStates(
        in nodes: [FileNode],
        into states: inout [String: DirectoryState]
    ) {
        for node in nodes where node.isDirectory {
            states[FileURLRewriter.normalizedPath(node.url)] = DirectoryState(
                node: node,
                isExpanded: node.isExpanded,
                isLoadingChildren: node.isLoadingChildren
            )
            collectDirectoryStates(in: node.children ?? [], into: &states)
        }
    }

    private func visibleNodes(in nodes: [FileNode], parentURL: URL?) -> [VisibleNode] {
        var result: [VisibleNode] = []

        for node in nodes {
            result.append(VisibleNode(node: node, parentURL: parentURL))

            if node.isDirectory,
               node.isExpanded,
               let children = node.children {
                result.append(contentsOf: visibleNodes(in: children, parentURL: node.url))
            }
        }

        return result
    }

    private func node(in nodes: [FileNode], at url: URL) -> FileNode? {
        for node in nodes {
            if FileURLRewriter.urlsMatch(node.url, url) {
                return node
            }

            if node.isDirectory,
               let children = node.children,
               let childNode = self.node(in: children, at: url) {
                return childNode
            }
        }

        return nil
    }

    private mutating func repairSelection(gitSnapshot: GitRepositorySnapshot?) {
        guard let selectedURL else { return }

        guard let visibleNode = visibleNodes(gitSnapshot: gitSnapshot).first(where: {
            FileURLRewriter.urlsMatch($0.node.url, selectedURL)
        }) else {
            self.selectedURL = nil
            return
        }

        self.selectedURL = visibleNode.node.url
    }

    private func filteredChangedNodes(
        _ nodes: [FileNode],
        gitSnapshot: GitRepositorySnapshot
    ) -> [FileNode] {
        nodes.compactMap { node in
            if node.isDirectory {
                guard gitSnapshot.hasChangedDescendant(of: node.url)
                        || gitSnapshot.change(for: node.url) != nil else {
                    return nil
                }

                return FileNode(
                    url: node.url,
                    name: node.name,
                    isDirectory: true,
                    children: node.children.map {
                        filteredChangedNodes($0, gitSnapshot: gitSnapshot)
                    },
                    isExpanded: node.isExpanded,
                    isLoadingChildren: node.isLoadingChildren,
                    isIgnored: node.isIgnored
                )
            }

            return gitSnapshot.change(for: node.url) == nil ? nil : node
        }
    }

    private static func renamedNode(_ node: FileNode, oldURL: URL, newURL: URL) -> FileNode {
        let rewrittenURL = FileURLRewriter.rewrittenURL(
            node.url,
            replacing: oldURL,
            with: newURL
        ) ?? node.url

        return FileNode(
            url: rewrittenURL,
            name: rewrittenURL.lastPathComponent,
            isDirectory: node.isDirectory,
            children: node.children.map { children in
                Self.sortedNodes(children.map { Self.renamedNode($0, oldURL: oldURL, newURL: newURL) })
            },
            isExpanded: node.isExpanded,
            isLoadingChildren: node.isLoadingChildren,
            isIgnored: node.isIgnored
        )
    }

    private static func renameNode(in nodes: inout [FileNode], oldURL: URL, newURL: URL) -> Bool {
        for index in nodes.indices {
            if FileURLRewriter.urlsMatch(nodes[index].url, oldURL) {
                nodes[index] = Self.renamedNode(nodes[index], oldURL: oldURL, newURL: newURL)
                nodes = Self.sortedNodes(nodes)
                return true
            }

            if nodes[index].isDirectory,
               nodes[index].children != nil,
               Self.renameNode(in: &nodes[index].children!, oldURL: oldURL, newURL: newURL) {
                nodes[index].children = Self.sortedNodes(nodes[index].children ?? [])
                return true
            }
        }

        return false
    }

    private static func sortedNodes(_ nodes: [FileNode]) -> [FileNode] {
        nodes.sorted { lhs, rhs in
            if lhs.isDirectory != rhs.isDirectory {
                return lhs.isDirectory && !rhs.isDirectory
            }

            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }

    private static func refreshedNodes(
        _ nodes: [FileNode],
        childrenByPath: [String: [FileNode]],
        directoryStates: [String: DirectoryState]
    ) -> [FileNode] {
        sortedNodes(nodes.map { node in
            guard node.isDirectory else { return node }

            let path = FileURLRewriter.normalizedPath(node.url)
            let previousState = directoryStates[path]
            let refreshedChildren = childrenByPath[path].map {
                refreshedNodes(
                    $0,
                    childrenByPath: childrenByPath,
                    directoryStates: directoryStates
                )
            }
            let preservedChildren = previousState?.isExpanded == true
                || previousState?.isLoadingChildren == true
                ? previousState?.node.children.map {
                    appliedSnapshotNodes(
                        $0,
                        childrenByPath: childrenByPath,
                        directoryStates: directoryStates
                    )
                }
                : nil

            return FileNode(
                url: node.url,
                name: node.name,
                isDirectory: true,
                children: refreshedChildren ?? preservedChildren,
                isExpanded: previousState?.isExpanded ?? false,
                isLoadingChildren: previousState?.isLoadingChildren ?? false,
                isIgnored: node.isIgnored
            )
        })
    }

    // Applies fresh snapshots to a preserved subtree whose own parent listing was
    // not reloaded; nodes without a snapshot are kept as-is, including cached
    // children of collapsed directories.
    private static func appliedSnapshotNodes(
        _ nodes: [FileNode],
        childrenByPath: [String: [FileNode]],
        directoryStates: [String: DirectoryState]
    ) -> [FileNode] {
        nodes.map { node in
            guard node.isDirectory else { return node }

            var updated = node
            let path = FileURLRewriter.normalizedPath(node.url)
            if let freshChildren = childrenByPath[path] {
                updated.children = refreshedNodes(
                    freshChildren,
                    childrenByPath: childrenByPath,
                    directoryStates: directoryStates
                )
            } else {
                updated.children = node.children.map {
                    appliedSnapshotNodes(
                        $0,
                        childrenByPath: childrenByPath,
                        directoryStates: directoryStates
                    )
                }
            }
            return updated
        }
    }
}
