//
//  ProjectFileService.swift
//  ruri
//

import Foundation

enum ProjectFileError: LocalizedError, Equatable, Sendable {
    case unreadableUTF8File
    case staleFileSignature
    case invalidFileName
    case destinationAlreadyExists
    case fileSearchExecutableNotFound
    case fileSearchFailed(String)

    var errorDescription: String? {
        switch self {
        case .unreadableUTF8File:
            "UTF-8として読めないファイルです"
        case .staleFileSignature:
            "保存先のファイルが外部で変更されています"
        case .invalidFileName:
            "使用できないファイル名です"
        case .destinationAlreadyExists:
            "同じ名前のファイルまたはフォルダが既に存在します"
        case .fileSearchExecutableNotFound:
            "ファイル検索エンジンが見つかりません"
        case .fileSearchFailed(let message):
            message.isEmpty ? "ファイル検索に失敗しました" : "ファイル検索に失敗しました: \(message)"
        }
    }
}

nonisolated struct ProjectFileSignature: Equatable, Sendable {
    let modificationDate: Date?
    let fileSize: UInt64?
}

nonisolated struct ProjectFileSnapshot: Equatable, Sendable {
    let text: String
    let signature: ProjectFileSignature?
}

struct ProjectFileService: Sendable {
    private let searchExecutableURL: URL?

    nonisolated init(searchExecutableURL: URL? = RipgrepExecutableResolver().bundledExecutableURL()) {
        self.searchExecutableURL = searchExecutableURL
    }

    nonisolated func loadDirectory(at url: URL) async throws -> [FileNode] {
        try await loadDirectory(at: url, projectRootURL: nil)
    }

    nonisolated func loadDirectory(at url: URL, projectRootURL: URL?) async throws -> [FileNode] {
        try await Task.detached(priority: .userInitiated) {
            try Self.loadDirectorySnapshot(at: url, projectRootURL: projectRootURL)
        }.value
    }

    nonisolated func readUTF8File(at url: URL) async throws -> String {
        try await Task.detached(priority: .userInitiated) {
            let data = try Data(contentsOf: url)

            guard let string = String(data: data, encoding: .utf8) else {
                throw ProjectFileError.unreadableUTF8File
            }

            return string
        }.value
    }

    nonisolated func readUTF8FileSnapshot(at url: URL) async throws -> ProjectFileSnapshot {
        try await Task.detached(priority: .userInitiated) {
            let data = try Data(contentsOf: url)

            guard let string = String(data: data, encoding: .utf8) else {
                throw ProjectFileError.unreadableUTF8File
            }

            return ProjectFileSnapshot(
                text: string,
                signature: try Self.fileSignatureSnapshot(at: url)
            )
        }.value
    }

    @discardableResult
    nonisolated func writeUTF8File(_ text: String, to url: URL) async throws -> ProjectFileSignature? {
        try await Task.detached(priority: .userInitiated) {
            try Self.writeUTF8FileSnapshot(text, to: url)
        }.value
    }

    /// ディスク上のファイルが `expectedSignature` のまま変わっていない場合だけ書き込む
    /// compare-and-swap。watcher未反映の外部変更を黙って上書きしないための保存経路用。
    @discardableResult
    nonisolated func writeUTF8File(
        _ text: String,
        to url: URL,
        replacingSignature expectedSignature: ProjectFileSignature?
    ) async throws -> ProjectFileSignature? {
        try await Task.detached(priority: .userInitiated) {
            guard try Self.fileSignatureSnapshot(at: url) == expectedSignature else {
                throw ProjectFileError.staleFileSignature
            }
            return try Self.writeUTF8FileSnapshot(text, to: url)
        }.value
    }

    nonisolated func renameItem(at url: URL, to proposedName: String) async throws -> URL {
        try await Task.detached(priority: .userInitiated) {
            try Self.renameItemSnapshot(at: url, to: proposedName)
        }.value
    }

