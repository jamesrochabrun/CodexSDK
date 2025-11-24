//
//  CodexExecError.swift
//  CodexSDK
//
//  Created by James Rochabrun on 11/23/25.
//

import Foundation

public enum CodexExecError: Error, CustomStringConvertible {
  case promptRequired
  case commandNotFound(String)
  case processLaunchFailed(String)
  case nonZeroExit(exitCode: Int32, stderr: String)
  case timeout(TimeInterval)
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
