# MASS Backend

MASS backend connects to the MASS daemon via ARI (Agent Runtime Interface) JSON-RPC over Unix domain sockets.

## MassClient

Actor-based ARI wrapper. All RPC calls are JSON-RPC 2.0 over a Unix socket `DataChannel`.

```swift
actor MassClient {
    func connect() async throws           // opens Unix socket, creates JSONRPCSession
    func disconnect() async               // closes session + channel
    func agentRunList(workspace: String? = nil, state: String? = nil) async throws -> [AgentRun]
    func agentRunGet(workspace: String, name: String) async throws -> AgentRun
    func agentRunPrompt(workspace: String, name: String, prompt: String) async throws
    func agentRunCancel(workspace: String, name: String) async throws
}
```

RPC methods:

| Method | Params | Returns |
|--------|--------|---------|
| `agentrun/list` | `ListOptions{workspace?, state?}` | `[AgentRun]` |
| `agentrun/get` | `{workspace, name}` | `AgentRun` |
| `agentrun/prompt` | `AgentRunPromptParams{workspace, name, content}` | void |
| `agentrun/cancel` | `{workspace, name}` | void |

Socket path configured via `AppSettings.massSocketPath`.

## MassPoller

Kubernetes-style list-watch polling loop.

```swift
actor MassPoller {
    let interval: TimeInterval = 3.0        // default poll interval
    let maxConsecutiveErrors = 3            // triggers onConnectionLost
    var knownRuns: [String: AgentRun]       // keyed by "workspace/name"
}
```

### Poll Cycle

1. Call `client.agentRunList()` → get current `[AgentRun]`
2. Build key set: `"(workspace ?? "default")/(name)"` for each run
3. Diff against `knownRuns`:
   - New key → `client.agentRunGet()` for full detail (list omits runtime socket) → `onDiscovered(run)`
   - Missing key → `onRemoved(key)`
   - State changed → `client.agentRunGet()` → `onStateChanged(run)`
4. Update `knownRuns`
5. Reset `consecutiveErrors` on success
6. On error: increment `consecutiveErrors`; if ≥ 3 → `onConnectionLost()`

### Callbacks

```swift
var onDiscovered:     (AgentRun) async -> Void
var onRemoved:        (String)   async -> Void
var onStateChanged:   (AgentRun) async -> Void
var onConnectionLost: ()         async -> Void
```

All wired by `MassSessionStore.start()`.

## EventWatcher

Per-agent event stream subscriber. One watcher per discovered agent run with a runtime socket.

```swift
actor EventWatcher {
    let socketPath: String          // agent runtime socket (not daemon socket)
    let sessionId: String
    var lastSeq: Int = 0            // for deduplication
}
```

### Connection Flow

1. Create `JSONRPCSession` over Unix socket at `socketPath`
2. Call `"runtime/status"` → get initial `RuntimeStatusResult` → `onInitialStatus()`
3. Call `"runtime/watch_event"` with `WatchEventParams(fromSeq: lastSeq)` → subscribe
4. Listen for `"runtime/event_update"` notifications → decode `AgentRunEvent`
5. Dedup: skip events where `event.seq <= lastSeq`
6. Update `lastSeq = event.seq`
7. Call `onEvent(sessionId, event)`

On disconnect: retry after 2s sleep.

## UnixSocketDataChannel

Low-level Unix domain socket transport implementing JSONRPC `DataChannel`.

```swift
class UnixSocketDataChannel: DataChannel {
    // AF_UNIX, SOCK_STREAM
    // SO_NOSIGPIPE to prevent SIGPIPE crashes
    // Non-blocking async reads
}
```

### JSONFramer

Parses raw byte stream into complete JSON objects:

- Tracks brace depth (`{` → +1, `}` → -1)
- Handles string literals (skips braces inside `"..."`)
- Handles escape sequences (`\"`)
- Yields complete JSON object when depth returns to 0

## ARI Types

```swift
struct AgentRun: Codable, Sendable {
    let metadata: ObjectMeta        // name, workspace, labels, annotations
    let spec: AgentSpec             // prompt, model, tools, maxTurns
    let status: AgentRunStatus      // state, run (socketPath, pid), message
}

struct ObjectMeta: Codable, Sendable {
    let name: String
    let workspace: String?
    let labels: [String: String]?
    let annotations: [String: String]?
}

struct AgentRunStatus: Codable, Sendable {
    let state: String               // "creating", "running", "idle", "stopped", "error"
    let run: RunStateInfo?          // socketPath, pid (only when running)
    let message: String?
}
```
