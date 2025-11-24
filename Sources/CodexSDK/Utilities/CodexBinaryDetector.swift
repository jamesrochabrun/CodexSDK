import Foundation

public struct CodexBinaryInfo {
  public let path: String
  public let version: String
}

public enum CodexBinaryDetector {
  /// Try to find the best available `codex` binary by scanning common locations and PATH.
  public static func detect() -> CodexBinaryInfo? {
    var candidates: [String] = []
    
    // From PATH
    if let pathEnv = ProcessInfo.processInfo.environment["PATH"] {
      let paths = pathEnv.split(separator: ":").map(String.init)
      for dir in paths {
        let candidate = dir + "/codex"
        if FileManager.default.isExecutableFile(atPath: candidate) {
          candidates.append(candidate)
        }
      }
    }
    
    // Common nvm location (shallow scan)
    if let nvmDir = ProcessInfo.processInfo.environment["NVM_DIR"] ?? defaultNvmDir() {
      let nodeDir = (nvmDir as NSString).appendingPathComponent("versions/node")
      if let contents = try? FileManager.default.contentsOfDirectory(atPath: nodeDir) {
        for versionDir in contents {
          let candidate = "\(nodeDir)/\(versionDir)/bin/codex"
          if FileManager.default.isExecutableFile(atPath: candidate) {
            candidates.append(candidate)
          }
        }
      }
    }
    
    // Common Homebrew / usr paths
    let commonPaths = [
      "/opt/homebrew/bin/codex",
      "/usr/local/bin/codex"
    ]
    candidates.append(contentsOf: commonPaths.filter { FileManager.default.isExecutableFile(atPath: $0) })
    
    // Deduplicate
    candidates = Array(Set(candidates))
    
    let infos: [CodexBinaryInfo] = candidates.compactMap { path in
      guard let version = versionString(for: path) else { return nil }
      return CodexBinaryInfo(path: path, version: version)
    }
    
    guard !infos.isEmpty else { return nil }
    return infos.max(by: { versionTuple($0.version) < versionTuple($1.version) })
  }
  
  private static func versionString(for path: String) -> String? {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: path)
    process.arguments = ["--version"]
    
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = Pipe()
    
    do {
      try process.run()
      process.waitUntilExit()
    } catch {
      return nil
    }
    
    guard process.terminationStatus == 0 else { return nil }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
  }
  
  private static func versionTuple(_ version: String) -> (Int, Int, Int) {
    // Parse numbers from strings like "codex-cli 0.63.0"
    let components = version
      .split(whereSeparator: { !$0.isNumber && $0 != "." })
      .joined()
      .split(separator: ".")
      .map { Int($0) ?? 0 }
    
    let major = components.count > 0 ? components[0] : 0
    let minor = components.count > 1 ? components[1] : 0
    let patch = components.count > 2 ? components[2] : 0
    return (major, minor, patch)
  }
  
  private static func defaultNvmDir() -> String? {
    let home = NSHomeDirectory()
    let nvm = (home as NSString).appendingPathComponent(".nvm")
    return nvm
  }
}
