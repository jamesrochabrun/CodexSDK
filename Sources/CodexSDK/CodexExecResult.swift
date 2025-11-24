//
//  CodexExecResult.swift
//  CodexSDK
//
//  Created by James Rochabrun on 11/23/25.
//

import Foundation

public struct CodexExecResult: Sendable {
  public let command: String
  public let stdout: String
  public let stderr: String
  public let exitCode: Int32
  public let events: [CodexJSONEvent]
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
