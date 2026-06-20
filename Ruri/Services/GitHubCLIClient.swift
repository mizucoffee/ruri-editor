//
//  GitHubCLIClient.swift
//  ruri
//

import Foundation

nonisolated enum GitHubCLIOptionalIgnoredReason: Equatable, Sendable {
    case githubCLINotInstalled
    case unauthenticated
}

nonisolated enum GitHubCLIOptionalCommandResult: Equatable, Sendable {
    case success(GitHubCommandResult)
    case ignored(GitHubCLIOptionalIgnoredReason)
    case failed(String)
}

nonisolated enum GitHubCLIClientError: LocalizedError, Equatable {
    case githubCLINotInstalled

    var errorDescription: String? {
        switch self {
        case .githubCLINotInstalled:
            "GitHub CLI is not installed."
        }
    }
}

nonisolated struct GitHubCLIClient: Sendable {
    private let executableURL: URL?
    private let commandRunner: any GitHubCommandRunning
    private let commandTimeout: TimeInterval

    init(
        executableURL: URL? = GitHubExecutableResolver().executableURL(named: "gh"),
        commandRunner: any GitHubCommandRunning = ProcessGitHubCommandRunner(),
        commandTimeout: TimeInterval = 20
    ) {
        self.executableURL = executableURL
        self.commandRunner = commandRunner
        self.commandTimeout = commandTimeout
    }

    var isAvailable: Bool {
        executableURL != nil
    }

    func run(
        arguments: [String],
        currentDirectoryURL: URL? = nil,
        environment: [String: String] = [:],
        standardInput: Data? = nil,
        outputHandler: (@Sendable (Data) -> Void)? = nil,
        timeout: TimeInterval? = nil
    ) async throws -> GitHubCommandResult {
        guard let executableURL else {
            throw GitHubCLIClientError.githubCLINotInstalled
        }

        return try await commandRunner.run(
            executableURL: executableURL,
            arguments: arguments,
            currentDirectoryURL: currentDirectoryURL,
            environment: environment,
            standardInput: standardInput,
            outputHandler: outputHandler,
            timeout: timeout ?? commandTimeout
        )
    }

    func runOptionalFeatureCommand(
        arguments: [String],
        currentDirectoryURL: URL? = nil,
        environment: [String: String] = [:],
        standardInput: Data? = nil,
        outputHandler: (@Sendable (Data) -> Void)? = nil,
        timeout: TimeInterval? = nil
    ) async -> GitHubCLIOptionalCommandResult {
        guard executableURL != nil else {
            return .ignored(.githubCLINotInstalled)
        }

        do {
            let result = try await run(
                arguments: arguments,
                currentDirectoryURL: currentDirectoryURL,
                environment: environment,
                standardInput: standardInput,
                outputHandler: outputHandler,
                timeout: timeout
            )

            guard result.exitCode != 0 else {
                return .success(result)
            }

            let message = Self.commandErrorMessage(from: result)
            if Self.isUnauthenticatedMessage(message) {
                return .ignored(.unauthenticated)
            }

            return .failed(message)
        } catch {
            let message = error.localizedDescription
            if Self.isUnauthenticatedMessage(message) {
                return .ignored(.unauthenticated)
            }

            return .failed(message)
        }
    }

    static func commandErrorMessage(from result: GitHubCommandResult) -> String {
        let stderr = outputString(from: result.stderr)
        if !stderr.isEmpty {
            return stderr
        }

        let stdout = outputString(from: result.stdout)
        if !stdout.isEmpty {
            return stdout
        }

        return "GitHub CLI exited with status \(result.exitCode)."
    }

    static func isUnauthenticatedMessage(_ message: String) -> Bool {
        let lowercasedMessage = message.lowercased()
        return lowercasedMessage.contains("not logged in")
            || lowercasedMessage.contains("gh auth login")
            || lowercasedMessage.contains("authentication required")
            || lowercasedMessage.contains("bad credentials")
            || lowercasedMessage.contains("token") && lowercasedMessage.contains("invalid")
            || lowercasedMessage.contains("http 401")
    }

    private static func outputString(from data: Data) -> String {
        String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
}
