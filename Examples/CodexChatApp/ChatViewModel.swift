import Foundation
import SwiftUI
import CodexSDK

enum ChatRole {
  case user
  case assistant
}

struct ChatMessage: Identifiable {
  let id = UUID()
  let role: ChatRole
  let text: String
}

@MainActor
final class ChatViewModel: ObservableObject {
  @Published var messages: [ChatMessage] = []
  @Published var isStreaming: Bool = false
  @Published var hasError: Bool = false
  @Published var lastErrorMessage: String?
  @Published var statusText: String = ""
  @Published var useJsonEvents: Bool = false {
    didSet { refreshStatusText() }
  }
  @Published var currentSandbox: CodexSandboxPolicy = .readOnly {
    didSet { refreshStatusText() }
  }
  @Published var currentModel: String = "gpt-5.1-codex-max" {
    didSet { refreshStatusText() }
  }
  @Published var mcpConfigPath: String = ""
  @Published var mcpEnabled: Bool = false
  @Published var useInlineMcp: Bool = false
  @Published var mcpInlineText: String = ChatViewModel.defaultInlineMcpConfig
  
  private let client: CodexExecClient
  private var hasSession = false
  private var codexBinaryVersion: String?
  private var codexBinaryPath: String = "codex"
  
  init() {
    // Use withNvmSupport() for automatic nvm detection (recommended)
    var config = CodexExecConfiguration.withNvmSupport()
    config.enableDebugLogging = false
    config.useLoginShell = true

    // Try to detect codex binary for status display
    if let detected = CodexBinaryDetector.detect() {
      codexBinaryPath = detected.path
      codexBinaryVersion = detected.version
      // If NvmPathDetector didn't find it, use the detected path
      if let nvmPath = NvmPathDetector.detectNvmPath() {
        config.command = "\(nvmPath)/codex"
      } else {
        config.command = detected.path
      }
    } else {
      // Fallback to PATH lookup; status will show warning
      config.command = codexBinaryPath
      codexBinaryVersion = nil
    }

    self.client = CodexExecClient(configuration: config)
    refreshStatusText()
  }
  
  func send(prompt: String) {
    let userMessage = ChatMessage(role: .user, text: prompt)
    messages.append(userMessage)
    lastErrorMessage = nil
    hasError = false
    isStreaming = true
    
    Task {
      var options = CodexExecOptions()
      // Only send --json on the first turn; resume rejects it
      options.jsonEvents = (!hasSession) && useJsonEvents
      options.promptViaStdin = true
      // Avoid sending sandbox on resume; codex exec resume rejects it
      options.sandbox = hasSession ? nil : currentSandbox
      // Avoid --full-auto on resume; resume rejects it
      options.fullAuto = hasSession ? false : true
      options.resumeLastSession = hasSession
      // codex exec resume does not accept --model; only send model on first turn
      options.model = hasSession ? nil : currentModel
      // MCP only on first turn
      if !hasSession && mcpEnabled {
        if useInlineMcp {
          guard let path = writeInlineMcpConfigValidated() else {
            isStreaming = false
            return
          }
          options.mcpConfigPath = path
        } else {
          let trimmed = mcpConfigPath.trimmingCharacters(in: .whitespacesAndNewlines)
          guard !trimmed.isEmpty else {
            let message = "MCP config path is empty."
            lastErrorMessage = message
            hasError = true
            finalizeAssistantMessage(with: "Error: \(message)")
            isStreaming = false
            return
          }
          guard FileManager.default.fileExists(atPath: trimmed) else {
            let message = "MCP config path does not exist."
            lastErrorMessage = message
            hasError = true
            finalizeAssistantMessage(with: "Error: \(message)")
            isStreaming = false
            return
          }
          options.mcpConfigPath = trimmed
        }
      }
      
      var stdoutBuffer = ""
      var stderrBuffer = ""
      
      do {
        let _ = try await client.run(prompt: prompt, options: options) { event in
          switch event {
          case .jsonEvent(let json):
            // Prefer agent_message text if present
            if let text = json.item?.text, json.item?.type == "agent_message" {
              Task { @MainActor in
                stdoutBuffer += text + "\n"
                self.updateAssistantPlaceholder(with: stdoutBuffer)
              }
            }
          case .stdout(let line):
            Task { @MainActor in
              stdoutBuffer += line + "\n"
              self.updateAssistantPlaceholder(with: stdoutBuffer)
            }
          case .stderr(let line):
            Task { @MainActor in
              stderrBuffer += line + "\n"
            }
          }
        }
        
        hasSession = true
        let finalOutput = stdoutBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallbackLogs = stderrBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
        finalizeAssistantMessage(with: finalOutput.isEmpty ? (fallbackLogs.isEmpty ? "(no output)" : fallbackLogs) : finalOutput)
      } catch {
        let message = friendlyMessage(for: error)
        lastErrorMessage = message
        hasError = true
        let details: String
        let outputSoFar = stdoutBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
        let logs = stderrBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
        if !outputSoFar.isEmpty {
          details = "\n\nOutput so far:\n\(outputSoFar)"
        } else if !logs.isEmpty {
          details = "\n\nLogs:\n\(logs)"
        } else {
          details = ""
        }
        finalizeAssistantMessage(with: "Error: \(message)\(details)")
      }
      
      isStreaming = false
    }
  }
  
  private func updateAssistantPlaceholder(with text: String) {
    if let last = messages.last, last.role == .assistant {
      messages.removeLast()
    }
    let placeholder = ChatMessage(role: .assistant, text: text)
    messages.append(placeholder)
  }
  
  private func finalizeAssistantMessage(with text: String) {
    if let last = messages.last, last.role == .assistant {
      messages.removeLast()
    }
    messages.append(ChatMessage(role: .assistant, text: text))
  }
  
  private func friendlyMessage(for error: Error) -> String {
    if let codexError = error as? CodexExecError {
      return codexError.localizedDescription
    }
    return error.localizedDescription
  }
  
  private func refreshStatusText() {
    let versionInfo = codexBinaryVersion.map { " (\($0))" } ?? " (version unknown)"
    statusText = "codex: \(codexBinaryPath)\(versionInfo) • sandbox: \(currentSandbox.rawValue) • json: \(useJsonEvents ? "on" : "off") • model: \(currentModel)"
  }
  
  private func writeInlineMcpConfigValidated() -> String? {
    let trimmed = mcpInlineText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
      let message = "Inline MCP config is empty."
      lastErrorMessage = message
      hasError = true
      finalizeAssistantMessage(with: "Error: \(message)")
      return nil
    }
    
    // Validate JSON
    guard let data = trimmed.data(using: .utf8),
          (try? JSONSerialization.jsonObject(with: data)) != nil else {
      let message = "Inline MCP config is not valid JSON."
      lastErrorMessage = message
      hasError = true
      finalizeAssistantMessage(with: "Error: \(message)")
      return nil
    }
    
    let temp = FileManager.default.temporaryDirectory
      .appendingPathComponent("mcp-inline-\(UUID().uuidString).json")
    do {
      try trimmed.write(to: temp, atomically: true, encoding: .utf8)
      return temp.path
    } catch {
      let message = "Failed to write MCP config: \(error.localizedDescription)"
      lastErrorMessage = message
      hasError = true
      finalizeAssistantMessage(with: "Error: \(message)")
      return nil
    }
  }
  
  private static let defaultInlineMcpConfig = """
{
  "mcpServers": {
    "filesystem": {
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-filesystem", "/tmp"]
    }
  }
}
"""
}
