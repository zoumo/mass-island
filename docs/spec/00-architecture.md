# Architecture Overview

Mass Island is a macOS notch overlay that monitors agent sessions from two backends: Claude Code (CC) and MASS daemon.

## Dual Backend Design

```
┌─────────────────────────────────────────────────────────┐
│                      Mass Island                         │
│                                                          │
│  ┌──────────────────┐    ┌───────────────────────────┐  │
│  │   SessionStore    │    │    MassSessionStore       │  │
│  │  (CC hook-based)  │    │  (ARI over Unix socket)   │  │
│  └────────┬─────────┘    └──────────┬────────────────┘  │
│           │                         │                    │
│           │  Combine publishers     │                    │
│           └──────────┬──────────────┘                    │
│                      ▼                                   │
│           ┌─────────────────────┐                        │
│           │ ClaudeSessionMonitor │                        │
│           │  (aggregated merge)  │                        │
│           └──────────┬──────────┘                        │
│                      ▼                                   │
│           ┌──────────────────┐                           │
│           │    NotchView UI   │                           │
│           └──────────────────┘                           │
└─────────────────────────────────────────────────────────┘
```

### CC Backend (SessionStore)

- Reads `.jsonl` session files from `~/.claude/projects/`
- Parses hook events (tool calls, permissions, messages)
- File-based: polls for file changes, parses incrementally
- Uses `SessionPhase.canTransition()` to guard state changes

### MASS Backend (MassSessionStore)

- Connects to MASS daemon via ARI JSON-RPC over Unix domain socket
- `MassPoller`: list-watch pattern, 3s poll interval, diff detection
- `EventWatcher`: per-agent event subscription via `runtime/watch_event`
- Daemon state is authoritative — bypasses `canTransition()` entirely
- See [01-mass-backend.md](01-mass-backend.md) for details

## Data Flow

```
Discovery:
  MassPoller.poll() → agentRunList → diff with knownRuns
    → onDiscovered(run) → MassSessionStore creates SessionState
    → startWatcher(socketPath) if runtime socket available

State Sync:
  MassPoller.poll() → state change detected
    → onStateChanged(run) → massStateToPhase() → update session.phase

Event Stream:
  EventWatcher → runtime/watch_event subscription
    → onEvent(id, AgentRunEvent) → handleRunEvent()
    → updates chatItems, conversationInfo, phase

UI Rendering:
  MassSessionStore.sessionsPublisher
    + SessionStore.sessionsPublisher
    → ClaudeSessionMonitor.aggregatedSessionsPublisher (combineLatest)
    → NotchView / ClaudeInstancesView observe via @ObservedObject
```

## Combine Merge Strategy

`ClaudeSessionMonitor+MASS.swift` defines:

```swift
static var aggregatedSessionsPublisher: AnyPublisher<[SessionState], Never>
```

This merges both publishers via `combineLatest`, concatenating MASS sessions after CC sessions. The unified `[SessionState]` array feeds all UI components. Each `SessionState` carries a `.source` field (`.claudeCode` or `.mass`) for conditional rendering.

## Key Shared Types

| Type | Role |
|------|------|
| `SessionState` | Universal session value type |
| `SessionPhase` | State machine (idle → processing → waitingForInput → ended) |
| `ChatHistoryItem` | Conversation items (user, assistant, thinking, toolCall) |
| `ConversationInfo` | Summary, last message, usage stats |
| `MultiplexerType` | Terminal mux detection (.tmux, .cmux, .none) |

## Component Ownership

```
ClaudeSessionMonitor
├── SessionStore (CC)
│   └── per-session file watchers
├── MassSessionStore (MASS)
│   ├── MassClient (ARI JSON-RPC)
│   ├── MassPoller (list-watch)
│   └── EventWatcher[] (per-agent event streams)
└── UI
    ├── NotchView (pill overlay)
    └── ClaudeInstancesView (session list)
```
