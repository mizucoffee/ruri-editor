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
        let changedPaths: Set<String>
        let gitMetadataChangedPaths: Set<String>

        var isEmpty: Bool {
            changedPaths.isEmpty && gitMetadataChangedPaths.isEmpty
        }
    }

    private struct PendingChange {
        var changedPaths = Set<String>()
        var gitMetadataChangedPaths = Set<String>()

        mutating func formUnion(_ change: Change) {
            changedPaths.formUnion(change.changedPaths)
            gitMetadataChangedPaths.formUnion(change.gitMetadataChangedPaths)
        }

        func change(rootURL: URL) -> Change {
            Change(
                rootURL: rootURL,
                changedPaths: changedPaths,
                gitMetadataChangedPaths: gitMetadataChangedPaths
            )
        }
    }

    typealias ChangeHandler = @MainActor (Change) -> Void

    private let debounceNanoseconds: UInt64
    private let changeHandler: ChangeHandler
    private var streamsByRootURL: [URL: FSEventStreamRef] = [:]
    private var debounceTasksByRootURL: [URL: Task<Void, Never>] = [:]
    private var pendingChangesByRootURL: [URL: PendingChange] = [:]

    init(
        debounceNanoseconds: UInt64 = 500_000_000,
        changeHandler: @escaping ChangeHandler
    ) {
        self.debounceNanoseconds = debounceNanoseconds
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
        debounceTasksByRootURL.removeValue(forKey: standardizedURL)?.cancel()
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

    fileprivate func receiveFileSystemEvents(paths: [String]) {
        let changes = classifiedChanges(for: paths)

        for change in changes {
            scheduleChangeNotification(change)
        }
    }

    func classifiedChanges(for paths: [String]) -> [Change] {
        classifiedChanges(for: paths, rootURLs: Array(streamsByRootURL.keys))
    }

    func classifiedChanges(for paths: [String], rootURLs: [URL]) -> [Change] {
        guard !paths.isEmpty else {
            return []
        }

        let rootPairs = rootURLs.map { rootURL in
            let standardizedURL = rootURL.standardizedFileURL
            return (standardizedURL, normalizedDirectoryPath(standardizedURL))
        }.sorted {
            $0.1.count > $1.1.count
        }
        var changesByRootURL: [URL: PendingChange] = [:]

        for eventPath in paths {
            let normalizedEventPath = normalizedPath(eventPath)

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
            } else {
                changesByRootURL[rootURL, default: PendingChange()]
                    .changedPaths
                    .insert(normalizedEventPath)
            }
        }

        return changesByRootURL
            .map { rootURL, pendingChange in pendingChange.change(rootURL: rootURL) }
            .filter { !$0.isEmpty }
    }

    private func scheduleChangeNotification(_ change: Change) {
        let rootURL = change.rootURL
        pendingChangesByRootURL[rootURL, default: PendingChange()].formUnion(change)
        debounceTasksByRootURL[rootURL]?.cancel()
        debounceTasksByRootURL[rootURL] = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: self?.debounceNanoseconds ?? 500_000_000)
            } catch {
                return
            }

            await MainActor.run {
                guard let self else { return }
                let change = self.pendingChangesByRootURL[rootURL]?.change(rootURL: rootURL)
                    ?? Change(rootURL: rootURL, changedPaths: [], gitMetadataChangedPaths: [])
                self.pendingChangesByRootURL[rootURL] = nil
                self.debounceTasksByRootURL[rootURL] = nil
                guard !change.isEmpty else { return }
                self.changeHandler(change)
            }
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

    private func normalizedDirectoryPath(_ url: URL) -> String {
        normalizedPath(url.standardizedFileURL.path(percentEncoded: false))
    }

    private func normalizedPath(_ path: String) -> String {
        var normalizedPath = NSString(string: path).standardizingPath

        while normalizedPath.count > 1 && normalizedPath.hasSuffix("/") {
            normalizedPath.removeLast()
        }

        return normalizedPath
    }
}

private let projectFileWatcherCallback: FSEventStreamCallback = { _, info, _, eventPaths, _, _ in
    guard let info else { return }

    let watcher = Unmanaged<ProjectFileWatcher>.fromOpaque(info).takeUnretainedValue()
    let paths = unsafeBitCast(eventPaths, to: NSArray.self) as? [String] ?? []

    Task { @MainActor in
        watcher.receiveFileSystemEvents(paths: paths)
    }
}
