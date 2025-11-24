//
//  CodexExecConfiguration.swift
//  CodexSDK
//
//  Created by James Rochabrun on 11/23/25.
//

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
