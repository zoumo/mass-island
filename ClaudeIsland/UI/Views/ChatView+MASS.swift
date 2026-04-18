//
//  ChatView+MASS.swift
//  ClaudeIsland
//
//  MASS send logic for ChatView.
//  Extracted to extension to minimize upstream diff.
//

import Foundation

extension ChatView {
    /// Send a prompt to a MASS agent run
    func sendToMassAgent(_ text: String) async {
        try? await sessionMonitor.sendMassPrompt(sessionId: sessionId, prompt: text)
    }

    /// Cancel current operation on a MASS agent run
    func cancelMassAgent() async {
        try? await sessionMonitor.cancelMassSession(sessionId: sessionId)
    }
}
