import Foundation

public final class CodexExecClient: @unchecked Sendable {
  private let configuration: CodexExecConfiguration
  private let decoder: JSONDecoder
  
  /// Create a Codex exec client.
  /// - Parameter configuration: Shell/command/environment configuration. Defaults to `CodexExecConfiguration.default`.
  public init(configuration: CodexExecConfiguration = .default) {
    self.configuration = configuration
    self.decoder = JSONDecoder()
    self.decoder.keyDecodingStrategy = .convertFromSnakeCase
  }
  
  /// Run a Codex exec turn.
  /// - Parameters:
  ///   - prompt: Text to send. If `options.promptViaStdin` is true (default), this is piped via stdin; otherwise passed as an argument.
  ///   - options: CLI flag mapping (sandbox/model/jsonEvents/etc.). For resume, drop flags the CLI rejects (`jsonEvents`, `sandbox`, `model`, `fullAuto`, `mcpConfigPath`/`mcpServers`).
  ///   - onEvent: Optional streaming callback for stdout/stderr/JSON events (first turn only for JSON).
  /// - Returns: `CodexExecResult` containing stdout/stderr/events and exit info.
  /// - Throws: `CodexExecError` on invalid prompt, missing binary, non-zero exit, timeout, or config/JSON errors.
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
  
  /// Internal executor that builds the command string and spawns the process.
  /// - Parameters:
  ///   - prompt: Text to send.
  ///   - options: Exec options (already validated for resume).
  ///   - onEvent: Streaming callback.
  /// - Returns: `CodexExecResult`.
  /// - Throws: `CodexExecError`.
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
    
