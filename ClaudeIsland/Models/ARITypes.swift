import Foundation

// MARK: - ARI Domain Types (matches Go pkg/ari/api/domain.go)

nonisolated struct ObjectMeta: Codable, Sendable {
    var name: String
    var workspace: String?
    var labels: [String: String]?
    var createdAt: String?
    var updatedAt: String?
}

nonisolated struct AgentSpec: Codable, Sendable {
    var command: String
    var args: [String]?
    var startupTimeoutSeconds: Int?
}

nonisolated struct Agent: Codable, Sendable {
    var metadata: ObjectMeta
    var spec: AgentSpec
}

nonisolated struct AgentList: Codable, Sendable {
    var items: [Agent]
}

nonisolated struct AgentRunSpec: Codable, Sendable {
    var agent: String
    var restartPolicy: String?
    var description: String?
    var systemPrompt: String?
}

/// Runtime process info for a running agent-run.
nonisolated struct RunStateInfo: Codable, Sendable {
    var status: String
    var pid: Int?
    var bundle: String
    var socketPath: String?
    var exitCode: Int?
}

nonisolated struct AgentRunStatus: Codable, Sendable {
    var state: String
    var errorMessage: String?
    var run: RunStateInfo?
}

nonisolated struct AgentRun: Codable, Sendable {
    var metadata: ObjectMeta
    var spec: AgentRunSpec
    var status: AgentRunStatus
}

nonisolated struct AgentRunList: Codable, Sendable {
    var items: [AgentRun]
}

// MARK: - ARI Operation Params/Results (matches Go pkg/ari/api/types.go)

nonisolated struct ListOptions: Codable, Sendable {
    var fieldSelector: [String: String]?
    var labels: [String: String]?
}

nonisolated struct AgentRunPromptParams: Codable, Sendable {
    var workspace: String
    var name: String
    var prompt: [ACPContentBlock]
}

/// ACP content block for prompt payloads (text, image, audio, etc.)
nonisolated struct ACPContentBlock: Codable, Sendable {
    var type: String   // "text", "image", "audio", etc.
    var text: String?

    /// Convenience factory for a text content block.
    static func text(_ value: String) -> ACPContentBlock {
        ACPContentBlock(type: "text", text: value)
    }
}

nonisolated struct AgentRunPromptResult: Codable, Sendable {
    var accepted: Bool
}

nonisolated struct AgentRunCancelParams: Codable, Sendable {
    var workspace: String
    var name: String
}

nonisolated struct AgentRunGetParams: Codable, Sendable {
    var workspace: String
    var name: String
}
