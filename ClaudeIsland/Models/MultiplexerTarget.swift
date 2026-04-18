//
//  MultiplexerTarget.swift
//  ClaudeIsland
//
//  Unified multiplexer abstraction for tmux and cmux
//

import Foundation

/// Which terminal multiplexer a session runs in
enum MultiplexerType: Equatable, Sendable {
    case tmux
    case cmux
    case none
}

/// Unified target for any multiplexer
enum MultiplexerTarget: Sendable {
    case tmux(TmuxTarget)
    case cmux(surfaceId: String)
}
