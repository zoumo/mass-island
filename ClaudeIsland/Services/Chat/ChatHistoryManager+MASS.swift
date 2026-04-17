//
//  ChatHistoryManager+MASS.swift
//  ClaudeIsland
//
//  MASS backend integration for ChatHistoryManager.
//  Extracted to extension to minimize upstream diff.
//

import Combine
import Foundation

extension ChatHistoryManager {
    /// Combined publisher merging Claude Code and MASS session streams
    static var aggregatedSessionsPublisher: AnyPublisher<[SessionState], Never> {
        SessionStore.shared.sessionsPublisher
            .combineLatest(MassSessionStore.shared.sessionsPublisher)
            .map { $0 + $1 }
            .eraseToAnyPublisher()
    }
}
