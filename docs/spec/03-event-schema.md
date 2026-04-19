# Event Schema

Agent runtime events streamed from MASS agent sockets via `EventWatcher`.

## AgentRunEvent

```swift
struct AgentRunEvent: Codable, Sendable {
    let runId: String?
    let sessionId: String?
    let seq: Int                    // monotonic sequence number for dedup
    let time: String?
    let type: String                // EventType constant
    let turnId: String?
    let payload: AgentRunEventPayload?
}
```

## Event Types

```swift
struct EventType {
    static let agentMessage   = "agent_message"
    static let agentThinking  = "agent_thinking"
    static let toolCall       = "tool_call"
    static let toolResult     = "tool_result"
    static let plan           = "plan"
    static let userMessage    = "user_message"
    static let turnStart      = "turn_start"
    static let turnEnd        = "turn_end"
    static let error          = "error"
    static let runtimeUpdate  = "runtime_update"
}
```

### runtime_update

Consolidated status event. Nested fields:

| Field | Content |
|-------|---------|
| `runtimeStatus.status` | "idle", "running", etc. → mapped via `massStateToPhase()` |
| `sessionInfo.title` | Session title → `conversationInfo.summary` |
| `usage.cost.amount` | Cost in dollars → `usage.outputTokens = Int(amount * 100)` |
| `usage.size` | Context size → `usage.inputTokens` |

Also carries `availableCommands`, `currentMode`, `configOptions` (decoded but not yet surfaced in UI).

### agent_message / agent_thinking

Text content with streaming block status.

```swift
struct BlockStatus {
    static let start     = "start"
    static let streaming = "streaming"
    static let end       = "end"
}
```

Payload fields: `content.text`, `status` (BlockStatus).

### tool_call

Payload fields:
- `title`: tool display name
- `id`: tool use ID (used to correlate with tool_result)
- `rawInput`: JSON dictionary of tool parameters

### tool_result

Payload fields:
- `id`: matching tool_call ID
- `status`: "success" or "error"
- `toolContent[].content.text`: result text

### plan

Payload field: `entries: [PlanEntry]`

```swift
struct PlanEntry {
    let content: String
    let status: String      // "completed", "in_progress", or other (pending)
}
```

Rendered as `[x]`, `[>]`, `[ ]` prefixed text. Each plan event replaces the entire plan view (keyed by `"\(id):plan"`).

### user_message

Payload field: `content.text`

Dedup logic: if `sentPrompt` flag is set (local prompt was just sent), the echoed `user_message` is skipped and the flag is cleared.

### turn_start / turn_end

No significant payload. Phase transitions:
- `turn_start` → `session.phase = .processing`
- `turn_end` → flush text buffers → `session.phase = .waitingForInput`

### error

Payload field: `message` — appended as assistant chat item with "Error:" prefix.

## Text Streaming Assembly

Text chunks (`agent_message`, `agent_thinking`) arrive as a stream of `start → streaming* → end` blocks.

### Buffer Management

Keyed by `"\(sessionId):\(role)"` where role is `.assistant` or `.thinking`.

```
start     → create buffer, append new ChatHistoryItem
streaming → append to buffer, update last matching ChatHistoryItem in-place
end       → append to buffer, update item, remove buffer
```

### Late Join Handling

If `streaming` or `end` arrives without a prior `start` (reconnect scenario), the handler auto-creates the buffer and chat item.

### Flush Triggers

Buffers are flushed (finalized) on:
1. `tool_call` event — ends any in-progress assistant message
2. `turn_end` event — flushes both assistant and thinking buffers

### Single-Shot Messages

If `blockStatus` is `nil` (no streaming), the entire text is appended as a new chat item without buffering.

## Event Deduplication

`EventWatcher` tracks `lastSeq: Int`. Events with `seq <= lastSeq` are silently dropped. On reconnect, `watch_event` is called with `fromSeq: lastSeq` to resume from where we left off.

## Payload Structure

`AgentRunEventPayload` is a flat union struct with custom `Codable`. The `"status"` JSON field is overloaded:
- For text blocks: `BlockStatus` string → decoded as `status: String?`
- For runtime updates: nested object → decoded as `runtimeStatus: RuntimeStatus?`

Custom `init(from decoder:)` tries object decode first, falls back to string.
