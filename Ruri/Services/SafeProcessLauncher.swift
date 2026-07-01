//
//  SafeProcessLauncher.swift
//  ruri
//

import Foundation

nonisolated struct ProcessLaunchError: LocalizedError, Equatable, Sendable {
    let message: String

    var errorDescription: String? {
        message
    }
}

nonisolated enum SafeProcessLauncher {
    static func run(_ process: Process, fileManager: FileManager = .default) throws {
        try validate(process, fileManager: fileManager)

        try catchObjectiveCException {
            try process.run()
        }
    }

    static func catchObjectiveCExceptionForTesting(_ block: () -> Void) throws {
        try catchObjectiveCException(block)
    }

    private static func catchObjectiveCException(_ block: () throws -> Void) throws {
        var swiftError: Error?
        do {
            try RuriObjCExceptionCatcher.`try` {
                do {
                    try block()
                } catch {
                    swiftError = error
                }
            }
        } catch {
            throw ProcessLaunchError(message: error.localizedDescription)
        }

        if let swiftError {
            throw ProcessLaunchError(message: swiftError.localizedDescription)
        }
    }

    private static func validate(_ process: Process, fileManager: FileManager) throws {
        guard let executableURL = process.executableURL else {
            throw ProcessLaunchError(message: "Process executable is not set.")
        }

        let executablePath = executableURL.path(percentEncoded: false)
        guard fileManager.isExecutableFile(atPath: executablePath) else {
            throw ProcessLaunchError(message: "\(executablePath) is not executable.")
        }

        guard let currentDirectoryURL = process.currentDirectoryURL else { return }

        let directoryPath = currentDirectoryURL.path(percentEncoded: false)
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: directoryPath, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            throw ProcessLaunchError(message: "\(directoryPath) is not a directory.")
        }
    }
}
