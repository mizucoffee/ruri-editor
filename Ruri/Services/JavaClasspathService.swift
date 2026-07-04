//
//  JavaClasspathService.swift
//  ruri
//

import Foundation

actor JavaClasspathService {
    private struct CacheEntry {
        var classpath: [URL]
        var diagnostics: [String]
    }

    private let runner: JavaClasspathCommandRunning
    private var cacheByProjectURL: [URL: CacheEntry] = [:]
    private var tasksByProjectURL: [URL: Task<Void, Never>] = [:]
    private var classpathPreparationTail: Task<Void, Never>?

    init(runner: JavaClasspathCommandRunning = JavaClasspathCommandRunner()) {
        self.runner = runner
    }

    func prepare(projectURL: URL, force: Bool = false) {
        let projectURL = projectURL.standardizedFileURL
        if !force, cacheByProjectURL[projectURL] != nil { return }
        if tasksByProjectURL[projectURL] != nil { return }

        let previousTask = classpathPreparationTail
        let task = Task { [weak self] in
            await previousTask?.value
            guard let self else { return }
            let result = await self.resolveClasspath(projectURL: projectURL)
            await self.store(result, projectURL: projectURL)
        }
        tasksByProjectURL[projectURL] = task
        classpathPreparationTail = task
    }

    func classpath(projectURL: URL) -> [URL] {
        cacheByProjectURL[projectURL.standardizedFileURL]?.classpath ?? []
    }

    func diagnostics(projectURL: URL) -> [String] {
        cacheByProjectURL[projectURL.standardizedFileURL]?.diagnostics ?? []
    }

    func stopPreparing(projectURL: URL) {
        let projectURL = projectURL.standardizedFileURL
        tasksByProjectURL.removeValue(forKey: projectURL)?.cancel()
        cacheByProjectURL.removeValue(forKey: projectURL)
    }

    func invalidateSourceFile(projectURL: URL, fileURL: URL) {
        _ = fileURL
        prepare(projectURL: projectURL)
    }

    private func store(_ result: CacheEntry, projectURL: URL) {
        cacheByProjectURL[projectURL] = result
        tasksByProjectURL[projectURL] = nil
    }

    private func resolveClasspath(projectURL: URL) async -> CacheEntry {
        let runner = self.runner
        return await Task.detached(priority: .utility) {
            var diagnostics: [String] = []
            var classpath: [URL] = []

            if let gradleCommand = JavaBuildToolResolver.gradleCommand(projectURL: projectURL) {
                do {
                    classpath.append(contentsOf: try runner.gradleClasspath(command: gradleCommand, projectURL: projectURL))
                } catch {
                    diagnostics.append("Gradle classpath unavailable: \(error.localizedDescription)")
                }
            }

            if let mavenCommand = JavaBuildToolResolver.mavenCommand(projectURL: projectURL) {
                do {
                    classpath.append(contentsOf: try runner.mavenClasspath(command: mavenCommand, projectURL: projectURL))
                } catch {
                    diagnostics.append("Maven classpath unavailable: \(error.localizedDescription)")
                }
            }

            return CacheEntry(
                classpath: uniqueExistingFiles(classpath),
                diagnostics: diagnostics
            )
        }.value
    }
}

nonisolated protocol JavaClasspathCommandRunning: Sendable {
    func gradleClasspath(command: JavaBuildToolCommand, projectURL: URL) throws -> [URL]
    func mavenClasspath(command: JavaBuildToolCommand, projectURL: URL) throws -> [URL]
}

nonisolated struct JavaBuildToolCommand: Equatable, Sendable {
    let executableURL: URL
    let argumentsPrefix: [String]
}

nonisolated struct JavaBuildToolResolver {
    static func gradleCommand(projectURL: URL) -> JavaBuildToolCommand? {
        let wrapperURL = projectURL.appending(path: "gradlew")
        if FileManager.default.isExecutableFile(atPath: wrapperURL.path(percentEncoded: false)) {
            return JavaBuildToolCommand(executableURL: wrapperURL, argumentsPrefix: [])
        }

        guard hasFile(named: "build.gradle", or: "build.gradle.kts", in: projectURL),
              let gradleURL = executableURL(named: "gradle") else {
            return nil
        }
        return JavaBuildToolCommand(executableURL: gradleURL, argumentsPrefix: [])
    }

    static func mavenCommand(projectURL: URL) -> JavaBuildToolCommand? {
        let wrapperURL = projectURL.appending(path: "mvnw")
        if FileManager.default.isExecutableFile(atPath: wrapperURL.path(percentEncoded: false)) {
            return JavaBuildToolCommand(executableURL: wrapperURL, argumentsPrefix: [])
        }

        guard FileManager.default.fileExists(atPath: projectURL.appending(path: "pom.xml").path(percentEncoded: false)),
              let mavenURL = executableURL(named: "mvn") else {
            return nil
        }
        return JavaBuildToolCommand(executableURL: mavenURL, argumentsPrefix: [])
    }

    private static func hasFile(named firstName: String, or secondName: String, in projectURL: URL) -> Bool {
        FileManager.default.fileExists(atPath: projectURL.appending(path: firstName).path(percentEncoded: false))
            || FileManager.default.fileExists(atPath: projectURL.appending(path: secondName).path(percentEncoded: false))
    }

    private static func executableURL(named executableName: String) -> URL? {
        let directories = (ProcessInfo.processInfo.environment["PATH"] ?? "")
            .split(separator: ":")
            .map(String.init) + ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin"]
        var seen = Set<String>()
        for directory in directories where seen.insert(directory).inserted {
            let url = URL(filePath: directory).appending(path: executableName)
            if FileManager.default.isExecutableFile(atPath: url.path(percentEncoded: false)) {
                return url.standardizedFileURL
            }
        }
        return nil
    }
}

