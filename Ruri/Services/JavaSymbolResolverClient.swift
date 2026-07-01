//
//  JavaSymbolResolverClient.swift
//  ruri
//

import Foundation

actor JavaSymbolResolverClient: JavaSymbolResolving {
    private struct RequestEnvelope: Codable {
        let id: String
        let payload: JavaSymbolResolverRequest
    }

    private struct ResponseEnvelope: Codable {
        let id: String
        let payload: JavaSymbolResolverResponse?
        let error: String?
    }

    private let javaExecutableURL: URL?
    private let jarURL: URL?
    private let timeout: TimeInterval
    private let idleTimeoutNanoseconds: UInt64
    private var process: Process?
    private var stdinPipe: Pipe?
    private var stdoutPipe: Pipe?
    private var stderrPipe: Pipe?
    private var stdoutBuffer = Data()
    private var stderrBuffer = Data()
    private var pending: [String: CheckedContinuation<JavaSymbolResolverResponse, Error>] = [:]
    private var idleShutdownTask: Task<Void, Never>?

    init(
        javaExecutableURL: URL? = JavaExecutableResolver().executableURL(),
        jarURL: URL? = JavaSymbolResolverBundle().jarURL(),
        timeout: TimeInterval = 20,
        idleTimeoutNanoseconds: UInt64 = 300_000_000_000
    ) {
        self.javaExecutableURL = javaExecutableURL
        self.jarURL = jarURL
        self.timeout = timeout
        self.idleTimeoutNanoseconds = idleTimeoutNanoseconds
    }

    func resolve(_ request: JavaSymbolResolverRequest) async throws -> JavaSymbolResolverResponse {
        try await ensureStarted()
        idleShutdownTask?.cancel()

        let id = UUID().uuidString
        let envelope = RequestEnvelope(id: id, payload: request)
        var data = try JSONEncoder().encode(envelope)
        data.append(0x0A)

        return try await withTaskCancellationHandler {
            try await withThrowingTaskGroup(of: JavaSymbolResolverResponse.self) { group in
                group.addTask {
                    try await withCheckedThrowingContinuation { continuation in
                        Task {
                            await self.send(data, id: id, continuation: continuation)
                        }
                    }
                }
                group.addTask {
                    try await Task.sleep(nanoseconds: UInt64(self.timeout * 1_000_000_000))
                    throw JavaSymbolResolverError(message: "Java symbol resolver timed out.")
                }

                guard let result = try await group.next() else {
                    throw JavaSymbolResolverError(message: "Java symbol resolver did not return a response.")
                }
                group.cancelAll()
                await scheduleIdleShutdown()
                return result
            }
        } onCancel: {
            Task {
                await self.cancelPending(id: id)
            }
        }
    }

    func stop() async {
        idleShutdownTask?.cancel()
        idleShutdownTask = nil
        stopProcess(error: JavaSymbolResolverError(message: "Java symbol resolver stopped."))
    }

    private func send(
        _ data: Data,
        id: String,
        continuation: CheckedContinuation<JavaSymbolResolverResponse, Error>
    ) {
        pending[id] = continuation

        guard let stdinPipe else {
            pending.removeValue(forKey: id)?.resume(
                throwing: JavaSymbolResolverError(message: "Java symbol resolver is not running.")
            )
            return
        }

        do {
            try stdinPipe.fileHandleForWriting.write(contentsOf: data)
        } catch {
            pending.removeValue(forKey: id)?.resume(throwing: error)
        }
    }

    private func cancelPending(id: String) {
        pending.removeValue(forKey: id)?.resume(throwing: CancellationError())
    }

    private func ensureStarted() throws {
        if process?.isRunning == true { return }
        guard let javaExecutableURL else {
            throw JavaSymbolResolverError(message: "Java executable was not found. Install Java 17 or later.")
        }
        guard let jarURL else {
            throw JavaSymbolResolverError(message: "java-symbol-resolver.jar was not found in the app bundle.")
        }

        let process = Process()
        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()

        process.executableURL = javaExecutableURL
        process.arguments = ["-Xmx512m", "-jar", jarURL.path(percentEncoded: false)]
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        process.environment = ProcessInfo.processInfo.environment.merging([
            "LC_ALL": "C",
            "LANG": "C"
        ]) { _, newValue in newValue }

        stdoutPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            Task {
                await self?.appendStdout(data)
            }
        }
        stderrPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            Task {
                await self?.appendStderr(data)
            }
        }
        process.terminationHandler = { [weak self] process in
            Task {
                await self?.handleTermination(exitCode: process.terminationStatus)
            }
        }

        do {
            try SafeProcessLauncher.run(process)
        } catch {
            stdoutPipe.fileHandleForReading.readabilityHandler = nil
            stderrPipe.fileHandleForReading.readabilityHandler = nil
            throw error
        }

        self.process = process
        self.stdinPipe = stdinPipe
        self.stdoutPipe = stdoutPipe
        self.stderrPipe = stderrPipe
        stdoutBuffer.removeAll(keepingCapacity: true)
        stderrBuffer.removeAll(keepingCapacity: true)
    }

    private func appendStdout(_ data: Data) {
        stdoutBuffer.append(data)
        while let newlineIndex = stdoutBuffer.firstIndex(of: 0x0A) {
            let line = stdoutBuffer.prefix(upTo: newlineIndex)
            stdoutBuffer.removeSubrange(...newlineIndex)
            guard !line.isEmpty else { continue }
            handleResponseLine(Data(line))
        }
    }

    private func appendStderr(_ data: Data) {
        stderrBuffer.append(data)
        if stderrBuffer.count > 32_768 {
            stderrBuffer.removeFirst(stderrBuffer.count - 32_768)
        }
    }

    private func handleResponseLine(_ data: Data) {
        do {
            let envelope = try JSONDecoder().decode(ResponseEnvelope.self, from: data)
            guard let continuation = pending.removeValue(forKey: envelope.id) else { return }
            if let error = envelope.error {
                continuation.resume(throwing: JavaSymbolResolverError(message: error))
            } else if let payload = envelope.payload {
                continuation.resume(returning: payload)
            } else {
                continuation.resume(
                    throwing: JavaSymbolResolverError(message: "Java symbol resolver returned an empty response.")
                )
            }
        } catch {
            let message = "Java symbol resolver returned invalid JSON: \(error.localizedDescription)"
            pending.values.forEach { $0.resume(throwing: JavaSymbolResolverError(message: message)) }
            pending.removeAll()
        }
    }

    private func handleTermination(exitCode: Int32) {
        let stderr = String(data: stderrBuffer, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let suffix = stderr?.isEmpty == false ? ": \(stderr ?? "")" : "."
        stopProcess(error: JavaSymbolResolverError(message: "Java symbol resolver exited with code \(exitCode)\(suffix)"))
    }

    private func stopProcess(error: Error) {
        stdoutPipe?.fileHandleForReading.readabilityHandler = nil
        stderrPipe?.fileHandleForReading.readabilityHandler = nil
        if process?.isRunning == true {
            process?.terminate()
        }
        process = nil
        stdinPipe = nil
        stdoutPipe = nil
        stderrPipe = nil
        stdoutBuffer.removeAll(keepingCapacity: false)
        stderrBuffer.removeAll(keepingCapacity: false)

        pending.values.forEach { $0.resume(throwing: error) }
        pending.removeAll()
    }

    private func scheduleIdleShutdown() {
        idleShutdownTask?.cancel()
        idleShutdownTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: await self?.idleTimeoutNanoseconds ?? 300_000_000_000)
            } catch {
                return
            }
            await self?.stop()
        }
    }
}

nonisolated struct JavaSymbolResolverBundle: Sendable {
    func jarURL(bundle: Bundle = .main) -> URL? {
        let candidates = [
            bundle.url(forResource: "java-symbol-resolver", withExtension: "jar", subdirectory: "Tools"),
            bundle.url(forResource: "java-symbol-resolver", withExtension: "jar", subdirectory: "Resources/Tools"),
            bundle.url(forResource: "java-symbol-resolver", withExtension: "jar")
        ]
        return candidates.compactMap(\.self).first
    }
}

nonisolated struct JavaExecutableResolver: Sendable {
    var environment: [String: String] = ProcessInfo.processInfo.environment

    func executableURL(named executableName: String = "java") -> URL? {
        let searchDirectories = (environment["PATH"] ?? "")
            .split(separator: ":")
            .map(String.init) + ["/usr/bin", "/opt/homebrew/bin", "/usr/local/bin"]
        var seen = Set<String>()

        for directory in searchDirectories where seen.insert(directory).inserted {
            let url = URL(filePath: directory).appending(path: executableName)
            if FileManager.default.isExecutableFile(atPath: url.path(percentEncoded: false)) {
                return url.standardizedFileURL
            }
        }

        return nil
    }
}