    nonisolated func createFile(named name: String, in directoryURL: URL) async throws -> URL {
        try await Task.detached(priority: .userInitiated) {
            try Self.createItemSnapshot(named: name, in: directoryURL, isDirectory: false)
        }.value
    }

    nonisolated func createDirectory(named name: String, in directoryURL: URL) async throws -> URL {
        try await Task.detached(priority: .userInitiated) {
            try Self.createItemSnapshot(named: name, in: directoryURL, isDirectory: true)
        }.value
    }

    nonisolated func trashItem(at url: URL) async throws {
        try await Task.detached(priority: .userInitiated) {
            try FileManager.default.trashItem(at: url, resultingItemURL: nil)
        }.value
    }

    nonisolated func duplicateItem(at url: URL) async throws -> URL {
        try await Task.detached(priority: .userInitiated) {
            try Self.duplicateItemSnapshot(at: url)
        }.value
    }

    nonisolated func fileSignature(at url: URL) async throws -> ProjectFileSignature? {
        try await Task.detached(priority: .utility) {
            try Self.fileSignatureSnapshot(at: url)
        }.value
    }

    nonisolated func loadSearchEntries(at url: URL) async throws -> [ProjectFileSearchEntry] {
        guard let searchExecutableURL else {
            throw ProjectFileError.fileSearchExecutableNotFound
        }

        let worker = Task.detached(priority: .userInitiated) {
            try Self.loadSearchEntriesSnapshot(
                at: url.standardizedFileURL,
                executableURL: searchExecutableURL
            )
        }

        return try await withTaskCancellationHandler {
            try await worker.value
        } onCancel: {
            worker.cancel()
        }
    }

    nonisolated private static func loadDirectorySnapshot(at url: URL, projectRootURL: URL?) throws -> [FileNode] {
        let fileManager = FileManager.default
        let keys: [URLResourceKey] = [
            .isDirectoryKey
        ]
        var gitIgnoreMatcher = projectRootURL.map { GitIgnoreMatcher(rootURL: $0) }

        let urls = try fileManager.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: keys,
            options: []
        )

        let nodes = try urls.compactMap { childURL -> FileNode? in
            let values = try childURL.resourceValues(forKeys: Set(keys))
            let name = childURL.lastPathComponent

            if name == ".git" || name == ".ruri" {
                return nil
            }

            let isDirectory = values.isDirectory == true
            let isIgnored = gitIgnoreMatcher?.isIgnoredBySelfOrAncestor(childURL, isDirectory: isDirectory) ?? false

            guard values.isDirectory == true else {
                return FileNode(
                    url: childURL,
                    name: name,
                    isDirectory: false,
                    children: nil,
                    isIgnored: isIgnored
                )
            }

            return FileNode(
                url: childURL,
                name: name,
                isDirectory: true,
                isIgnored: isIgnored
            )
        }

        return nodes.sorted { lhs, rhs in
            if lhs.isDirectory != rhs.isDirectory {
                return lhs.isDirectory && !rhs.isDirectory
            }

            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }

    nonisolated private static func renameItemSnapshot(at url: URL, to proposedName: String) throws -> URL {
        let fileManager = FileManager.default
        let newName = proposedName.trimmingCharacters(in: .whitespacesAndNewlines)

        guard isValidFileName(newName) else {
            throw ProjectFileError.invalidFileName
        }

        guard newName != url.lastPathComponent else {
            return url.standardizedFileURL
        }

        let destinationURL = url
            .deletingLastPathComponent()
            .appendingPathComponent(newName)

        if fileManager.fileExists(atPath: destinationURL.path(percentEncoded: false)) {
            throw ProjectFileError.destinationAlreadyExists
        }

        try fileManager.moveItem(at: url, to: destinationURL)
        return destinationURL.standardizedFileURL
    }

