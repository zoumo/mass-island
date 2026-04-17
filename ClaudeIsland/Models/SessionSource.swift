//
//  SessionSource.swift
//  ClaudeIsland
//
//  Identifies where a session originates from.
//  Extracted to standalone file to minimize upstream diff on SessionState.swift.
//

import Foundation

/// Identifies where a session originates from
enum SessionSource: String, Codable, Sendable, Equatable {
    case claudeCode
    case mass
}
