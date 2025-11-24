//
//  CodexExecResult.swift
//  CodexSDK
//
//  Created by James Rochabrun on 11/23/25.
//

import Foundation

/// Result of a `codex exec` invocation.
public struct CodexExecResult: Sendable {
  /// Full command string executed.
  public let command: String
  /// Standard output (final answer or JSON events if `jsonEvents` enabled).
  public let stdout: String
  /// Standard error (logs/errors).
  public let stderr: String
  /// Process exit code.
  public let exitCode: Int32
  /// Parsed JSON events (when `jsonEvents` is true and accepted by the CLI).
  public let events: [CodexJSONEvent]
}

/// CLI sandbox policy.
public enum CodexSandboxPolicy: String, Sendable {
  case readOnly = "read-only"
  case workspaceWrite = "workspace-write"
  case dangerFullAccess = "danger-full-access"
}

/// Approval policy (passed via config override).
public enum CodexApprovalMode: String, Sendable {
  case untrusted
  case onFailure = "on-failure"
  case onRequest = "on-request"
  case never
}

/// Color output mode.
public enum CodexColorMode: String, Sendable {
  case always
  case never
  case auto
}

/// Item in a JSON event (e.g., agent_message, command_execution).
public struct CodexJSONEventItem: Decodable, Sendable {
  public let id: String?
  public let type: String?
  public let status: String?
  public let text: String?
  public let command: String?
}

/// Usage info from JSON events.
public struct CodexUsage: Decodable, Sendable {
  public let inputTokens: Int?
  public let outputTokens: Int?
}

/// JSON event emitted by the CLI in `--json` mode.
public struct CodexJSONEvent: Decodable, Sendable {
  public let type: String
  public let item: CodexJSONEventItem?
  public let error: String?
  public let text: String?
  public let usage: CodexUsage?
  public var rawLine: String?
}

/// Streaming event callback type.
public enum CodexExecEvent: Sendable {
  case stderr(String)
  case stdout(String)
  case jsonEvent(CodexJSONEvent)
}
