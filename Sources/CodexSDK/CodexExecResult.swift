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

// MARK: - Supporting Types for Item Events

/// Web search result from `web_search` item type.
public struct CodexWebSearchResult: Decodable, Sendable {
  public let title: String?
  public let url: String?
  public let snippet: String?
}

/// Todo item from `todo_list` item type.
public struct CodexTodoItem: Decodable, Sendable {
  public let id: String?
  public let content: String?
  public let status: String?
}

/// Type-erased JSON value for flexible decoding (e.g., MCP tool arguments).
/// Uses `@unchecked Sendable` since JSON values (strings, numbers, bools, arrays, dicts) are inherently safe.
public struct AnyCodable: Decodable, @unchecked Sendable, CustomStringConvertible {
  public let value: Any

  public init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()

    if container.decodeNil() {
      value = NSNull()
    } else if let bool = try? container.decode(Bool.self) {
      value = bool
    } else if let int = try? container.decode(Int.self) {
      value = int
    } else if let double = try? container.decode(Double.self) {
      value = double
    } else if let string = try? container.decode(String.self) {
      value = string
    } else if let array = try? container.decode([AnyCodable].self) {
      value = array.map(\.value)
    } else if let dict = try? container.decode([String: AnyCodable].self) {
      value = dict.mapValues(\.value)
    } else {
      throw DecodingError.dataCorruptedError(
        in: container,
        debugDescription: "Unable to decode AnyCodable value"
      )
    }
  }

  public var description: String {
    String(describing: value)
  }
}

/// Item in a JSON event (e.g., agent_message, command_execution, file_change, etc.).
public struct CodexJSONEventItem: Decodable, Sendable {
  // MARK: - Common fields
  public let id: String?
  public let type: String?
  public let status: String?
  public let text: String?

  // MARK: - command_execution fields
  public let command: String?
  /// Output from command_execution events.
  public let aggregatedOutput: String?
  /// Exit code from command_execution events.
  public let exitCode: Int?

  // MARK: - file_change fields
  /// File path for file_change events.
  public let filePath: String?
  /// Diff content for file_change events.
  public let diff: String?

  // MARK: - mcp_tool_call fields
  /// Tool name for mcp_tool_call events.
  public let toolName: String?
  /// Tool arguments for mcp_tool_call events.
  public let toolArguments: [String: AnyCodable]?
  /// Tool result for mcp_tool_call events.
  public let toolResult: String?

  // MARK: - web_search fields
  /// Search query for web_search events.
  public let query: String?
  /// Search results for web_search events.
  public let results: [CodexWebSearchResult]?

  // MARK: - todo_list fields
  /// Todo items for todo_list events.
  public let items: [CodexTodoItem]?
}

/// Usage info from JSON events.
public struct CodexUsage: Decodable, Sendable {
  public let inputTokens: Int?
  public let outputTokens: Int?
  /// Cached input tokens (for prompt caching).
  public let cachedInputTokens: Int?
}

/// JSON event emitted by the CLI in `--json` mode.
public struct CodexJSONEvent: Decodable, Sendable {
  public let type: String
  public let item: CodexJSONEventItem?
  public let error: String?
  public let text: String?
  public let usage: CodexUsage?
  public var rawLine: String?
  /// Thread ID for `thread.started` events.
  public let threadId: String?
}

/// Streaming event callback type.
public enum CodexExecEvent: Sendable {
  case stderr(String)
  case stdout(String)
  case jsonEvent(CodexJSONEvent)
}
