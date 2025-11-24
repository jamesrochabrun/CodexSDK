import Foundation

public struct CodexExecConfiguration {
    public var command: String
    public var workingDirectory: String?
    public var additionalPaths: [String]
    public var environment: [String: String]
    public var shell: String
    public var useLoginShell: Bool
    public var enableDebugLogging: Bool

    public init(
        command: String = "codex",
        workingDirectory: String? = nil,
        additionalPaths: [String] = [],
        environment: [String: String] = [:],
        shell: String = "/bin/zsh",
        useLoginShell: Bool = true,
        enableDebugLogging: Bool = false
    ) {
        self.command = command
        self.workingDirectory = workingDirectory
        self.additionalPaths = additionalPaths
        self.environment = environment
        self.shell = shell
        self.useLoginShell = useLoginShell
        self.enableDebugLogging = enableDebugLogging
    }

    public static var `default`: CodexExecConfiguration {
        CodexExecConfiguration()
    }
}

public enum CodexSandboxPolicy: String, Sendable {
    case readOnly = "read-only"
    case workspaceWrite = "workspace-write"
    case dangerFullAccess = "danger-full-access"
}

public enum CodexApprovalMode: String, Sendable {
    case untrusted
    case onFailure = "on-failure"
    case onRequest = "on-request"
    case never
}

public enum CodexColorMode: String, Sendable {
    case always
    case never
    case auto
}

public enum CodexExecError: Error, CustomStringConvertible {
    case promptRequired
    case commandNotFound(String)
    case processLaunchFailed(String)
    case nonZeroExit(exitCode: Int32, stderr: String)
    case timeout(TimeInterval)

    public var description: String {
        switch self {
        case .promptRequired:
            return "A prompt is required to run codex exec."
        case .commandNotFound(let command):
            return "Codex CLI command '\(command)' was not found in PATH."
        case .processLaunchFailed(let message):
            return "Failed to launch process: \(message)"
        case .nonZeroExit(let code, let stderr):
            return "codex exec exited with code \(code): \(stderr)"
        case .timeout(let seconds):
            return "codex exec timed out after \(seconds) seconds."
        }
    }
}

extension CodexExecError: LocalizedError {
    public var errorDescription: String? { description }
}

public struct CodexExecOptions: Sendable {
    public var model: String?
    public var profile: String?
    public var useOSSBackend: Bool = false
    public var sandbox: CodexSandboxPolicy?
    public var fullAuto: Bool = false
    public var yolo: Bool = false
    public var changeDirectory: String?
    public var additionalWriteDirectories: [String] = []
    public var skipGitRepoCheck: Bool = false
    public var enableSearch: Bool = false
    public var enableFeatures: [String] = []
    public var disableFeatures: [String] = []
    public var configOverrides: [String: String] = [:]
    public var jsonEvents: Bool = false
    public var outputSchema: String?
    public var outputFile: String?
    public var colorMode: CodexColorMode?
    public var imagePaths: [String] = []
    public var resumeSessionId: String?
    public var resumeLastSession: Bool = false
    public var promptViaStdin: Bool = true
    public var timeout: TimeInterval?
    public var extraFlags: [String] = []

    public init() {}

    fileprivate func buildArgumentList() -> [String] {
        var args: [String] = []

        for image in imagePaths {
            args.append("--image")
            args.append(shellEscape(image))
        }

        if let model {
            args.append("--model")
            args.append(shellEscape(model))
        }

        if let profile {
            args.append("--profile")
            args.append(shellEscape(profile))
        }

        if useOSSBackend {
            args.append("--oss")
        }

        if let sandbox {
            args.append("--sandbox")
            args.append(sandbox.rawValue)
        }

        if fullAuto {
            args.append("--full-auto")
        }

        if yolo {
            args.append("--dangerously-bypass-approvals-and-sandbox")
        }

        if let changeDirectory {
            args.append("--cd")
            args.append(shellEscape(changeDirectory))
        }

        for dir in additionalWriteDirectories {
            args.append("--add-dir")
            args.append(shellEscape(dir))
        }

        if skipGitRepoCheck {
            args.append("--skip-git-repo-check")
        }

        if enableSearch {
            args.append("--search")
        }

        for feature in enableFeatures {
            args.append("--enable")
            args.append(shellEscape(feature))
        }

        for feature in disableFeatures {
            args.append("--disable")
            args.append(shellEscape(feature))
        }

        for (key, value) in configOverrides {
            args.append("-c")
            args.append(shellEscape("\(key)=\(value)"))
        }

        if jsonEvents {
            args.append("--json")
        }

        if let outputSchema {
            args.append("--output-schema")
            args.append(shellEscape(outputSchema))
        }

        if let outputFile {
            args.append("--output-last-message")
            args.append(shellEscape(outputFile))
        }

        if let colorMode {
            args.append("--color")
            args.append(colorMode.rawValue)
        }

        args.append(contentsOf: extraFlags)

        return args
    }

