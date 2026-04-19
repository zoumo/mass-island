# Session State Model

Unified session representation shared across both backends and all UI components.

## SessionState

```swift
struct SessionState: Equatable, Identifiable, Sendable {
    let sessionId: String           // CC: UUID from .jsonl filename; MASS: "workspace/name"
    let source: SessionSource       // .claudeCode | .mass
    let cwd: String                 // working directory or workspace name
    let projectName: String         // display name

    var pid: Int?                   // process ID (CC only)
    var multiplexer: MultiplexerType // .tmux | .cmux | .none
    var cmuxSurfaceId: String?      // cmux surface ref (cmux only)

    var phase: SessionPhase         // current state machine phase
    var chatItems: [ChatHistoryItem]
    var toolTracker: ToolTracker
    var subagentState: SubagentState
    var conversationInfo: ConversationInfo
    var lastActivity: Date
}
```

### Display Properties

- `displayTitle`: priority `summary > firstUserMessage > projectName`
- `stableId`: combines PID + sessionId for SwiftUI animation stability
- `needsAttention`: delegates to `phase.needsAttention`
- `isInMultiplexer`: `multiplexer != .none`

## SessionPhase State Machine

```
                    ┌──────────┐
          ┌────────►│  idle    │◄────────┐
          │         └────┬─────┘         │
          │              │               │
          │              ▼               │
          │    ┌──────────────────┐      │
          │    │   processing     │──────┤
          │    └───────┬──┬──────┘      │
          │            │  │              │
          │            ▼  │              │
          │  ┌────────────┴───────┐     │
          │  │ waitingForApproval  │─────┤
          │  └────────────────────┘     │
          │            │                 │
          │            ▼                 │
          │  ┌──────────────────┐       │
          ├──│ waitingForInput   │───────┤
          │  └──────────────────┘       │
          │                              │
          │  ┌──────────────────┐       │
          └──│   compacting      │───────┘
             └──────────────────┘
                      │
                      ▼ (any state)
             ┌──────────────────┐
             │     ended         │  ← terminal
             └──────────────────┘
```

### Transition Rules

```swift
func canTransition(to next: SessionPhase) -> Bool
```

- `.ended` is terminal — no transitions out (returns `false` for all)
- Any state → `.ended` is allowed
- Self-transitions are always allowed
- `.idle` → `.processing`, `.waitingForApproval`, `.compacting`
- `.processing` → `.waitingForInput`, `.waitingForApproval`, `.compacting`, `.idle`
- `.waitingForApproval` → `.processing`, `.idle`, `.waitingForInput`, another `.waitingForApproval`
- `.compacting` → `.processing`, `.idle`, `.waitingForInput`

### MASS vs CC Phase Handling

**CC sessions** use `canTransition()` as a guard — state comes from file parsing which can be noisy.

**MASS sessions** bypass `canTransition()` entirely. Daemon state is authoritative and directly overwrites `session.phase`. This is critical because:

- `.ended` is terminal in `canTransition` (returns `false` for all outgoing transitions)
- MASS daemon can restart agents, making `ended → idle` a valid transition
- Using `canTransition` caused MASS agents to get stuck showing "ended" when daemon reported them as "idle"

### MASS State Mapping

```swift
func massStateToPhase(_ state: String) -> SessionPhase {
    switch state {
    case "creating", "running": return .processing
    case "idle":                return .waitingForInput
    case "stopped", "error":    return .ended
    default:                    return .idle
    }
}
```

## PermissionContext

```swift
struct PermissionContext: Sendable, Equatable {
    let toolUseId: String
    let toolName: String
    let toolInput: [String: AnyCodable]?
    let receivedAt: Date
}
```

Carried by `.waitingForApproval(PermissionContext)`. Used by UI to show tool name and formatted input in the approval row.

## SubagentState

Tracks CC subagent task hierarchy (not used by MASS — each MASS agent is its own session).

```swift
struct SubagentState: Equatable, Sendable {
    var activeTasks: [String: TaskContext]
    var taskStack: [String]
    var totalTaskCount: Int
    var activeTaskCount: Int { activeTasks.count }
}
```

## ToolTracker

Deduplication and in-progress tracking for tool calls.

```swift
struct ToolTracker: Equatable, Sendable {
    var inProgress: [String: ToolInProgress]
    var seenIds: Set<String>
    var lastSyncOffset: UInt64
}
```

## ConversationInfo

Summary and usage data for display.

```swift
struct ConversationInfo {
    var summary: String?
    var lastMessage: String?
    var lastMessageRole: String?
    var lastToolName: String?
    var firstUserMessage: String?
    var lastUserMessageDate: Date?
    var usage: UsageInfo
}
```