    nonisolated private static func createItemSnapshot(
        named name: String,
        in directoryURL: URL,
        isDirectory: Bool
    ) throws -> URL {
        let fileManager = FileManager.default
        let newName = name.trimmingCharacters(in: .whitespacesAndNewlines)

        guard isValidFileName(newName) else {
            throw ProjectFileError.invalidFileName
        }

        let destinationURL = directoryURL.appendingPathComponent(newName)

        if fileManager.fileExists(atPath: destinationURL.path(percentEncoded: false)) {
            throw ProjectFileError.destinationAlreadyExists
        }

        if isDirectory {
            try fileManager.createDirectory(at: destinationURL, withIntermediateDirectories: false)
        } else {
            try Data().write(to: destinationURL)
        }

        return destinationURL.standardizedFileURL
    }

    nonisolated private static func duplicateItemSnapshot(at url: URL) throws -> URL {
        let fileManager = FileManager.default
        let parentURL = url.deletingLastPathComponent()
        let pathExtension = url.pathExtension
        let baseName = pathExtension.isEmpty
            ? url.lastPathComponent
            : url.deletingPathExtension().lastPathComponent

        for attempt in 1...10000 {
            let candidateBase = attempt == 1 ? "\(baseName) copy" : "\(baseName) copy \(attempt)"
            var candidateURL = parentURL.appendingPathComponent(candidateBase)
            if !pathExtension.isEmpty {
                candidateURL = candidateURL.appendingPathExtension(pathExtension)
            }

            if fileManager.fileExists(atPath: candidateURL.path(percentEncoded: false)) {
                continue
            }

            try fileManager.copyItem(at: url, to: candidateURL)
            return candidateURL.standardizedFileURL
        }

        throw ProjectFileError.destinationAlreadyExists
    }

    nonisolated private static func isValidFileName(_ name: String) -> Bool {
        !name.isEmpty
            && name != "."
            && name != ".."
            && !name.contains("/")
            && !name.contains("\0")
    }

    // atomic書き込み(rename置換)がsymlink自体を通常ファイルで潰さないよう、実体パスへ解決してから書く。
    @discardableResult
    nonisolated private static func writeUTF8FileSnapshot(_ text: String, to url: URL) throws -> ProjectFileSignature? {
        let targetURL = url.resolvingSymlinksInPath()
        try text.write(to: targetURL, atomically: true, encoding: .utf8)
        return try fileSignatureSnapshot(at: targetURL)
    }

    // attributesOfItemは末尾のsymlinkを辿らないため、リンク先の実体を見るよう解決してから取得する
    // (symlinkされた開いているファイルが「削除済み」扱いになったり、CAS書き込みが常に失敗するのを防ぐ)。
    nonisolated private static func fileSignatureSnapshot(at url: URL) throws -> ProjectFileSignature? {
        do {
            let attributes = try FileManager.default.attributesOfItem(
                atPath: url.resolvingSymlinksInPath().path(percentEncoded: false)
            )

            guard attributes[.type] as? FileAttributeType == .typeRegular else {
                return nil
            }

            return ProjectFileSignature(
                modificationDate: attributes[.modificationDate] as? Date,
                fileSize: (attributes[.size] as? NSNumber)?.uint64Value
            )
        } catch let error as NSError where error.domain == NSCocoaErrorDomain
            && error.code == NSFileReadNoSuchFileError {
            return nil
        }
    }

    nonisolated private static func loadSearchEntriesSnapshot(
        at rootURL: URL,
        executableURL: URL
    ) throws -> [ProjectFileSearchEntry] {
        _ = try rootURL.resourceValues(forKeys: [.isDirectoryKey])

        let output = try RipgrepFileListRunner.run(
            executableURL: executableURL,
            currentDirectoryURL: rootURL
        )
        return searchEntries(fromNullSeparatedOutput: output, rootURL: rootURL)
    }

