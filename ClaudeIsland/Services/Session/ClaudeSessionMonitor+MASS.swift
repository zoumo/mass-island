//
//  ClaudeSessionMonitor+MASS.swift
//  ClaudeIsland
//
//  MASS backend methods for ClaudeSessionMonitor.
//  Extracted to extension to minimize upstream diff.
//

import Combine
import Foundation

extension ClaudeSessionMonitor {
    /// Combined publisher merging Claude Code and MASS session streams
    static var aggregatedSessionsPublisher: AnyPublisher<[SessionState], Never> {
        SessionStore.shared.sessionsPublisher
            .combineLatest(MassSessionStore.shared.sessionsPublisher)
            .map { $0 + $1 }
            .eraseToAnyPublisher()
    }

    // MARK: - MASS Monitoring Lifecycle

    func startMassMonitoring() {
        let socketPath = AppSettings.massSocketPath
        NSLog("[MassMonitor] Starting with socket: %@", socketPath)
        Task {
            await MassSessionStore.shared.start(socketPath: socketPath)
        }
    }

    func stopMassMonitoring() {
        Task {
            await MassSessionStore.shared.stop()
        }
    }

    // MARK: - MASS Actions

    /// Send a prompt to a MASS agent run
    func sendMassPrompt(sessionId: String, prompt: String) async throws {
        guard let client = await MassSessionStore.shared.client() else { return }
        // sessionId format: "workspace/name"
        let parts = sessionId.split(separator: "/", maxSplits: 1)
        guard parts.count == 2 else { return }
        let workspace = String(parts[0])
        let name = String(parts[1])
        _ = try await client.agentRunPrompt(workspace: workspace, name: name, prompt: prompt)
    }

    /// Cancel current operation on a MASS agent run
    func cancelMassSession(sessionId: String) async throws {
        guard let client = await MassSessionStore.shared.client() else { return }
        let parts = sessionId.split(separator: "/", maxSplits: 1)
        let workspace = String(parts[0])
        let name = String(parts[1])
        try await client.agentRunCancel(workspace: workspace, name: name)
    }
}
