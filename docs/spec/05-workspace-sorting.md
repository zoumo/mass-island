# Workspace Sorting

Instance list groups MASS agents by workspace and sorts active items first.

## Workspace Grouping

MASS session IDs follow `"workspace/name"` format. Workspace is extracted by splitting on `/`:

```swift
var massWorkspaces: [(workspace: String, sessions: [SessionState])] {
    // filter source == .mass
    // group by sessionId.split("/")[0], fallback "default"
    // sort: active workspaces first, then alphabetical
}
```

CC sessions are listed ungrouped, after their respective active/inactive MASS workspaces.

## Sort Order

```
Active zone:
  1. Active MASS workspaces (sorted alphabetically)
     └── sessions within: sorted by priority then recency
  2. Active CC sessions (sorted by priority then recency)

Inactive zone:
  3. Inactive MASS workspaces (sorted alphabetically)
     └── sessions within: sorted by priority then recency
  4. Inactive CC sessions (sorted by priority then recency)
```

### Active Determination

A session is active if `phasePriority(phase) == 0`:

```swift
func phasePriority(_ phase: SessionPhase) -> Int {
    switch phase {
    case .waitingForApproval, .processing, .compacting: return 0  // active
    case .waitingForInput: return 1                                // ready
    case .idle, .ended: return 2                                   // inactive
    }
}
```

A workspace is active if any of its sessions is active.

### Within-Group Sorting

```swift
func sortByPriority(_ sessions: [SessionState]) -> [SessionState] {
    sessions.sorted { a, b in
        let priorityA = phasePriority(a.phase)
        let priorityB = phasePriority(b.phase)
        if priorityA != priorityB { return priorityA < priorityB }
        let dateA = a.lastUserMessageDate ?? a.lastActivity
        let dateB = b.lastUserMessageDate ?? b.lastActivity
        return dateA > dateB    // most recent first
    }
}
```

## WorkspaceSectionHeader

Collapsible header for each MASS workspace group.

```
┌─────────────────────────────────────────┐
│ [MASS] workspace-name              3 ▾  │
└─────────────────────────────────────────┘
```

- "MASS" badge: monospaced 9pt bold, `TerminalColors.blue`, background opacity 0.15
- Workspace name + agent count
- Chevron toggles collapse (tracked in `collapsedWorkspaces: Set<String>`)
- Collapse animation: 0.2s easeInOut
- Session rows indented with `padding(.leading, 12)` inside workspace group

## Instance Row

Each session rendered as `InstanceRow` with:
- Left: state indicator (spinner for active, dot for idle)
- Center: title line + status/tool info line
- Right: action buttons (chat, focus, cancel, archive, approve/deny)

Source badge "CC" shown only for Claude Code sessions (MASS source shown in workspace header).
