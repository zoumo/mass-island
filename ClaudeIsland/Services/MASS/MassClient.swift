import Foundation
import JSONRPC

// MARK: - MassClient — ARI API wrapper over daemon JSON-RPC socket

actor MassClient {
    private let socketPath: String
    private var session: JSONRPCSession?
    private var connected = false

    init(socketPath: String) {
        self.socketPath = socketPath
    }

    var isConnected: Bool { connected }

    // MARK: - Connection

    func connect() async throws {
        let channel = try makeUnixSocketDataChannel(path: socketPath)
        session = JSONRPCSession(channel: channel)
        connected = true
    }

    func disconnect() {
        session = nil
        connected = false
    }

    // MARK: - ARI Methods

    /// List all agent runs, optionally filtered by workspace/state.
    func agentRunList(workspace: String? = nil, state: String? = nil) async throws -> [AgentRun] {
        var fieldSelector: [String: String] = [:]
        if let ws = workspace { fieldSelector["workspace"] = ws }
        if let st = state { fieldSelector["state"] = st }

        let params = fieldSelector.isEmpty ? ListOptions() : ListOptions(fieldSelector: fieldSelector)
        let result: AgentRunList = try await call(method: "agentrun/list", params: params)
        return result.items
    }

    /// Get a specific agent run.
    func agentRunGet(workspace: String, name: String) async throws -> AgentRun {
        let params = AgentRunGetParams(workspace: workspace, name: name)
        return try await call(method: "agentrun/get", params: params)
    }

    /// Send a prompt to an agent run.
    func agentRunPrompt(workspace: String, name: String, prompt: String) async throws -> Bool {
        let params = AgentRunPromptParams(
            workspace: workspace,
            name: name,
            prompt: [.text(prompt)]
        )
        let result: AgentRunPromptResult = try await call(method: "agentrun/prompt", params: params)
        return result.accepted
    }

    /// Cancel current operation on an agent run.
    func agentRunCancel(workspace: String, name: String) async throws {
        let params = AgentRunCancelParams(workspace: workspace, name: name)
        let _: AgentRunCancelResult = try await call(method: "agentrun/cancel", params: params)
    }

    // MARK: - Private

    private func call<P: Encodable & Sendable, R: Decodable & Sendable>(method: String, params: P) async throws -> R {
        guard let session else {
            throw MassClientError.notConnected
        }
        return try await session.response(to: method, params: params)
    }
}

nonisolated struct AgentRunCancelResult: Decodable, Sendable {}

enum MassClientError: Error, LocalizedError {
    case notConnected
    case rpcError(code: Int, message: String)

    var errorDescription: String? {
        switch self {
        case .notConnected:
            return "Not connected to MASS daemon"
        case .rpcError(let code, let message):
            return "RPC error \(code): \(message)"
        }
    }
}
