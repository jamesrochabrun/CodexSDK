//
//  CodexExecOptions.swift
//  CodexSDK
//
//  Created by James Rochabrun on 11/23/25.
//

import Foundation

public struct CodexExecOptions: Sendable {
  /// Model override (first turn only).
  public var model: String?
  /// Config profile name.
  public var profile: String?
  /// Use OSS provider instead of OpenAI.
  public var useOSSBackend: Bool = false
  /// Approval mode (config override).
  public var approval: CodexApprovalMode?
  /// Sandbox policy (first turn only; resume rejects).
  public var sandbox: CodexSandboxPolicy?
  /// Send `--full-auto` (first turn only; resume rejects).
  public var fullAuto: Bool = false
  /// Send `--dangerously-bypass-approvals-and-sandbox`.
  public var yolo: Bool = false
  /// Working directory override (`--cd`).
  public var changeDirectory: String?
  /// Additional writeable directories (`--add-dir`).
  public var additionalWriteDirectories: [String] = []
  /// Skip git repo check (`--skip-git-repo-check`).
  public var skipGitRepoCheck: Bool = false
  /// Enable web search (`--search`).
  public var enableSearch: Bool = false
  /// Feature toggles (`--enable`).
  public var enableFeatures: [String] = []
  /// Feature disables (`--disable`).
  public var disableFeatures: [String] = []
  /// Config overrides (`-c key=value`).
  public var configOverrides: [String: String] = [:]
  /// Emit JSON events (`--json`, first turn only).
  public var jsonEvents: Bool = false
  /// Structured output schema (`--output-schema`).
  public var outputSchema: String?
  /// Save final message to file (`--output-last-message`).
  public var outputFile: String?
  /// Color mode (`--color`).
  public var colorMode: CodexColorMode?
  /// Attach images (`--image`).
  public var imagePaths: [String] = []
  /// Resume specific session id.
  public var resumeSessionId: String?
  /// Resume last session.
  public var resumeLastSession: Bool = false
  /// Send prompt via stdin (`-`) when true (default).
  public var promptViaStdin: Bool = true
  /// Timeout in seconds (client-side).
  public var timeout: TimeInterval?
  /// Extra raw flags appended verbatim.
  public var extraFlags: [String] = []
  /// MCP config file path (first turn only).
  public var mcpConfigPath: String?
  /// MCP servers (programmatic) to encode as `--mcp-config` (first turn only).
  public var mcpServers: [String: McpServerConfig]?
  
  public init() {}
  
  /// Build the CLI argument list for `codex exec`.
  /// - Throws: `CodexExecError.invalidConfiguration` on MCP encoding/write failures.
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