    let commandString = try buildCommand(
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
        // Prepend additionalPaths so they take priority over shell PATH
        environment["PATH"] = "\(combined):\(current)"
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
  
  /// Stream stdout/stderr (and optional JSON events) for a running Process, apply timeout, and collect results.
  /// Uses readabilityHandler for immediate data delivery (no buffering).
  /// - Parameters:
  ///   - process: Spawned `Process`.
  ///   - stdoutPipe: Pipe for stdout.
  ///   - stderrPipe: Pipe for stderr.
  ///   - commandString: Human-readable command (for error reporting).
  ///   - options: Exec options (timeout, jsonEvents, etc.).
  ///   - onEvent: Streaming callback.
  /// - Returns: `CodexExecResult`.
  /// - Throws: `CodexExecError` on timeout, non-zero exit, or launch failure.
  private func runProcess(
    process: Process,
    stdoutPipe: Pipe,
    stderrPipe: Pipe,
    commandString: String,
    options: CodexExecOptions,
    onEvent: (@Sendable (CodexExecEvent) -> Void)?
  ) async throws -> CodexExecResult {
    let decoder = self.decoder
    let enableLogging = configuration.enableDebugLogging

    let stdoutHandle = stdoutPipe.fileHandleForReading
    let stderrHandle = stderrPipe.fileHandleForReading

    // Thread-safe collectors for stdout/stderr/events
    let collector = StreamCollector()
    let stdoutBuffer = StreamBuffer()
    let stderrBuffer = StreamBuffer()

    // Timeout tracking
    actor TimeoutFlag {
      private(set) var fired = false
      func mark() { fired = true }
      func value() -> Bool { fired }
    }
    let timeoutFlag = TimeoutFlag()

    return try await withCheckedThrowingContinuation { continuation in
      // Set up stdout readability handler - fires immediately when data arrives
      stdoutHandle.readabilityHandler = { [weak self] fileHandle in
        let data = fileHandle.availableData
        guard !data.isEmpty else {
          // EOF reached
          fileHandle.readabilityHandler = nil
          // Process any remaining data in buffer
          Task {
            if let remaining = await stdoutBuffer.getString(), !remaining.isEmpty {
              await collector.addStdout(remaining)
              if options.jsonEvents,
                 let event = self?.decodeJSONEvent(line: remaining, decoder: decoder) {
                await collector.addEvent(event)
                onEvent?(.jsonEvent(event))
              } else {
                onEvent?(.stdout(remaining))
              }
            }
          }
          return
        }

        Task {
          await stdoutBuffer.append(data)

          guard let outputString = await stdoutBuffer.getString() else { return }

          let lines = outputString.components(separatedBy: .newlines)

          // Process complete lines (all except potentially incomplete last one)
          if lines.count > 1 {
            // Keep only incomplete last line in buffer
            if let lastLine = lines.last, !lastLine.isEmpty {
              if let lastLineData = lastLine.data(using: .utf8) {
                await stdoutBuffer.set(lastLineData)
              }
            } else {
              await stdoutBuffer.set(Data())
            }

            // Process all complete lines immediately
            for i in 0..<lines.count-1 where !lines[i].isEmpty {
              let line = lines[i]
              await collector.addStdout(line)

              if enableLogging {
                print("[CodexSDK] 📥 STDOUT: \(line)")
              }

              if options.jsonEvents,
                 let event = self?.decodeJSONEvent(line: line, decoder: decoder) {
                if enableLogging {
                  print("[CodexSDK] 📦 JSON Event: \(event.type)")
                }
                await collector.addEvent(event)
                onEvent?(.jsonEvent(event))
              } else {
                onEvent?(.stdout(line))
              }
            }
          }
        }
      }

      // Set up stderr readability handler
      stderrHandle.readabilityHandler = { fileHandle in
        let data = fileHandle.availableData
        guard !data.isEmpty else {
          fileHandle.readabilityHandler = nil
          Task {
            if let remaining = await stderrBuffer.getString(), !remaining.isEmpty {
              await collector.addStderr(remaining)
              onEvent?(.stderr(remaining))
            }
          }
          return
        }

        Task {
          await stderrBuffer.append(data)

          guard let outputString = await stderrBuffer.getString() else { return }

          let lines = outputString.components(separatedBy: .newlines)

          if lines.count > 1 {
            if let lastLine = lines.last, !lastLine.isEmpty {
              if let lastLineData = lastLine.data(using: .utf8) {
                await stderrBuffer.set(lastLineData)
              }
            } else {
              await stderrBuffer.set(Data())
            }

            for i in 0..<lines.count-1 where !lines[i].isEmpty {
              let line = lines[i]
              await collector.addStderr(line)
              if enableLogging {
                print("[CodexSDK] ⚠️ STDERR: \(line)")
              }
              onEvent?(.stderr(line))
            }
          }
        }
      }

      // Set up timeout task
      var timeoutTask: Task<Void, Never>?
      if let timeout = options.timeout {
        timeoutTask = Task { [weak process] in
          try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
          guard let process, process.isRunning else { return }
          await timeoutFlag.mark()
          process.terminate()
          if process.isRunning {
            process.interrupt()
          }
        }
      }

      // Handle process termination
      process.terminationHandler = { [collector, timeoutFlag, timeoutTask] terminatedProcess in
        // Clean up handlers
        stdoutHandle.readabilityHandler = nil
        stderrHandle.readabilityHandler = nil
        timeoutTask?.cancel()

        Task {
          // Small delay to ensure all readability handlers have processed
          try? await Task.sleep(nanoseconds: 50_000_000) // 50ms

          let snapshot = await collector.snapshot()
          let stdoutString = snapshot.stdout.joined(separator: "\n")
          let stderrString = snapshot.stderr.joined(separator: "\n")

          if await timeoutFlag.value() {
            continuation.resume(throwing: CodexExecError.timeout(options.timeout ?? 0))
            return
          }

          if terminatedProcess.terminationStatus != 0 {
            continuation.resume(throwing: CodexExecError.nonZeroExit(
              exitCode: terminatedProcess.terminationStatus,
              stderr: stderrString
            ))
            return
          }

          let result = CodexExecResult(
            command: commandString,
            stdout: stdoutString,
            stderr: stderrString,
            exitCode: terminatedProcess.terminationStatus,
            events: snapshot.events
          )
          continuation.resume(returning: result)
        }
      }

      // Launch the process
      do {
        try process.run()
      } catch {
        stdoutHandle.readabilityHandler = nil
        stderrHandle.readabilityHandler = nil
        timeoutTask?.cancel()

        if (error as NSError).code == NSFileNoSuchFileError {
          continuation.resume(throwing: CodexExecError.commandNotFound(commandString))
        } else {
          continuation.resume(throwing: CodexExecError.processLaunchFailed(error.localizedDescription))
        }
      }
    }
  }

  /// Thread-safe buffer for accumulating streaming data
  private actor StreamBuffer {
    private var buffer = Data()

    func append(_ data: Data) {
      buffer.append(data)
    }

    func set(_ data: Data) {
      buffer = data
    }

    func isEmpty() -> Bool {
      return buffer.isEmpty
    }

    func getString() -> String? {
      return String(data: buffer, encoding: .utf8)
    }
  }

  /// Thread-safe collector for stdout/stderr/events
  private actor StreamCollector {
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
  
  /// Decode a single JSON event line; returns nil on parse failure.
  /// - Parameters:
  ///   - line: Raw JSONL line.
  ///   - decoder: JSON decoder to use.
  /// - Returns: Parsed `CodexJSONEvent` with `rawLine` set, or nil.
  private func decodeJSONEvent(line: String, decoder: JSONDecoder) -> CodexJSONEvent? {
    // Skip empty lines or non-JSON lines
    let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty, trimmed.hasPrefix("{") else {
      return nil
    }

    guard let data = trimmed.data(using: .utf8) else { return nil }
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
  
  /// Build the shell command string for `codex exec`, including resume logic and prompt handling.
  /// - Parameters:
  ///   - prompt: Text to send (passed as arg or stdin marker).
  ///   - options: Exec options to serialize into CLI flags.
  ///   - sendPromptViaStdin: If true, append `-` and pipe prompt via stdin.
  /// - Returns: Shell-escaped command string.
  /// - Throws: `CodexExecError.invalidConfiguration` if MCP encoding fails.
  private func buildCommand(
    prompt: String,
    options: CodexExecOptions,
    sendPromptViaStdin: Bool
  ) throws -> String {
    var parts: [String] = [shellEscape(configuration.command), "exec"]

    if let sessionId = options.resumeSessionId {
      parts.append(contentsOf: ["resume", shellEscape(sessionId)])
    } else if options.resumeLastSession {
      parts.append(contentsOf: ["resume", "--last"])
    }

    parts.append(contentsOf: try options.buildArgumentList())

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
