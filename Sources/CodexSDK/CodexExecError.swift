//
//  CodexExecError.swift
//  CodexSDK
//
//  Created by James Rochabrun on 11/23/25.
//

import Foundation

/// Errors surfaced by `CodexExecClient`.
public enum CodexExecError: Error, CustomStringConvertible {
  /// Missing prompt when required.
  case promptRequired
  /// Codex CLI binary not found in PATH or at provided command.
  case commandNotFound(String)
  /// Process could not launch (e.g., permissions, missing shell).
  case processLaunchFailed(String)
  /// Process exited non-zero with stderr details.
  case nonZeroExit(exitCode: Int32, stderr: String)
  /// Process terminated after exceeding timeout (seconds).
  case timeout(TimeInterval)
  /// Invalid SDK/CLI configuration (e.g., MCP encoding/write failure).
  case invalidConfiguration(String)
  
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
    case .invalidConfiguration(let message):
      return "Invalid configuration: \(message)"
    }
  }
}

extension CodexExecError: LocalizedError {
  public var errorDescription: String? { description }
}
