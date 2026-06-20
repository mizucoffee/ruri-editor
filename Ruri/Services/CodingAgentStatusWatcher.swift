//
//  CodingAgentStatusWatcher.swift
//  ruri
//

import CoreServices
import Foundation

@MainActor
final class CodingAgentStatusWatcher {
    typealias ChangeHandler = @MainActor (URL) -> Void

    private let debounceNanoseconds: UInt64
    private let changeHandler: ChangeHandler
    private var streamsByDirectoryURL: [URL: FSEventStreamRef] = [:]
    private var debounceTasksByDirectoryURL: [URL: Task<Void, Never>] = [:]

    init(
        debounceNanoseconds: UInt64 = 50_000_000,
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

    var watchedDirectoryURLs: Set<URL> {
        Set(streamsByDirectoryURL.keys)
    }

    func updateWatchedDirectories(_ directoryURLs: Set<URL>) {
        let standardizedDirectoryURLs = Set(directoryURLs.map(\.standardizedFileURL))

        for directoryURL in watchedDirectoryURLs.subtracting(standardizedDirectoryURLs) {
            stopWatching(directoryURL)
        }

        for directoryURL in standardizedDirectoryURLs {
            startWatching(directoryURL)
        }
    }

    func stopWatchingAll() {
        for directoryURL in Array(streamsByDirectoryURL.keys) {
            stopWatching(directoryURL)
        }
    }

    private func startWatching(_ directoryURL: URL) {
        let standardizedURL = directoryURL.standardizedFileURL
        guard streamsByDirectoryURL[standardizedURL] == nil else { return }

        try? FileManager.default.createDirectory(
            at: standardizedURL,
            withIntermediateDirectories: true
        )

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
            codingAgentStatusWatcherCallback,
            &context,
            paths,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.05,
            flags
        ) else {
            return
        }

        FSEventStreamSetDispatchQueue(stream, DispatchQueue.global(qos: .utility))
        FSEventStreamStart(stream)
        streamsByDirectoryURL[standardizedURL] = stream
    }

    private func stopWatching(_ directoryURL: URL) {
        let standardizedURL = directoryURL.standardizedFileURL
        debounceTasksByDirectoryURL.removeValue(forKey: standardizedURL)?.cancel()

        guard let stream = streamsByDirectoryURL.removeValue(forKey: standardizedURL) else {
            return
        }

        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
    }

    fileprivate func receiveFileSystemEvents(paths: [String]) {
        guard !paths.isEmpty else {
            for directoryURL in streamsByDirectoryURL.keys {
                scheduleChangeNotification(for: directoryURL)
            }
            return
        }

        for directoryURL in directoriesContaining(paths: paths) {
            scheduleChangeNotification(for: directoryURL)
        }
    }

    private func directoriesContaining(paths: [String]) -> Set<URL> {
        let directoryPairs = streamsByDirectoryURL.keys.map { directoryURL in
            let standardizedURL = directoryURL.standardizedFileURL
            return (standardizedURL, normalizedDirectoryPath(standardizedURL))
        }

        var changedDirectoryURLs = Set<URL>()
        for eventPath in paths {
            let normalizedEventPath = normalizedPath(eventPath)
            for (directoryURL, directoryPath) in directoryPairs where contains(
                eventPath: normalizedEventPath,
                in: directoryPath
            ) {
                changedDirectoryURLs.insert(directoryURL)
            }
        }
        return changedDirectoryURLs
    }

    private func scheduleChangeNotification(for directoryURL: URL) {
        debounceTasksByDirectoryURL[directoryURL]?.cancel()
        debounceTasksByDirectoryURL[directoryURL] = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: self?.debounceNanoseconds ?? 50_000_000)
            } catch {
                return
            }

            await MainActor.run {
                guard let self else { return }
                self.debounceTasksByDirectoryURL[directoryURL] = nil
                self.changeHandler(directoryURL)
            }
        }
    }

    private func contains(eventPath: String, in directoryPath: String) -> Bool {
        eventPath == directoryPath
            || eventPath.hasPrefix(directoryPath.hasSuffix("/") ? directoryPath : "\(directoryPath)/")
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

private let codingAgentStatusWatcherCallback: FSEventStreamCallback = { _, info, _, eventPaths, _, _ in
    guard let info else { return }

    let watcher = Unmanaged<CodingAgentStatusWatcher>.fromOpaque(info).takeUnretainedValue()
    let paths = unsafeBitCast(eventPaths, to: NSArray.self) as? [String] ?? []

    Task { @MainActor in
        watcher.receiveFileSystemEvents(paths: paths)
    }
}
