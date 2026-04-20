//
//  Settings+MASS.swift
//  ClaudeIsland
//
//  MASS backend settings — extracted to extension to minimize upstream diff.
//

import Foundation

extension AppSettings {
    // MARK: - Keys (MASS)

    private enum MASSKeys {
        static let massSocketPath = "massSocketPath"
        static let claudeCodeEnabled = "claudeCodeEnabled"
        static let massEnabled = "massEnabled"
    }

    // MARK: - MASS Backend

    /// Unix socket path for MASS daemon.
    /// Can be overridden by MASS_SOCKET_PATH env var.
    static var massSocketPath: String {
        get {
            if let envPath = Foundation.ProcessInfo.processInfo.environment["MASS_SOCKET_PATH"], !envPath.isEmpty {
                return envPath
            }
            let stored = defaults.string(forKey: MASSKeys.massSocketPath) ?? ""
            if !stored.isEmpty { return stored }
            return NSHomeDirectory() + "/.mass/socket"
        }
        set {
            defaults.set(newValue.trimmingCharacters(in: .whitespaces), forKey: MASSKeys.massSocketPath)
        }
    }

    // MARK: - Backend Toggles

    /// Whether the Claude Code (hook-based) backend is enabled
    static var claudeCodeEnabled: Bool {
        get { defaults.object(forKey: MASSKeys.claudeCodeEnabled) as? Bool ?? true }
        set { defaults.set(newValue, forKey: MASSKeys.claudeCodeEnabled) }
    }

    /// Whether the MASS daemon backend is enabled
    static var massEnabled: Bool {
        get { defaults.object(forKey: MASSKeys.massEnabled) as? Bool ?? true }
        set { defaults.set(newValue, forKey: MASSKeys.massEnabled) }
    }
}
