//
//  TerminalShellResolver.swift
//  ruri
//

import Foundation

struct TerminalShellLaunchConfiguration: Equatable {
    let executable: String
    let arguments: [String]
    let execName: String

    init(shellPath: String) {
        executable = shellPath
        arguments = []

        let shellName = URL(filePath: shellPath).lastPathComponent
        execName = shellName.isEmpty ? shellPath : "-\(shellName)"
    }
}

struct TerminalShellResolver: Equatable {
    var environment: [String: String]
    var fallbackShellPath: String

    init(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fallbackShellPath: String = "/bin/zsh"
    ) {
        self.environment = environment
        self.fallbackShellPath = fallbackShellPath
    }

    func shellPath() -> String {
        let shell = environment["SHELL"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let shell,
              !shell.isEmpty else {
            return fallbackShellPath
        }

        return shell
    }
}
