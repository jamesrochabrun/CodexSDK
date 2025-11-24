//
//  NvmPathDetector.swift
//  CodexSDK
//

import Foundation

/// Utility to detect nvm (Node Version Manager) installation paths
/// This is an optional helper - the SDK works perfectly fine without nvm.
/// If nvm is not installed, all methods safely return nil or empty results.
public struct NvmPathDetector {

  /// Detects the nvm node binary path for the current default version
  /// - Returns: The path to the node binary directory if found, nil otherwise
  /// - Note: Returns nil if nvm is not installed - this is safe and expected
  public static func detectNvmPath() -> String? {
    let homeDir = NSHomeDirectory()
    let nvmDefaultPath = "\(homeDir)/.nvm/alias/default"

    // Try to read the default version
    // If the file doesn't exist (no nvm), this safely returns nil
    if let version = try? String(contentsOfFile: nvmDefaultPath).trimmingCharacters(in: .whitespacesAndNewlines) {
      let nodePath = "\(homeDir)/.nvm/versions/node/\(version)/bin"
      // Verify the path exists before returning it
      if FileManager.default.fileExists(atPath: nodePath) {
        return nodePath
      }
    }

    // Fallback: check for any installed version
    // If nvm directory doesn't exist, this returns nil
    let nvmVersionsPath = "\(homeDir)/.nvm/versions/node"
    if let versions = try? FileManager.default.contentsOfDirectory(atPath: nvmVersionsPath),
       let latestVersion = versions.sorted().last {
      let nodePath = "\(nvmVersionsPath)/\(latestVersion)/bin"
      if FileManager.default.fileExists(atPath: nodePath) {
        return nodePath
      }
    }

    // No nvm installation found - this is perfectly fine
    return nil
  }

  /// Detects all available nvm node binary paths
  /// - Returns: An array of paths to node binary directories, empty if nvm not installed
  /// - Note: Returns empty array if nvm is not installed - this is safe and expected
  public static func detectAllNvmPaths() -> [String] {
    let homeDir = NSHomeDirectory()
    let nvmVersionsPath = "\(homeDir)/.nvm/versions/node"

    // If nvm isn't installed, this returns empty array
    guard let versions = try? FileManager.default.contentsOfDirectory(atPath: nvmVersionsPath) else {
      return []
    }

    return versions.compactMap { version in
      let nodePath = "\(nvmVersionsPath)/\(version)/bin"
      return FileManager.default.fileExists(atPath: nodePath) ? nodePath : nil
    }
  }

  /// Checks if nvm is installed
  /// - Returns: true if nvm directory exists, false otherwise
  /// - Note: Used to provide helpful debugging information
  public static func isNvmInstalled() -> Bool {
    let nvmDir = "\(NSHomeDirectory())/.nvm"
    return FileManager.default.fileExists(atPath: nvmDir)
  }
}

// MARK: - CodexExecConfiguration Extension

public extension CodexExecConfiguration {

  /// Creates a configuration with automatic nvm support
  /// - Returns: A configuration with nvm paths automatically detected and added
  /// - Note: If nvm is not installed, returns a standard configuration without modification
  ///
  /// Example:
  /// ```swift
  /// // This works whether or not nvm is installed
  /// let config = CodexExecConfiguration.withNvmSupport()
  /// ```
  static func withNvmSupport() -> CodexExecConfiguration {
    var config = CodexExecConfiguration.default

    // Add nvm path if detected, otherwise config remains unchanged
    if let nvmPath = NvmPathDetector.detectNvmPath() {
      // Insert at beginning for highest priority
      config.additionalPaths.insert(nvmPath, at: 0)
    }

    return config
  }

  /// Adds nvm support to the current configuration
  /// - Returns: Self for chaining
  /// - Note: Safe to call even if nvm is not installed - will simply not modify paths
  ///
  /// Example:
  /// ```swift
  /// var config = CodexExecConfiguration.default
  /// config.addNvmSupport() // Safe to call - no-op if nvm not found
  /// ```
  mutating func addNvmSupport() {
    if let nvmPath = NvmPathDetector.detectNvmPath() {
      // Avoid duplicates and insert at beginning for priority
      if !additionalPaths.contains(nvmPath) {
        additionalPaths.insert(nvmPath, at: 0)
      }
    }
    // If nvm not found, configuration remains unchanged
  }
}
