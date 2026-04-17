import Foundation

// MARK: - AgentRunEvent (matches runtime/event_update notification params)

nonisolated struct AgentRunEvent: Codable, Sendable {
    let runId: String
    let sessionId: String?
    let seq: Int
    let time: Date
    let type: String         // EventType constants below
    let turnId: String?
    let payload: AgentRunEventPayload?

    enum CodingKeys: String, CodingKey {
        case runId, sessionId, seq, time, type, turnId, payload
    }
}

// MARK: - Event Type Constants (matches runtime event_update AgentRunEvent types)

nonisolated enum EventType {
    static let agentMessage = "agent_message"
    static let agentThinking = "agent_thinking"
    static let toolCall = "tool_call"
    static let toolResult = "tool_result"
    static let plan = "plan"
    static let userMessage = "user_message"
    static let turnStart = "turn_start"
    static let turnEnd = "turn_end"
    static let error = "error"
    static let runtimeUpdate = "runtime_update"
}

// Block streaming status
nonisolated enum BlockStatus {
    static let start = "start"
    static let streaming = "streaming"
    static let end = "end"
}

// MARK: - Event Payload (union type decoded based on AgentRunEvent.type)

/// Payload is decoded dynamically based on the event type.
/// We use a flat struct with optional fields rather than a full discriminated union
/// to simplify JSON decoding — each event type populates its relevant subset.
nonisolated struct AgentRunEventPayload: Codable, Sendable {
    // ContentEvent fields (agent_message, agent_thinking, user_message)
    var status: String?       // BlockStatus: "start" | "streaming" | "end"
    var content: ContentBlock?

    // ToolCallEvent / ToolResultEvent fields
    var id: String?
    var kind: String?
    var title: String?
    // "status" is shared with ContentEvent
    var toolContent: [ToolCallContentWire]?
    var locations: [ToolCallLocationWire]?
    var rawInput: AnyJSONValue?
    var rawOutput: AnyJSONValue?

    // TurnEndEvent
    var stopReason: String?

    // PlanEvent
    var entries: [PlanEntry]?

    // runtime_update nested fields
    var runtimeStatus: RuntimeStatusPayload?
    var sessionInfo: SessionInfoPayload?
    var usage: UsagePayload?
    var availableCommands: AvailableCommandsPayload?
    var currentMode: CurrentModePayload?
    var configOptions: ConfigOptionsPayload?

    // ErrorEvent
    var message: String?

    // Custom decoding to handle the union type
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: FlexibleCodingKeys.self)

        self.id = try container.decodeIfPresent(String.self, forKey: .init("id"))
        self.kind = try container.decodeIfPresent(String.self, forKey: .init("kind"))
        self.title = try container.decodeIfPresent(String.self, forKey: .init("title"))
        self.stopReason = try container.decodeIfPresent(String.self, forKey: .init("stopReason"))
        self.message = try container.decodeIfPresent(String.self, forKey: .init("message"))
        self.rawInput = try container.decodeIfPresent(AnyJSONValue.self, forKey: .init("rawInput"))
        self.rawOutput = try container.decodeIfPresent(AnyJSONValue.self, forKey: .init("rawOutput"))
        self.locations = try container.decodeIfPresent([ToolCallLocationWire].self, forKey: .init("locations"))

        // "status" is overloaded: String for content events, object for runtime_update.
        // Try object first, fallback to string.
        if let rtStatus = try? container.decodeIfPresent(RuntimeStatusPayload.self, forKey: .init("status")) {
            self.runtimeStatus = rtStatus
            self.status = nil
        } else {
            self.runtimeStatus = nil
            self.status = try container.decodeIfPresent(String.self, forKey: .init("status"))
        }
        self.sessionInfo = try container.decodeIfPresent(SessionInfoPayload.self, forKey: .init("sessionInfo"))
        self.usage = try container.decodeIfPresent(UsagePayload.self, forKey: .init("usage"))
        self.availableCommands = try container.decodeIfPresent(AvailableCommandsPayload.self, forKey: .init("availableCommands"))
        self.currentMode = try container.decodeIfPresent(CurrentModePayload.self, forKey: .init("currentMode"))
        self.configOptions = try container.decodeIfPresent(ConfigOptionsPayload.self, forKey: .init("configOptions"))
        self.entries = try container.decodeIfPresent([PlanEntry].self, forKey: .init("entries"))

        // "content" can be either ContentBlock (for content events) or [ToolCallContentWire] (for tool events)
        if let contentBlock = try? container.decodeIfPresent(ContentBlock.self, forKey: .init("content")) {
            self.content = contentBlock
            self.toolContent = nil
        } else if let toolContents = try? container.decodeIfPresent([ToolCallContentWire].self, forKey: .init("content")) {
            self.content = nil
            self.toolContent = toolContents
        } else {
            self.content = nil
            self.toolContent = nil
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: FlexibleCodingKeys.self)
        try container.encodeIfPresent(status, forKey: .init("status"))
        try container.encodeIfPresent(id, forKey: .init("id"))
        try container.encodeIfPresent(kind, forKey: .init("kind"))
        try container.encodeIfPresent(title, forKey: .init("title"))
        try container.encodeIfPresent(stopReason, forKey: .init("stopReason"))
        try container.encodeIfPresent(message, forKey: .init("message"))
        try container.encodeIfPresent(runtimeStatus, forKey: .init("status"))
        try container.encodeIfPresent(sessionInfo, forKey: .init("sessionInfo"))
        try container.encodeIfPresent(usage, forKey: .init("usage"))
        try container.encodeIfPresent(availableCommands, forKey: .init("availableCommands"))
        try container.encodeIfPresent(currentMode, forKey: .init("currentMode"))
        try container.encodeIfPresent(configOptions, forKey: .init("configOptions"))
        try container.encodeIfPresent(entries, forKey: .init("entries"))
    }

    init() {}
}

