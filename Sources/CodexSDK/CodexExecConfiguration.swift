//
//  CodexExecConfiguration.swift
//  CodexSDK
//
//  Created by James Rochabrun on 11/23/25.
//

import Foundation

/// Process/shell configuration for invoking `codex exec`.
public struct CodexExecConfiguration {
  /// Command/binary to run (e.g., `codex` or a full path to the CLI).
  public var command: String
  /// Working directory to set before launching the process (optional).
  public var workingDirectory: String?
  /// Additional entries appended to `PATH` for the child process.
  public var additionalPaths: [String]
  /// Environment overrides for the child process.
  public var environment: [String: String]
  /// Shell used to launch the command (default `/bin/zsh`).
  public var shell: String
  /// Whether to launch the shell as a login shell (adds shell startup files).
  public var useLoginShell: Bool
  /// Enable verbose debug logging to stdout/stderr.
  public var enableDebugLogging: Bool
  
  /// Create a configuration.
  /// - Parameters:
  ///   - command: Command/binary to invoke (default: `codex`).
  ///   - workingDirectory: Optional working directory.
  ///   - additionalPaths: Extra PATH entries for the child process.
  ///   - environment: Environment overrides for the child process.
  ///   - shell: Shell to execute (default: `/bin/zsh`).
  ///   - useLoginShell: Launch shell with `-l` (default: true).
  ///   - enableDebugLogging: Emit debug logs (default: false).
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
  
  /// Default configuration (`codex`, login shell, no extra PATH/ENV).
  public static var `default`: CodexExecConfiguration {
    CodexExecConfiguration()
  }
}