    private func shellEscape(_ value: String) -> String {
        let escaped = value.replacingOccurrences(of: "'", with: "'\\''")
        return "'\(escaped)'"
    }
}

public struct CodexJSONEventItem: Decodable, Sendable {
    public let id: String?
    public let type: String?
    public let status: String?
    public let text: String?
    public let command: String?
}

public struct CodexUsage: Decodable, Sendable {
    public let inputTokens: Int?
    public let outputTokens: Int?
}

public struct CodexJSONEvent: Decodable, Sendable {
    public let type: String
    public let item: CodexJSONEventItem?
    public let error: String?
    public let text: String?
    public let usage: CodexUsage?
    public var rawLine: String?
}

public enum CodexExecEvent: Sendable {
    case stderr(String)
    case stdout(String)
    case jsonEvent(CodexJSONEvent)
}

public struct CodexExecResult: Sendable {
    public let command: String
    public let stdout: String
    public let stderr: String
    public let exitCode: Int32
    public let events: [CodexJSONEvent]
}

public final class CodexExecClient: @unchecked Sendable {
    private let configuration: CodexExecConfiguration
    private let decoder: JSONDecoder

    public init(configuration: CodexExecConfiguration = .default) {
        self.configuration = configuration
        self.decoder = JSONDecoder()
        self.decoder.keyDecodingStrategy = .convertFromSnakeCase
    }

    public func run(
        prompt: String,
        options: CodexExecOptions = CodexExecOptions(),
        onEvent: (@Sendable (CodexExecEvent) -> Void)? = nil
    ) async throws -> CodexExecResult {
        // Try once with requested options; if --json is not supported by the installed CLI, retry without it.
        do {
            return try await runInternal(prompt: prompt, options: options, onEvent: onEvent)
        } catch let error as CodexExecError {
            if case .nonZeroExit(_, let stderr) = error,
               options.jsonEvents,
               stderr.contains("unexpected argument '--json'") {
                var fallback = options
                fallback.jsonEvents = false
                onEvent?(.stderr("codex exec does not support --json; retrying without it"))
                return try await runInternal(prompt: prompt, options: fallback, onEvent: onEvent)
            }
            throw error
        }
    }

    private func runInternal(
        prompt: String,
        options: CodexExecOptions,
        onEvent: (@Sendable (CodexExecEvent) -> Void)?
    ) async throws -> CodexExecResult {
        let isResume = options.resumeSessionId != nil || options.resumeLastSession
        let shouldSendPromptViaStdin = options.promptViaStdin && (!prompt.isEmpty || isResume)

        guard shouldSendPromptViaStdin || !prompt.isEmpty else {
            throw CodexExecError.promptRequired
        }

        let commandString = buildCommand(
            prompt: prompt,
            options: options,
            sendPromptViaStdin: shouldSendPromptViaStdin
        )

        if configuration.enableDebugLogging {
            print("Executing: \(commandString)")
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: configuration.shell)
        var shellArguments = [String]()
        if configuration.useLoginShell {
            shellArguments.append("-l")
        }
        shellArguments.append(contentsOf: ["-c", commandString])
        process.arguments = shellArguments

        if let workingDirectory = configuration.workingDirectory {
            process.currentDirectoryURL = URL(fileURLWithPath: workingDirectory)
        }

        var environment = ProcessInfo.processInfo.environment
        if !configuration.additionalPaths.isEmpty {
            let combined = configuration.additionalPaths.joined(separator: ":")
            if let current = environment["PATH"], !current.isEmpty {
                environment["PATH"] = "\(current):\(combined)"
            } else {
                environment["PATH"] = combined
            }
        }
        configuration.environment.forEach { key, value in
            environment[key] = value
        }
        process.environment = environment

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        if shouldSendPromptViaStdin {
            let stdinPipe = Pipe()
            process.standardInput = stdinPipe
            if let data = prompt.data(using: .utf8) {
                try stdinPipe.fileHandleForWriting.write(contentsOf: data)
                stdinPipe.fileHandleForWriting.closeFile()
            }
        }

        return try await runProcess(
            process: process,
            stdoutPipe: stdoutPipe,
            stderrPipe: stderrPipe,
            commandString: commandString,
            options: options,
            onEvent: onEvent
        )
    }

