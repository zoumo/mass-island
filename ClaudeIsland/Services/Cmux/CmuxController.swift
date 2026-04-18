//
//  CmuxController.swift
//  ClaudeIsland
//
//  High-level cmux operations controller
//

import Foundation
import os.log

/// Controller for cmux terminal multiplexer operations
actor CmuxController {
    static let shared = CmuxController()

    private static let logger = Logger(subsystem: "com.claudeisland", category: "Cmux")

    private init() {}

    // MARK: - Messaging

    /// Send a text message followed by Enter
    func sendMessage(_ message: String, surfaceId: String) async -> Bool {
        guard let cmuxPath = await CmuxPathFinder.shared.getCmuxPath() else {
            Self.logger.error("cmux not found")
            return false
        }

        do {
            // cmux interprets \n as Enter key
            let textWithEnter = message + "\\n"
            Self.logger.info("Sending message to surface \(surfaceId.prefix(8), privacy: .public)")
            _ = try await ProcessExecutor.shared.run(cmuxPath, arguments: [
                "send", "--surface", surfaceId, textWithEnter
            ])
            return true
        } catch {
            Self.logger.error("Send failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    /// Send a key to a surface (for tool approval interactions)
    func sendKey(_ key: String, surfaceId: String) async -> Bool {
        guard let cmuxPath = await CmuxPathFinder.shared.getCmuxPath() else {
            return false
        }

        do {
            Self.logger.info("Sending key '\(key, privacy: .public)' to surface \(surfaceId.prefix(8), privacy: .public)")
            _ = try await ProcessExecutor.shared.run(cmuxPath, arguments: [
                "send-key", "--surface", surfaceId, key
            ])
            return true
        } catch {
            Self.logger.error("Send-key failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    // MARK: - Focus

    /// Focus a cmux surface via RPC
    func focusSurface(_ surfaceId: String) async -> Bool {
        guard let cmuxPath = await CmuxPathFinder.shared.getCmuxPath() else {
            return false
        }

        do {
            let params = "{\"surface_id\":\"\(surfaceId)\"}"
            _ = try await ProcessExecutor.shared.run(cmuxPath, arguments: [
                "rpc", "surface.focus", params
            ])
            Self.logger.info("Focused surface \(surfaceId.prefix(8), privacy: .public)")
            return true
        } catch {
            Self.logger.error("Focus failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    // MARK: - Approval

    /// Approve a tool once (sends '1' + Enter)
    func approveOnce(surfaceId: String) async -> Bool {
        await sendMessage("1", surfaceId: surfaceId)
    }

    /// Approve a tool always (sends '2' + Enter)
    func approveAlways(surfaceId: String) async -> Bool {
        await sendMessage("2", surfaceId: surfaceId)
    }

    /// Reject a tool with optional message
    func reject(surfaceId: String, message: String? = nil) async -> Bool {
        guard await sendMessage("n", surfaceId: surfaceId) else {
            return false
        }

        if let message = message, !message.isEmpty {
            try? await Task.sleep(for: .milliseconds(100))
            return await sendMessage(message, surfaceId: surfaceId)
        }

        return true
    }
}
