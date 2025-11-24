//
//  McpServerConfig.swift
//  CodexSDK
//
//  Created by James Rochabrun on 11/23/25.
//

import Foundation

public struct McpServerConfig: Codable, Sendable {
  public var command: String?
  public var args: [String]?
  public var env: [String: String]?
  public var type: String?
  public var url: String?
  public var headers: [String: String]?
  
  public init(
    command: String? = nil,
    args: [String]? = nil,
    env: [String: String]? = nil,
    type: String? = nil,
    url: String? = nil,
    headers: [String: String]? = nil
  ) {
    self.command = command
    self.args = args
    self.env = env
    self.type = type
    self.url = url
    self.headers = headers
  }
}

public struct McpConfigPayload: Codable {
  let mcpServers: [String: McpServerConfig]
}
