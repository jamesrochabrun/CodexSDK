//
//  CodexExecOptions.swift
//  CodexSDK
//
//  Created by James Rochabrun on 11/23/25.
//

import Foundation

public struct CodexExecOptions: Sendable {
  public var model: String?
  public var profile: String?
  public var useOSSBackend: Bool = false
  public var approval: CodexApprovalMode?
  public var sandbox: CodexSandboxPolicy?
  public var fullAuto: Bool = false
  public var yolo: Bool = false
  public var changeDirectory: String?
  public var additionalWriteDirectories: [String] = []
  public var skipGitRepoCheck: Bool = false
  public var enableSearch: Bool = false
  public var enableFeatures: [String] = []
  public var disableFeatures: [String] = []
  public var configOverrides: [String: String] = [:]
  public var jsonEvents: Bool = false
  public var outputSchema: String?
  public var outputFile: String?
  public var colorMode: CodexColorMode?
  public var imagePaths: [String] = []
  public var resumeSessionId: String?
  public var resumeLastSession: Bool = false
  public var promptViaStdin: Bool = true
  public var timeout: TimeInterval?
  public var extraFlags: [String] = []
  public var mcpConfigPath: String?
  public var mcpServers: [String: McpServerConfig]?
  
  public init() {}
  
  func buildArgumentList() throws -> [String] {
    var args: [String] = []
    
    for image in imagePaths {
      args.append("--image")
      args.append(shellEscape(image))
    }
    
    if let model {
      args.append("--model")
      args.append(shellEscape(model))
    }
    
    if let approval {
      // The newer CLI accepts approval as config override; safer than old --ask-for-approval flag
      args.append("-c")
      args.append(shellEscape("approval=\(approval.rawValue)"))
    }
    
    if let profile {
      args.append("--profile")
      args.append(shellEscape(profile))
    }
    
    if useOSSBackend {
      args.append("--oss")
    }
    
    if let sandbox {
      args.append("--sandbox")
      args.append(sandbox.rawValue)
    }
    
    if fullAuto {
      args.append("--full-auto")
    }
    
    if yolo {
      args.append("--dangerously-bypass-approvals-and-sandbox")
    }
    
    if let changeDirectory {
      args.append("--cd")
      args.append(shellEscape(changeDirectory))
    }
    
    for dir in additionalWriteDirectories {
      args.append("--add-dir")
      args.append(shellEscape(dir))
    }
    
    if skipGitRepoCheck {
      args.append("--skip-git-repo-check")
    }
    
    if enableSearch {
      args.append("--search")
    }
    
    for feature in enableFeatures {
      args.append("--enable")
      args.append(shellEscape(feature))
    }
    
    for feature in disableFeatures {
      args.append("--disable")
      args.append(shellEscape(feature))
    }
    
    for (key, value) in configOverrides {
      args.append("-c")
      args.append(shellEscape("\(key)=\(value)"))
    }
    
    if let mcpConfigPath {
      args.append("--mcp-config")
      args.append(shellEscape(mcpConfigPath))
    } else if let mcpServers {
      let payload = McpConfigPayload(mcpServers: mcpServers)
      let jsonData = try JSONEncoder().encode(payload)
      guard let jsonString = String(data: jsonData, encoding: .utf8) else {
        throw CodexExecError.invalidConfiguration("Failed to encode MCP servers.")
      }
      let temp = FileManager.default.temporaryDirectory
        .appendingPathComponent("mcp-\(UUID().uuidString).json")
      do {
        try jsonString.write(to: temp, atomically: true, encoding: .utf8)
      } catch {
        throw CodexExecError.invalidConfiguration("Failed to write MCP config: \(error.localizedDescription)")
      }
      args.append("--mcp-config")
      args.append(shellEscape(temp.path))
    }
    
    if jsonEvents {
      args.append("--json")
    }
    
    if let outputSchema {
      args.append("--output-schema")
      args.append(shellEscape(outputSchema))
    }
    
    if let outputFile {
      args.append("--output-last-message")
      args.append(shellEscape(outputFile))
    }
    
    if let colorMode {
      args.append("--color")
      args.append(colorMode.rawValue)
    }
    
    args.append(contentsOf: extraFlags)
    
    return args
  }
  
  private func shellEscape(_ value: String) -> String {
    let escaped = value.replacingOccurrences(of: "'", with: "'\\''")
    return "'\(escaped)'"
  }
}