// MARK: - runtime_update nested payload types

nonisolated struct RuntimeStatusPayload: Codable, Sendable {
    var previousStatus: String?
    var status: String?
    var pid: Int?
    var reason: String?
}

nonisolated struct SessionInfoPayload: Codable, Sendable {
    var title: String?
    var updatedAt: String?
}

nonisolated struct UsagePayload: Codable, Sendable {
    var size: Int?
    var used: Int?
    var cost: CostInfo?
}

// MARK: - Plan entry

nonisolated struct PlanEntry: Codable, Sendable {
    var content: String
    var status: String    // "pending" | "in_progress" | "completed"
}

// MARK: - runtime_update additional payload types

nonisolated struct AvailableCommand: Codable, Sendable {
    var name: String
    var description: String?
}

nonisolated struct AvailableCommandsPayload: Codable, Sendable {
    var commands: [AvailableCommand]
}

nonisolated struct CurrentModePayload: Codable, Sendable {
    var modeId: String
}

nonisolated struct ConfigOption: Codable, Sendable {
    var type: String
    var id: String
    var name: String
    var currentValue: String?
}

nonisolated struct ConfigOptionsPayload: Codable, Sendable {
    var options: [ConfigOption]
}

// MARK: - ContentBlock (matches Go ACP ContentBlock — simplified text-only for now)

nonisolated struct ContentBlock: Codable, Sendable {
    var type: String     // "text"
    var text: String?

    enum CodingKeys: String, CodingKey {
        case type, text
    }
}

// MARK: - Tool content wire types

nonisolated struct ToolCallContentWire: Codable, Sendable {
    var type: String     // "content" | "diff" | "terminal"
    // content variant
    var content: ContentBlock?
    // diff variant
    var path: String?
    var oldText: String?
    var newText: String?
    // terminal variant
    var terminalId: String?
}

nonisolated struct ToolCallLocationWire: Codable, Sendable {
    var path: String
    var line: Int?
}

// MARK: - Flexible coding key for union decoding

nonisolated struct FlexibleCodingKeys: CodingKey {
    var stringValue: String
    var intValue: Int?

    init(_ string: String) {
        self.stringValue = string
        self.intValue = nil
    }

    init?(stringValue: String) {
        self.stringValue = stringValue
        self.intValue = nil
    }

    init?(intValue: Int) {
        self.stringValue = String(intValue)
        self.intValue = intValue
    }
}

// MARK: - AnyJSONValue (for rawInput/rawOutput)

nonisolated struct AnyJSONValue: Codable, Equatable, @unchecked Sendable {
    let value: Any

    init(_ value: Any) {
        self.value = value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let string = try? container.decode(String.self) {
            value = string
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if let dict = try? container.decode([String: AnyJSONValue].self) {
            value = dict.mapValues { $0.value }
        } else if let array = try? container.decode([AnyJSONValue].self) {
            value = array.map { $0.value }
        } else {
            value = NSNull()
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch value {
        case let s as String: try container.encode(s)
        case let i as Int: try container.encode(i)
        case let d as Double: try container.encode(d)
        case let b as Bool: try container.encode(b)
        default: try container.encodeNil()
        }
    }

    static func == (lhs: AnyJSONValue, rhs: AnyJSONValue) -> Bool {
        String(describing: lhs.value) == String(describing: rhs.value)
    }
}

// MARK: - CostInfo (from MASS session model)

nonisolated struct CostInfo: Codable, Equatable, Sendable {
    var amount: Double
    var currency: String
}

// MARK: - Watch event params/result

nonisolated struct WatchEventParams: Codable, Sendable {
    var fromSeq: Int
}

nonisolated struct WatchEventResult: Codable, Sendable {
    var watchId: String?
    var nextSeq: Int?
}

// MARK: - runtime/status types

nonisolated struct RuntimeStatusResult: Codable, Sendable {
    var state: RuntimeState
    var recovery: RuntimeRecoveryInfo
}

/// Mirrors Go apiruntime.State — full runtime state written to state.json.
nonisolated struct RuntimeState: Codable, Sendable {
    var massVersion: String?
    var id: String?
    var status: String?
    var pid: Int?
    var bundle: String?
    var exitCode: Int?
    var updatedAt: String?
}

nonisolated struct RuntimeRecoveryInfo: Codable, Sendable {
    var lastSeq: Int?
}