    nonisolated private static func searchEntries(
        fromNullSeparatedOutput output: Data,
        rootURL: URL
    ) -> [ProjectFileSearchEntry] {
        output
            .split(separator: 0)
            .compactMap { pathData -> ProjectFileSearchEntry? in
                guard let relativePath = String(data: Data(pathData), encoding: .utf8),
                      !relativePath.isEmpty else {
                    return nil
                }

                let fileURL = rootURL.appending(path: relativePath).standardizedFileURL
                return ProjectFileSearchEntry(
                    url: fileURL,
                    fileName: fileURL.lastPathComponent,
                    relativeParentPath: FileURLRewriter.relativePath(
                        from: rootURL,
                        to: fileURL.deletingLastPathComponent().standardizedFileURL
                    ) ?? ""
                )
            }
    }
}

// ファイル名検索index用の列挙。ignore判定はrgのネイティブ解釈に委ねる（`--no-ignore` を渡さない）。
// 同じファイル内のツリー表示（loadDirectorySnapshot）はGitIgnoreMatcherでノード単位に判定する
// （役割分担は GitIgnoreMatcher.swift 冒頭を参照）。
nonisolated private enum RipgrepFileListRunner {
    static func run(executableURL: URL, currentDirectoryURL: URL) throws -> Data {
        let process = Process()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        let stdout = ProjectFileSearchLockedData()
        let stderr = ProjectFileSearchLockedData()
        let terminationSemaphore = DispatchSemaphore(value: 0)

        process.executableURL = executableURL
        process.arguments = [
            "--files",
            "--null",
            "--hidden",
            "--no-require-git",
            "--glob",
            "!.git/**",
            "--glob",
            "!.ruri/**"
        ]
        process.currentDirectoryURL = currentDirectoryURL
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        process.environment = ProcessInfo.processInfo.environment.merging([
            "LC_ALL": "C",
            "LANG": "C"
        ]) { _, newValue in newValue }
        process.terminationHandler = { _ in
            terminationSemaphore.signal()
        }

        let stdoutEOFSemaphore = DispatchSemaphore(value: 0)
        let stderrEOFSemaphore = DispatchSemaphore(value: 0)
        stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
                stdoutEOFSemaphore.signal()
            } else {
                stdout.append(data)
            }
        }
        stderrPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
                stderrEOFSemaphore.signal()
            } else {
                stderr.append(data)
            }
        }

        do {
            try SafeProcessLauncher.run(process)
        } catch {
            cleanup(stdoutPipe: stdoutPipe, stderrPipe: stderrPipe)
            throw ProjectFileError.fileSearchExecutableNotFound
        }

        while terminationSemaphore.wait(timeout: .now() + 0.05) == .timedOut {
            if Task.isCancelled {
                SafeProcessLauncher.terminateWithEscalation(process)
                cleanup(stdoutPipe: stdoutPipe, stderrPipe: stderrPipe)
                throw CancellationError()
            }
        }

        // 終了直前のバースト出力をハンドラがEOFまで読み切るのを待ってから結果を確定する。
        // 孫プロセスがpipeを保持し続ける場合に備えて待ちは有限にする。
        _ = stdoutEOFSemaphore.wait(timeout: .now() + 2)
        _ = stderrEOFSemaphore.wait(timeout: .now() + 2)
        cleanup(stdoutPipe: stdoutPipe, stderrPipe: stderrPipe)

        guard process.terminationStatus == 0 || process.terminationStatus == 1 else {
            let message = String(data: stderr.data(), encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            throw ProjectFileError.fileSearchFailed(message)
        }

        return stdout.data()
    }

    private static func cleanup(stdoutPipe: Pipe, stderrPipe: Pipe) {
        stdoutPipe.fileHandleForReading.readabilityHandler = nil
        stderrPipe.fileHandleForReading.readabilityHandler = nil
    }
}

nonisolated private final class ProjectFileSearchLockedData: @unchecked Sendable {
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
