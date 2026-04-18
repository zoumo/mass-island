//
//  CmuxPathFinder.swift
//  ClaudeIsland
//
//  Finds cmux executable path
//

import Foundation

/// Finds and caches the cmux executable path
actor CmuxPathFinder {
    static let shared = CmuxPathFinder()

    private var cachedPath: String?

    private init() {}

    /// Get the path to cmux executable
    func getCmuxPath() -> String? {
        if let cached = cachedPath {
            return cached
        }

        let possiblePaths = [
            "/opt/homebrew/bin/cmux",   // Apple Silicon Homebrew
            "/usr/local/bin/cmux",      // Intel Homebrew
            "\(NSHomeDirectory())/.cargo/bin/cmux",  // Cargo install
            "/usr/bin/cmux",
            "/bin/cmux"
        ]

        for path in possiblePaths {
            if FileManager.default.isExecutableFile(atPath: path) {
                cachedPath = path
                return path
            }
        }

        return nil
    }

    /// Check if cmux is available
    func isCmuxAvailable() -> Bool {
        getCmuxPath() != nil
    }
}