    private func runProcess(
        process: Process,
        stdoutPipe: Pipe,
        stderrPipe: Pipe,
        commandString: String,
        options: CodexExecOptions,
        onEvent: (@Sendable (CodexExecEvent) -> Void)?
    ) async throws -> CodexExecResult {
        let decoder = self.decoder

        let stdoutHandle = stdoutPipe.fileHandleForReading
        let stderrHandle = stderrPipe.fileHandleForReading

        actor StreamCollector {
            private var stdoutLines = [String]()
            private var stderrLines = [String]()
            private var events = [CodexJSONEvent]()

            func addStdout(_ line: String) {
                stdoutLines.append(line)
            }

            func addStderr(_ line: String) {
                stderrLines.append(line)
            }

            func addEvent(_ event: CodexJSONEvent) {
                events.append(event)
            }

            func snapshot() -> (stdout: [String], stderr: [String], events: [CodexJSONEvent]) {
                (stdoutLines, stderrLines, events)
            }
        }

        let collector = StreamCollector()

        let stdoutTask = Task { () throws -> Void in
            for try await line in stdoutHandle.bytes.lines {
                let stringLine = String(line)
                await collector.addStdout(stringLine)

                if options.jsonEvents,
                   let event = self.decodeJSONEvent(line: stringLine, decoder: decoder) {
                    await collector.addEvent(event)
                    onEvent?(.jsonEvent(event))
                } else {
                    onEvent?(.stdout(stringLine))
                }
            }
        }

        let stderrTask = Task { () throws -> Void in
            for try await line in stderrHandle.bytes.lines {
                let stringLine = String(line)
                await collector.addStderr(stringLine)
                onEvent?(.stderr(stringLine))
            }
        }

        let timeoutTask = options.timeout.map { timeout in
            Task { [weak process] in
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                guard let process, process.isRunning else { return }
                process.terminate()
            }
        }

        do {
            try process.run()
        } catch {
            timeoutTask?.cancel()
            if (error as NSError).code == NSFileNoSuchFileError {
                throw CodexExecError.commandNotFound(commandString)
            } else {
                throw CodexExecError.processLaunchFailed(error.localizedDescription)
            }
        }

        let terminationStatus = await Task.detached { () -> Int32 in
            process.waitUntilExit()
            return process.terminationStatus
        }.value

        timeoutTask?.cancel()

        do { try await stdoutTask.value } catch { /* ignore stream errors */ }
        do { try await stderrTask.value } catch { /* ignore stream errors */ }

        let snapshot = await collector.snapshot()
        let stdoutString = snapshot.stdout.joined(separator: "\n")
        let stderrString = snapshot.stderr.joined(separator: "\n")

        if terminationStatus != 0 {
            throw CodexExecError.nonZeroExit(
                exitCode: terminationStatus,
                stderr: stderrString
            )
        }

        return CodexExecResult(
            command: commandString,
            stdout: stdoutString,
            stderr: stderrString,
            exitCode: terminationStatus,
            events: snapshot.events
        )
    }

    private func decodeJSONEvent(line: String, decoder: JSONDecoder) -> CodexJSONEvent? {
        guard let data = line.data(using: .utf8) else { return nil }
        do {
            var event = try decoder.decode(CodexJSONEvent.self, from: data)
            event.rawLine = line
            return event
        } catch {
            if configuration.enableDebugLogging {
                print("Failed to decode JSON event: \(error) for line: \(line)")
            }
            return nil
        }
    }

    private func buildCommand(
        prompt: String,
        options: CodexExecOptions,
        sendPromptViaStdin: Bool
    ) -> String {
        var parts: [String] = [configuration.command, "exec"]

        if let sessionId = options.resumeSessionId {
            parts.append(contentsOf: ["resume", shellEscape(sessionId)])
        } else if options.resumeLastSession {
            parts.append(contentsOf: ["resume", "--last"])
        }

        parts.append(contentsOf: options.buildArgumentList())

        if !prompt.isEmpty {
            if sendPromptViaStdin {
                parts.append("-")
            } else {
                parts.append(shellEscape(prompt))
            }
        }

        return parts.joined(separator: " ")
    }

    private func shellEscape(_ value: String) -> String {
        let escaped = value.replacingOccurrences(of: "'", with: "'\\''")
        return "'\(escaped)'"
    }
}
