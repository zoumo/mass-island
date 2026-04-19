# Multiplexer Support

Mass Island interacts with terminal sessions running in tmux or cmux to focus windows and send approval keystrokes.

## MultiplexerType

```swift
enum MultiplexerType: Equatable, Sendable {
    case tmux
    case cmux
    case none
}
```

Stored on `SessionState.multiplexer`. Detected during session discovery. Determines which controller handles focus and approval.

## Architecture

```
SessionState.multiplexer + .cmuxSurfaceId
        │
        ▼
MultiplexerTarget.tmux(TmuxTarget)  or  MultiplexerTarget.cmux(surfaceId:)
        │                                          │
        ▼                                          ▼
ToolApprovalHandler (central dispatch)
        │                                          │
        ├── tmux branch                            ├── cmux branch
        ▼                                          ▼
TmuxController                              CmuxController
  └── ProcessExecutor("tmux", ...)            └── ProcessExecutor("cmux", ...)
```

`ToolApprovalHandler` is the single dispatch point for all approval interactions.

## tmux

### TmuxTarget

```swift
struct TmuxTarget: Sendable {
    let session: String
    let window: String
    let pane: String

    var targetString: String { "\(session):\(window).\(pane)" }
}
```

### TmuxTargetFinder

Locates which tmux pane runs a given Claude session:

1. **By PID**: runs `tmux list-panes -a -F "#{session_name}:#{window_index}.#{pane_index} #{pane_pid}"`, then walks process tree via `ProcessTreeBuilder` to find pane that is ancestor of Claude PID
2. **By working directory**: matches `#{pane_current_path}` against session cwd

### TmuxSessionMatcher

Maps tmux pane → Claude session ID:

1. Captures 500 lines of scrollback via `tmux capture-pane -t <target> -p -S -500`
2. Extracts up to 5 representative text snippets (≥25 chars, >1/3 letters, not UI decorators)
3. Scans last 100KB of `.jsonl` session files for matching snippets
4. Returns session ID with ≥2 matched snippets

### Approval Keystrokes (tmux)

```swift
func approveOnce(target:)   // sends "1" + Enter
func approveAlways(target:) // sends "2" + Enter
func reject(target:)        // sends "n" + Enter, then optional message
```

Uses `tmux send-keys -t <target> -l <text>` (literal flag prevents special-char interpretation), then separate `send-keys -t <target> Enter`.

### Focus

```swift
func switchToPane(target:)  // tmux select-window + tmux select-pane
```

## cmux

### CmuxController

```swift
actor CmuxController {
    func sendMessage(_ message: String, surfaceId: String) async -> Bool
    func sendKey(_ key: String, surfaceId: String) async -> Bool
    func focusSurface(_ surfaceId: String) async -> Bool
    func approveOnce(surfaceId:) async -> Bool     // sendMessage("1")
    func approveAlways(surfaceId:) async -> Bool   // sendMessage("2")
    func reject(surfaceId:) async -> Bool          // sendMessage("n")
}
```

- `surfaceId` corresponds to `SessionState.cmuxSurfaceId`
- `cmux send --surface <id> <text>` for message input
- `cmux send-key --surface <id> <key>` for special keys
- `cmux rpc surface.focus {"surface_id":"..."}` for window focus
- cmux path resolved lazily via `CmuxPathFinder.shared.getCmuxPath()`

### cmux identify

The `surface:N` format provides a stable reference to a terminal surface. Used as `cmuxSurfaceId` throughout the app.

## UI Integration

Focus and approval buttons in `InstanceRow` check multiplexer availability:

```swift
// Focus button shown when:
session.isInMultiplexer && (isYabaiAvailable || session.isInCmux)

// YabaiController used for window management (tmux path)
// CmuxController.focusSurface used for cmux path
```

`isYabaiAvailable` is checked once via `.task` modifier. cmux focus works independently of yabai.
