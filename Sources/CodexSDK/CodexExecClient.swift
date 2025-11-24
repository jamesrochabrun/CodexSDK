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
  
  /// Stream stdout/stderr (and optional JSON events) for a running Process, apply timeout, and collect results.
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
    
    actor TimeoutFlag {
      private(set) var fired = false
      func mark() { fired = true }
      func value() -> Bool { fired }
    }
    let timeoutFlag = TimeoutFlag()
    
    let timeoutTask = options.timeout.map { timeout in
      Task { [weak process] in
        try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
        guard let process, process.isRunning else { return }
        await timeoutFlag.mark()
        process.terminate()
        if process.isRunning {
          process.interrupt()
        }
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
    
    if await timeoutFlag.value() {
      throw CodexExecError.timeout(options.timeout ?? 0)
    }
    
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
  
  /// Decode a single JSON event line; returns nil on parse failure.
  /// - Parameters:
  ///   - line: Raw JSONL line.
  ///   - decoder: JSON decoder to use.
  /// - Returns: Parsed `CodexJSONEvent` with `rawLine` set, or nil.
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