nonisolated struct JavaClasspathCommandRunner: JavaClasspathCommandRunning {
    func gradleClasspath(command: JavaBuildToolCommand, projectURL: URL) throws -> [URL] {
        let initScriptURL = FileManager.default.temporaryDirectory
            .appending(path: "ruri-gradle-classpath-\(UUID().uuidString).gradle")
        let outputURL = FileManager.default.temporaryDirectory
            .appending(path: "ruri-gradle-classpath-\(UUID().uuidString).txt")
        defer {
            try? FileManager.default.removeItem(at: initScriptURL)
            try? FileManager.default.removeItem(at: outputURL)
        }

        try Self.gradleInitScript(outputPath: outputURL.path(percentEncoded: false))
            .write(to: initScriptURL, atomically: true, encoding: .utf8)

        let result = try Self.run(
            command: command,
            arguments: [
                "--quiet",
                "--init-script", initScriptURL.path(percentEncoded: false),
                "ruriPrintJavaClasspath"
            ],
            projectURL: projectURL,
            timeout: 60
        )
        guard result.exitCode == 0 else {
            throw JavaSymbolResolverError(message: result.stderrString)
        }

        return try Self.classpathURLs(from: outputURL)
    }

    func mavenClasspath(command: JavaBuildToolCommand, projectURL: URL) throws -> [URL] {
        let outputURL = FileManager.default.temporaryDirectory
            .appending(path: "ruri-maven-classpath-\(UUID().uuidString).txt")
        defer {
            try? FileManager.default.removeItem(at: outputURL)
        }

        let result = try Self.run(
            command: command,
            arguments: [
                "--quiet",
                "dependency:build-classpath",
                "-Dmdep.outputFile=\(outputURL.path(percentEncoded: false))"
            ],
            projectURL: projectURL,
            timeout: 60
        )
        guard result.exitCode == 0 else {
            throw JavaSymbolResolverError(message: result.stderrString)
        }

        return try Self.classpathURLs(from: outputURL)
    }

    private static func gradleInitScript(outputPath: String) -> String {
        """
        allprojects {
            tasks.register("ruriPrintJavaClasspath") {
                doLast {
                    def entries = new LinkedHashSet<String>()
                    plugins.withType(JavaPlugin) {
                        sourceSets.main.compileClasspath.each { entries.add(it.absolutePath) }
                    }
                    rootProject.file("\(outputPath.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\""))").text = entries.join(File.pathSeparator)
                }
            }
        }
        """
    }

    private static func classpathURLs(from outputURL: URL) throws -> [URL] {
        guard FileManager.default.fileExists(atPath: outputURL.path(percentEncoded: false)) else {
            return []
        }

        let text = try String(contentsOf: outputURL, encoding: .utf8)
        return text
            .split(separator: ":")
            .map(String.init)
            .filter { !$0.isEmpty }
            .map { URL(filePath: $0).standardizedFileURL }
    }

    private static func run(
        command: JavaBuildToolCommand,
        arguments: [String],
        projectURL: URL,
        timeout: TimeInterval
    ) throws -> JavaClasspathCommandResult {
        let process = Process()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        let stdout = JavaClasspathLockedData()
        let stderr = JavaClasspathLockedData()
        let terminationSemaphore = DispatchSemaphore(value: 0)

        process.executableURL = command.executableURL
        process.arguments = command.argumentsPrefix + arguments
        process.currentDirectoryURL = projectURL
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
            throw error
        }

        if terminationSemaphore.wait(timeout: .now() + timeout) == .timedOut {
            SafeProcessLauncher.terminateWithEscalation(process)
            cleanup(stdoutPipe: stdoutPipe, stderrPipe: stderrPipe)
            throw JavaSymbolResolverError(message: "Classpath command timed out.")
        }

        // 終了直前のバースト出力をハンドラがEOFまで読み切るのを待ってから結果を確定する。
        // 孫プロセスがpipeを保持し続ける場合に備えて待ちは有限にする。
        _ = stdoutEOFSemaphore.wait(timeout: .now() + 2)
        _ = stderrEOFSemaphore.wait(timeout: .now() + 2)
        cleanup(stdoutPipe: stdoutPipe, stderrPipe: stderrPipe)

        return JavaClasspathCommandResult(
            stdout: stdout.data(),
            stderr: stderr.data(),
            exitCode: process.terminationStatus
        )
    }

    private static func cleanup(stdoutPipe: Pipe, stderrPipe: Pipe) {
        stdoutPipe.fileHandleForReading.readabilityHandler = nil
        stderrPipe.fileHandleForReading.readabilityHandler = nil
    }
}

nonisolated private struct JavaClasspathCommandResult: Sendable {
    let stdout: Data
    let stderr: Data
    let exitCode: Int32

    var stderrString: String {
        String(data: stderr, encoding: .utf8) ?? ""
    }
}

nonisolated private final class JavaClasspathLockedData: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = Data()

    func append(_ data: Data) {
        lock.lock()
        storage.append(data)
        lock.unlock()
    }

    func data() -> Data {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
}

nonisolated private func uniqueExistingFiles(_ urls: [URL]) -> [URL] {
    var seen = Set<String>()
    var result: [URL] = []
    for url in urls {
        let standardizedURL = url.standardizedFileURL
        let path = standardizedURL.path(percentEncoded: false)
        guard seen.insert(path).inserted,
              FileManager.default.fileExists(atPath: path) else {
            continue
        }
        result.append(standardizedURL)
    }
    return result
}
