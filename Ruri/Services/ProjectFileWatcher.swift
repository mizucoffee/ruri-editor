//
//  ProjectFileWatcher.swift
//  ruri
//

import CoreServices
import Foundation

@MainActor
final class ProjectFileWatcher {
    struct Change: Equatable, Sendable {
        let rootURL: URL
        let dirtyFilePaths: Set<String>
        let dirtyDirectoryPaths: Set<String>
        let dirtyRecursivePaths: Set<String>
        let gitMetadataChangedPaths: Set<String>
        let requiresWorkspaceRescan: Bool
        let requiresFullGitRefresh: Bool

        init(
            rootURL: URL,
            dirtyFilePaths: Set<String>,
            dirtyDirectoryPaths: Set<String> = [],
            dirtyRecursivePaths: Set<String> = [],
            gitMetadataChangedPaths: Set<String> = [],
            requiresWorkspaceRescan: Bool = false,
            requiresFullGitRefresh: Bool = false
        ) {
            self.rootURL = rootURL
            self.dirtyFilePaths = dirtyFilePaths
            self.dirtyDirectoryPaths = dirtyDirectoryPaths
            self.dirtyRecursivePaths = dirtyRecursivePaths
            self.gitMetadataChangedPaths = gitMetadataChangedPaths
            self.requiresWorkspaceRescan = requiresWorkspaceRescan
            self.requiresFullGitRefresh = requiresFullGitRefresh
        }

        init(
            rootURL: URL,
            changedPaths: Set<String>,
            gitMetadataChangedPaths: Set<String> = []
        ) {
            self.init(
                rootURL: rootURL,
                dirtyFilePaths: changedPaths,
                gitMetadataChangedPaths: gitMetadataChangedPaths
            )
        }

        static func fileChange(rootURL: URL, paths: Set<String>) -> Change {
            Change(rootURL: rootURL.standardizedFileURL, dirtyFilePaths: paths)
        }

        static func directoryChange(rootURL: URL, paths: Set<String>) -> Change {
            Change(rootURL: rootURL.standardizedFileURL, dirtyFilePaths: [], dirtyDirectoryPaths: paths)
        }

        static func recursiveChange(rootURL: URL, paths: Set<String>) -> Change {
            Change(rootURL: rootURL.standardizedFileURL, dirtyFilePaths: [], dirtyRecursivePaths: paths)
        }

        static func workspaceRescan(rootURL: URL) -> Change {
            let standardizedURL = rootURL.standardizedFileURL
            return Change(
                rootURL: standardizedURL,
                dirtyFilePaths: [],
                dirtyRecursivePaths: [standardizedURL.path(percentEncoded: false)],
                requiresWorkspaceRescan: true,
                requiresFullGitRefresh: true
            )
        }

        var changedPaths: Set<String> {
            dirtyFilePaths
                .union(dirtyDirectoryPaths)
                .union(dirtyRecursivePaths)
        }

        var isEmpty: Bool {
            changedPaths.isEmpty
                && gitMetadataChangedPaths.isEmpty
                && !requiresWorkspaceRescan
                && !requiresFullGitRefresh
        }
    }

    private struct PendingChange {
        var dirtyFilePaths = Set<String>()
        var dirtyDirectoryPaths = Set<String>()
        var dirtyRecursivePaths = Set<String>()
        var gitMetadataChangedPaths = Set<String>()
        var requiresWorkspaceRescan = false
        var requiresFullGitRefresh = false

        mutating func formUnion(_ change: Change) {
            dirtyFilePaths.formUnion(change.dirtyFilePaths)
            dirtyDirectoryPaths.formUnion(change.dirtyDirectoryPaths)
            dirtyRecursivePaths.formUnion(change.dirtyRecursivePaths)
            gitMetadataChangedPaths.formUnion(change.gitMetadataChangedPaths)
            requiresWorkspaceRescan = requiresWorkspaceRescan || change.requiresWorkspaceRescan
            requiresFullGitRefresh = requiresFullGitRefresh || change.requiresFullGitRefresh
        }

        func change(rootURL: URL) -> Change {
            Change(
                rootURL: rootURL,
                dirtyFilePaths: dirtyFilePaths,
                dirtyDirectoryPaths: dirtyDirectoryPaths,
                dirtyRecursivePaths: dirtyRecursivePaths,
                gitMetadataChangedPaths: gitMetadataChangedPaths,
                requiresWorkspaceRescan: requiresWorkspaceRescan,
                requiresFullGitRefresh: requiresFullGitRefresh
            )
        }
    }

    struct FileSystemEvent: Equatable {
        let path: String
        let flags: FSEventStreamEventFlags
    }

    typealias ChangeHandler = @MainActor (Change) -> Void

    private let changeHandler: ChangeHandler
    private let debouncer: PerKeyDebouncer<URL>
    private var streamsByRootURL: [URL: FSEventStreamRef] = [:]
    private var pendingChangesByRootURL: [URL: PendingChange] = [:]

