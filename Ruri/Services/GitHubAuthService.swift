//
//  GitHubAuthService.swift
//  ruri
//

import Foundation

nonisolated protocol GitHubAuthServiceProtocol: Sendable {
    func currentAuthenticationStatus() async -> GitHubAuthStatusState
    func logIn(devicePromptHandler: @escaping @Sendable (GitHubLoginDevicePrompt) -> Void) async throws
}

nonisolated struct GitHubAuthService: GitHubAuthServiceProtocol, Sendable {
    private let cliClient: GitHubCLIClient
    private let commandTimeout: TimeInterval
    private let loginCommandTimeout: TimeInterval

    init(
        executableURL: URL? = GitHubExecutableResolver().executableURL(named: "gh"),
        commandRunner: any GitHubCommandRunning = ProcessGitHubCommandRunner(),
        commandTimeout: TimeInterval = 20,
        loginCommandTimeout: TimeInterval = 300
    ) {
        cliClient = GitHubCLIClient(
            executableURL: executableURL,
            commandRunner: commandRunner,
            commandTimeout: commandTimeout
        )
        self.commandTimeout = commandTimeout
        self.loginCommandTimeout = loginCommandTimeout
    }

    nonisolated func currentAuthenticationStatus() async -> GitHubAuthStatusState {
        guard cliClient.isAvailable else {
            return .unavailable(message: "GitHub CLI is not installed.")
        }

        do {
            let result = try await cliClient.run(
                arguments: ["api", "user", "--hostname", "github.com", "--jq", ".login"],
                currentDirectoryURL: nil,
                environment: [:],
                standardInput: nil,
                outputHandler: nil,
                timeout: commandTimeout
            )
            if result.exitCode == 0 {
                let username = Self.outputString(from: result.stdout)
                guard !username.isEmpty else {
                    return .failed(message: "GitHub did not return a username.")
                }

                return .authenticated(username: username)
            }

            return Self.status(forFailedResult: result)
        } catch {
            return .failed(message: error.localizedDescription)
        }
    }

    nonisolated func logIn(
        devicePromptHandler: @escaping @Sendable (GitHubLoginDevicePrompt) -> Void
    ) async throws {
        guard cliClient.isAvailable else {
            throw GitHubAuthServiceError.githubCLINotInstalled
        }

        let promptObserver = GitHubLoginPromptOutputObserver(promptHandler: devicePromptHandler)
        let result = try await cliClient.run(
            arguments: [
                "auth",
                "login",
                "--hostname",
                "github.com",
                "--web",
                "--git-protocol",
                "ssh",
                "--skip-ssh-key"
            ],
            currentDirectoryURL: nil,
            environment: [
                "GH_BROWSER": "/usr/bin/open"
            ],
            standardInput: Data("\n".utf8),
            outputHandler: { data in
                promptObserver.append(data)
            },
            timeout: loginCommandTimeout
        )
        guard result.exitCode == 0 else {
            throw GitHubAuthServiceError.commandFailed(Self.commandErrorMessage(from: result))
        }
    }

    private nonisolated static func status(forFailedResult result: GitHubCommandResult) -> GitHubAuthStatusState {
        let message = GitHubCLIClient.commandErrorMessage(from: result)
        if GitHubCLIClient.isUnauthenticatedMessage(message) {
            return .unauthenticated
        }

        return .failed(message: message)
    }

    private nonisolated static func commandErrorMessage(from result: GitHubCommandResult) -> String {
        GitHubCLIClient.commandErrorMessage(from: result)
    }

    private nonisolated static func outputString(from data: Data) -> String {
        String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
}

nonisolated enum GitHubAuthServiceError: LocalizedError, Equatable {
    case githubCLINotInstalled
    case commandFailed(String)

    var errorDescription: String? {
        switch self {
        case .githubCLINotInstalled:
            "GitHub CLI is not installed."
        case .commandFailed(let message):
            message
        }
    }
}

nonisolated protocol GitHubCommandRunning: Sendable {
    func run(
        executableURL: URL,
        arguments: [String],
        currentDirectoryURL: URL?,
        environment: [String: String],
        standardInput: Data?,
        outputHandler: (@Sendable (Data) -> Void)?,
        timeout: TimeInterval
    ) async throws -> GitHubCommandResult
}

nonisolated struct GitHubCommandResult: Equatable, Sendable {
    let stdout: Data
    let stderr: Data
    let exitCode: Int32

    init(
        stdout: Data = Data(),
        stderr: Data = Data(),
        exitCode: Int32
    ) {
        self.stdout = stdout
        self.stderr = stderr
        self.exitCode = exitCode
    }
}

nonisolated struct ProcessGitHubCommandRunner: GitHubCommandRunning, Sendable {
    func run(
        executableURL: URL,
        arguments: [String],
        currentDirectoryURL: URL?,
        environment: [String: String],
        standardInput: Data?,
        outputHandler: (@Sendable (Data) -> Void)?,
        timeout: TimeInterval
    ) async throws -> GitHubCommandResult {
        try await Task.detached(priority: .utility) {
            try GitHubProcessCommandRunner.run(
                executableURL: executableURL,
                arguments: arguments,
                currentDirectoryURL: currentDirectoryURL,
                environment: environment,
                standardInput: standardInput,
                outputHandler: outputHandler,
                timeout: timeout
            )
        }.value
    }
}

nonisolated struct GitHubExecutableResolver: Sendable {
    var environment: [String: String] = ProcessInfo.processInfo.environment
    var fallbackDirectories: [String] = [
        "/opt/homebrew/bin",
        "/usr/local/bin",
        "/usr/bin"
    ]

    func executableURL(named executableName: String) -> URL? {
        for directory in searchDirectories {
            let url = URL(filePath: directory).appending(path: executableName)
            if FileManager.default.isExecutableFile(atPath: url.path(percentEncoded: false)) {
                return url.standardizedFileURL
            }
        }

        return nil
    }

    private var searchDirectories: [String] {
        let pathDirectories = (environment["PATH"] ?? "")
            .split(separator: ":")
            .map(String.init)

        var seen = Set<String>()
        return (pathDirectories + fallbackDirectories).filter { directory in
            guard !directory.isEmpty else { return false }
            return seen.insert(directory).inserted
        }
    }
}

nonisolated private enum GitHubProcessCommandRunner {
    static func run(
        executableURL: URL,
        arguments: [String],
        currentDirectoryURL: URL?,
        environment: [String: String],
        standardInput: Data?,
        outputHandler: (@Sendable (Data) -> Void)?,
        timeout: TimeInterval
    ) throws -> GitHubCommandResult {
        let process = Process()
        let stdinPipe = standardInput.map { _ in Pipe() }
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        let stdout = GitHubLockedData()
        let stderr = GitHubLockedData()
        let terminationSemaphore = DispatchSemaphore(value: 0)

        process.executableURL = executableURL
        process.arguments = arguments
        process.currentDirectoryURL = currentDirectoryURL
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        process.environment = ProcessInfo.processInfo.environment.merging([
            "LC_ALL": "C",
            "LANG": "C"
        ].merging(environment) { _, newValue in newValue }) { _, newValue in newValue }
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
                outputHandler?(data)
            }
        }
        stderrPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
                stderrEOFSemaphore.signal()
            } else {
                stderr.append(data)
                outputHandler?(data)
            }
        }

        do {
            try SafeProcessLauncher.run(process)
        } catch {
            stdoutPipe.fileHandleForReading.readabilityHandler = nil
            stderrPipe.fileHandleForReading.readabilityHandler = nil
            throw error
        }
        if let standardInput,
           let stdinPipe {
            stdinPipe.fileHandleForWriting.write(standardInput)
            try? stdinPipe.fileHandleForWriting.close()
        }

        let timeoutResult = terminationSemaphore.wait(timeout: .now() + timeout)
        if timeoutResult == .timedOut {
            SafeProcessLauncher.terminateWithEscalation(process)
            stdoutPipe.fileHandleForReading.readabilityHandler = nil
            stderrPipe.fileHandleForReading.readabilityHandler = nil
            throw GitHubCommandRunnerProcessError.timedOut
        }

        // 終了直前のバースト出力をハンドラがEOFまで読み切るのを待ってから結果を確定する。
        // 孫プロセスがpipeを保持し続ける場合に備えて待ちは有限にする。
        _ = stdoutEOFSemaphore.wait(timeout: .now() + 2)
        _ = stderrEOFSemaphore.wait(timeout: .now() + 2)
        stdoutPipe.fileHandleForReading.readabilityHandler = nil
        stderrPipe.fileHandleForReading.readabilityHandler = nil

        return GitHubCommandResult(
            stdout: stdout.data(),
            stderr: stderr.data(),
            exitCode: process.terminationStatus
        )
    }
}

