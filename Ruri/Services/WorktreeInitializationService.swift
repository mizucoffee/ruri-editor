//
//  WorktreeInitializationService.swift
//  ruri
//

import Foundation

nonisolated protocol WorktreeInitializationServiceProtocol: Sendable {
    func run(command: String, in worktreeRootURL: URL) async throws
}

nonisolated enum WorktreeInitializationError: LocalizedError, Equatable, Sendable {
    case timedOut
    case commandFailed(exitCode: Int32, output: String)
    case processFailed(String)

    var errorDescription: String? {
        switch self {
        case .timedOut:
            "Worktree initialization timed out."
        case .commandFailed(let exitCode, let output):
            if output.isEmpty {
                "Worktree initialization failed with exit code \(exitCode)."
            } else {
                "Worktree initialization failed with exit code \(exitCode).\n\(output)"
            }
        case .processFailed(let message):
            message.isEmpty ? "Worktree initialization failed." : message
        }
    }
}

nonisolated struct WorktreeInitializationService: WorktreeInitializationServiceProtocol, Sendable {
    private static let maximumOutputCharacters = 6_000

    private let shellPath: String
    private let timeout: TimeInterval

    init(
        shellPath: String = TerminalShellResolver().shellPath(),
        timeout: TimeInterval = 600
    ) {
        self.shellPath = shellPath
        self.timeout = timeout
    }

    nonisolated func run(command: String, in worktreeRootURL: URL) async throws {
        let trimmedCommand = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedCommand.isEmpty else { return }

        let worktreeRootURL = worktreeRootURL.standardizedFileURL
        try await Task.detached(priority: .utility) {
            do {
                let result = try Self.runProcess(
                    shellPath: shellPath,
                    command: trimmedCommand,
                    worktreeRootURL: worktreeRootURL,
                    timeout: timeout
                )

                guard result.exitCode == 0 else {
                    throw WorktreeInitializationError.commandFailed(
                        exitCode: result.exitCode,
                        output: Self.displayOutput(stdout: result.stdout, stderr: result.stderr)
                    )
                }
            } catch let error as WorktreeInitializationError {
                throw error
            } catch {
                throw WorktreeInitializationError.processFailed(error.localizedDescription)
            }
        }.value
    }

    private nonisolated static func runProcess(
        shellPath: String,
        command: String,
        worktreeRootURL: URL,
        timeout: TimeInterval
    ) throws -> WorktreeInitializationCommandResult {
        let process = Process()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        let stdout = WorktreeInitializationLockedData()
        let stderr = WorktreeInitializationLockedData()
        let terminationSemaphore = DispatchSemaphore(value: 0)

        process.executableURL = URL(filePath: shellPath)
        process.arguments = ["-lc", command]
        process.currentDirectoryURL = worktreeRootURL
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        process.environment = ProcessInfo.processInfo.environment.merging([
            "PWD": worktreeRootURL.path(percentEncoded: false)
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
            throw WorktreeInitializationError.timedOut
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

        return WorktreeInitializationCommandResult(
            stdout: stdout.data(),
            stderr: stderr.data(),
            exitCode: process.terminationStatus
        )
    }

    private nonisolated static func displayOutput(stdout: Data, stderr: Data) -> String {
        let output = [stdout, stderr]
            .compactMap { data -> String? in
                guard !data.isEmpty else { return nil }
                return String(data: data, encoding: .utf8)
            }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard output.count > maximumOutputCharacters else {
            return output
        }

        let endIndex = output.index(output.startIndex, offsetBy: maximumOutputCharacters)
        return "\(output[..<endIndex])\n..."
    }
}

nonisolated private struct WorktreeInitializationCommandResult: Sendable {
    let stdout: Data
    let stderr: Data
    let exitCode: Int32
}

nonisolated private final class WorktreeInitializationLockedData: @unchecked Sendable {
    private let lock = NSLock()
    private var storedData = Data()

    func append(_ data: Data) {
        lock.lock()
        storedData.append(data)
        lock.unlock()
    }

    func data() -> Data {
        lock.lock()
        defer { lock.unlock() }
        return storedData
    }
}