    init(
        debounceNanoseconds: UInt64 = 500_000_000,
        changeHandler: @escaping ChangeHandler
    ) {
        self.debouncer = PerKeyDebouncer(delayNanoseconds: debounceNanoseconds)
        self.changeHandler = changeHandler
    }

    deinit {
        MainActor.assumeIsolated {
            stopWatchingAll()
        }
    }

    var watchedProjectURLs: [URL] {
        streamsByRootURL.keys.sorted {
            $0.path(percentEncoded: false) < $1.path(percentEncoded: false)
        }
    }

    func startWatching(_ rootURL: URL) {
        let standardizedURL = rootURL.standardizedFileURL
        guard streamsByRootURL[standardizedURL] == nil else { return }

        var context = FSEventStreamContext(
            version: 0,
            info: UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()),
            retain: nil,
            release: nil,
            copyDescription: nil
        )
        let paths = [standardizedURL.path(percentEncoded: false)] as CFArray
        let flags = FSEventStreamCreateFlags(
            kFSEventStreamCreateFlagFileEvents
                | kFSEventStreamCreateFlagUseCFTypes
                | kFSEventStreamCreateFlagNoDefer
        )

        guard let stream = FSEventStreamCreate(
            kCFAllocatorDefault,
            projectFileWatcherCallback,
            &context,
            paths,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.25,
            flags
        ) else {
            return
        }