nonisolated private enum GitHubCommandRunnerProcessError: LocalizedError {
    case timedOut

    var errorDescription: String? {
        switch self {
        case .timedOut:
            "GitHub CLI command timed out."
        }
    }
}

nonisolated private final class GitHubLoginPromptOutputObserver: @unchecked Sendable {
    private let lock = NSLock()
    private let promptHandler: @Sendable (GitHubLoginDevicePrompt) -> Void
    private var outputBuffer = ""
    private var didSendPrompt = false

    init(promptHandler: @escaping @Sendable (GitHubLoginDevicePrompt) -> Void) {
        self.promptHandler = promptHandler
    }

    func append(_ data: Data) {
        guard let chunk = String(data: data, encoding: .utf8),
              !chunk.isEmpty else {
            return
        }

        var prompt: GitHubLoginDevicePrompt?
        lock.lock()
        if !didSendPrompt {
            outputBuffer.append(chunk)
            if outputBuffer.count > 8_000 {
                outputBuffer = String(outputBuffer.suffix(8_000))
            }
            prompt = Self.devicePrompt(in: outputBuffer)
            if prompt != nil {
                didSendPrompt = true
            }
        }
        lock.unlock()

        if let prompt {
            promptHandler(prompt)
        }
    }

    private static func devicePrompt(in output: String) -> GitHubLoginDevicePrompt? {
        guard let userCode = firstMatch(
            pattern: #"(?i)(?:one-time code|code):\s*([A-Z0-9]{4}-[A-Z0-9]{4}|[A-Z0-9-]{6,})"#,
            in: output,
            captureGroup: 1
        ) else {
            return nil
        }

        let urlString = firstMatch(
            pattern: #"https://github\.com/login/device(?:\?[^\s]+)?"#,
            in: output,
            captureGroup: 0
        ) ?? "https://github.com/login/device"

        guard let verificationURL = URL(string: urlString) else {
            return nil
        }

        return GitHubLoginDevicePrompt(
            userCode: userCode,
            verificationURL: verificationURL
        )
    }

    private static func firstMatch(
        pattern: String,
        in output: String,
        captureGroup: Int
    ) -> String? {
        guard let regularExpression = try? NSRegularExpression(pattern: pattern) else {
            return nil
        }

        let range = NSRange(output.startIndex..<output.endIndex, in: output)
        guard let match = regularExpression.firstMatch(in: output, range: range),
              captureGroup < match.numberOfRanges else {
            return nil
        }

        let matchRange = match.range(at: captureGroup)
        guard let range = Range(matchRange, in: output) else {
            return nil
        }

        return String(output[range])
    }
}

nonisolated private final class GitHubLockedData: @unchecked Sendable {
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