        FSEventStreamSetDispatchQueue(stream, DispatchQueue.global(qos: .utility))
        FSEventStreamStart(stream)
        streamsByRootURL[standardizedURL] = stream
    }

    func stopWatching(_ rootURL: URL) {
        let standardizedURL = rootURL.standardizedFileURL
        debouncer.cancel(for: standardizedURL)
        pendingChangesByRootURL[standardizedURL] = nil

        guard let stream = streamsByRootURL.removeValue(forKey: standardizedURL) else {
            return
        }

        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
    }

    func stopWatchingAll() {
        for rootURL in Array(streamsByRootURL.keys) {
            stopWatching(rootURL)
        }
    }

    fileprivate func receiveFileSystemEvents(_ events: [FileSystemEvent]) {
        let changes = classifiedEventChanges(for: events)

        for change in changes {
            scheduleChangeNotification(change)
        }
    }

    func classifiedChanges(for paths: [String]) -> [Change] {
        classifiedEventChanges(
            for: paths.map { FileSystemEvent(path: $0, flags: 0) },
            rootURLs: Array(streamsByRootURL.keys)
        )
    }

    func classifiedChanges(for paths: [String], rootURLs: [URL]) -> [Change] {
        classifiedEventChanges(
            for: paths.map { FileSystemEvent(path: $0, flags: 0) },
            rootURLs: rootURLs
        )
    }

    func classifiedEventChanges(for events: [FileSystemEvent]) -> [Change] {
        classifiedEventChanges(for: events, rootURLs: Array(streamsByRootURL.keys))
    }

    func classifiedEventChanges(for events: [FileSystemEvent], rootURLs: [URL]) -> [Change] {
        guard !events.isEmpty else {
            return []
        }

        let rootPairs = rootURLs.map { rootURL in
            let standardizedURL = rootURL.standardizedFileURL
            return (standardizedURL, FileURLRewriter.normalizedPath(standardizedURL))
        }.sorted {
            $0.1.count > $1.1.count
        }
        var changesByRootURL: [URL: PendingChange] = [:]

        for event in events {
            let normalizedEventPath = FileURLRewriter.normalizedPath(event.path)

            guard let (rootURL, rootPath) = rootPairs.first(where: { _, rootPath in
                normalizedEventPath == rootPath
                    || normalizedEventPath.hasPrefix(rootPath.hasSuffix("/") ? rootPath : "\(rootPath)/")
            }) else {
                continue
            }

            if isRuriMetadataPath(normalizedEventPath, in: rootPath) {
                continue
            }

            if isGitMetadataPath(normalizedEventPath, in: rootPath) {
                changesByRootURL[rootURL, default: PendingChange()]
                    .gitMetadataChangedPaths
                    .insert(normalizedEventPath)
                changesByRootURL[rootURL, default: PendingChange()].requiresFullGitRefresh = true
                continue
            }

            var pendingChange = changesByRootURL[rootURL, default: PendingChange()]
            classify(
                normalizedEventPath,
                flags: event.flags,
                into: &pendingChange
            )
            changesByRootURL[rootURL] = pendingChange
        }

        return changesByRootURL
            .map { rootURL, pendingChange in pendingChange.change(rootURL: rootURL) }
            .filter { !$0.isEmpty }
    }

    private func classify(
        _ path: String,
        flags: FSEventStreamEventFlags,
        into pendingChange: inout PendingChange
    ) {
        if flags.containsAny([
            FSEventStreamEventFlags(kFSEventStreamEventFlagMustScanSubDirs),
            FSEventStreamEventFlags(kFSEventStreamEventFlagUserDropped),
            FSEventStreamEventFlags(kFSEventStreamEventFlagKernelDropped),
            FSEventStreamEventFlags(kFSEventStreamEventFlagEventIdsWrapped),
            FSEventStreamEventFlags(kFSEventStreamEventFlagRootChanged),
            FSEventStreamEventFlags(kFSEventStreamEventFlagMount),
            FSEventStreamEventFlags(kFSEventStreamEventFlagUnmount)
        ]) {
            pendingChange.dirtyRecursivePaths.insert(path)
            pendingChange.requiresWorkspaceRescan = true
            pendingChange.requiresFullGitRefresh = true
            return
        }

        let isDirectory = flags.contains(FSEventStreamEventFlags(kFSEventStreamEventFlagItemIsDir))
        let isCreatedOrDeletedOrRenamed = flags.containsAny([
            FSEventStreamEventFlags(kFSEventStreamEventFlagItemCreated),
            FSEventStreamEventFlags(kFSEventStreamEventFlagItemRemoved),
            FSEventStreamEventFlags(kFSEventStreamEventFlagItemRenamed)
        ])

        if isDirectory {
            if isCreatedOrDeletedOrRenamed {
                pendingChange.dirtyRecursivePaths.insert(path)
                if let parentPath = parentPath(for: path) {
                    pendingChange.dirtyDirectoryPaths.insert(parentPath)
                }
            } else {
                pendingChange.dirtyDirectoryPaths.insert(path)
            }
            return
        }

        pendingChange.dirtyFilePaths.insert(path)
        if isCreatedOrDeletedOrRenamed,
           let parentPath = parentPath(for: path) {
            pendingChange.dirtyDirectoryPaths.insert(parentPath)
        }
    }

    private func parentPath(for path: String) -> String? {
        let parent = NSString(string: path).deletingLastPathComponent
        return parent.isEmpty || parent == path ? nil : FileURLRewriter.normalizedPath(parent)
    }

    private func scheduleChangeNotification(_ change: Change) {
        var change = change
        if change.changedPaths.count > 64 {
            change = Change(
                rootURL: change.rootURL,
                dirtyFilePaths: change.dirtyFilePaths,
                dirtyDirectoryPaths: change.dirtyDirectoryPaths,
                dirtyRecursivePaths: change.dirtyRecursivePaths,
                gitMetadataChangedPaths: change.gitMetadataChangedPaths,
                requiresWorkspaceRescan: change.requiresWorkspaceRescan,
                requiresFullGitRefresh: true
            )
        }

        let rootURL = change.rootURL
        pendingChangesByRootURL[rootURL, default: PendingChange()].formUnion(change)
        debouncer.schedule(for: rootURL) { [weak self] in
            guard let self else { return }
            let change = self.pendingChangesByRootURL[rootURL]?.change(rootURL: rootURL)
                ?? Change(rootURL: rootURL, dirtyFilePaths: [])
            self.pendingChangesByRootURL[rootURL] = nil
            guard !change.isEmpty else { return }
            self.changeHandler(change)
        }
    }

    private func isGitMetadataPath(_ eventPath: String, in rootPath: String) -> Bool {
        let prefix = rootPath.hasSuffix("/") ? rootPath : "\(rootPath)/"
        guard eventPath.hasPrefix(prefix) else { return false }

        let relativePath = String(eventPath.dropFirst(prefix.count))
        return relativePath == ".git" || relativePath.hasPrefix(".git/")
    }

    private func isRuriMetadataPath(_ eventPath: String, in rootPath: String) -> Bool {
        let prefix = rootPath.hasSuffix("/") ? rootPath : "\(rootPath)/"
        guard eventPath.hasPrefix(prefix) else { return false }

        let relativePath = String(eventPath.dropFirst(prefix.count))
        return relativePath == ".ruri" || relativePath.hasPrefix(".ruri/")
    }

}

private let projectFileWatcherCallback: FSEventStreamCallback = { _, info, numEvents, eventPaths, eventFlags, _ in
    guard let info else { return }

    let watcher = Unmanaged<ProjectFileWatcher>.fromOpaque(info).takeUnretainedValue()
    let paths = unsafeBitCast(eventPaths, to: NSArray.self) as? [String] ?? []
    let flags = Array(UnsafeBufferPointer(start: eventFlags, count: numEvents))
    let events = paths.enumerated().map { index, path in
        ProjectFileWatcher.FileSystemEvent(
            path: path,
            flags: index < flags.count ? flags[index] : 0
        )
    }

    Task { @MainActor in
        watcher.receiveFileSystemEvents(events)
    }
}

private extension FSEventStreamEventFlags {
    func contains(_ flag: FSEventStreamEventFlags) -> Bool {
        self & flag != 0
    }

    func containsAny(_ flags: [FSEventStreamEventFlags]) -> Bool {
        flags.contains { contains($0) }
    }
}
