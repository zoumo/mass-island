# Notch UI

Mass Island renders a pill-shaped overlay anchored to the macOS notch, using a custom SwiftUI `Shape` for clipping.

## NotchShape

Custom SwiftUI `Shape` using quadratic Bezier curves. Not macOS native.

```swift
struct NotchShape: Shape {
    var topCornerRadius: CGFloat      // default 6 (closed), 19 (opened)
    var bottomCornerRadius: CGFloat   // default 14 (closed), 24 (opened)
}
```

### Path Geometry

```
   ←─ topR ─→                    ←─ topR ─→
   ╭─────────╮                    ╭─────────╮
   │  quad    │                    │  quad    │
   │ (inward) │                    │ (inward) │
   │          │                    │          │
   │          └────────────────────┘          │
   │            ← bottom edge (inset) →       │
   ╰──────╮                          ╭────────╯
     quad  │     bottomR + topR      │  quad
   (outward)   consumed each side   (outward)
```

- Top corners curve **inward** — control point at `(minX + r, minY)`, pulls curve away from corner
- Bottom corners curve **outward** — control point at corner apex, sweeps along bottom
- Bottom edge inset: `topR + bottomR` consumed on each side for curves
- Both radii are `animatableData` — smooth transition between closed/opened states

### Corner Radius Constants

```swift
private let cornerRadiusInsets = (
    opened: (top: CGFloat(19), bottom: CGFloat(24)),
    closed: (top: CGFloat(6),  bottom: CGFloat(14))
)
```

## clipShape Principle

`.clipShape(NotchShape)` applies an alpha mask:
- Pixels inside the Shape path → visible (alpha = 1)
- Pixels outside → transparent (alpha = 0)
- Bottom corner curves clip ~20pt from each side

This means content near the pill edges gets clipped by the curves, even if the HStack frame is wide enough.

## Closed Pill Layout

```
┌─ HStack(spacing: 0) ──────────────────────────────────┐
│                                                         │
│  ┌─Left Arm──┐  ┌──Center Rectangle──┐  ┌─Right Arm─┐ │
│  │ 🦀 [⚠️]   │  │  .fill(.black)     │  │ ✻ [3/5]   │ │
│  │ sideWidth  │  │  notchW - 6 + Δ   │  │ fixedSize  │ │
│  │  +18 perm  │  │  +40 counter       │  │            │ │
│  └───────────┘  │  +16 bounce        │  └───────────┘ │
│                  └───────────────────┘                  │
│                                                         │
│  .background(.black) ← fills entire HStack naturally    │
│  .clipShape(NotchShape) ← alpha mask crops to pill      │
└─────────────────────────────────────────────────────────┘
```

### Width Determination

Pill width = natural HStack content width. Key insight: `.background(.black)` fills whatever width the HStack produces, then `.clipShape(NotchShape)` crops it.

- **Left arm**: `sideWidth` (≈ `closedNotchSize.height - 12 + 10` ≈ 30pt) + 18pt if permission pending
- **Center Rectangle**: `closedNotchSize.width - 6` base, +40pt when agent counter visible, +16pt during bounce animation
- **Right arm**: `fixedSize` — ProcessingSpinner + optional counter text

To make pill wider: increase center Rectangle width. Content near edges is clipped by NotchShape curves.

### sideWidth Formula

```swift
private var sideWidth: CGFloat {
    max(0, closedNotchSize.height - 12) + 10
}
```

## Agent Counter (Minimized Pill)

Shows `active/total` next to ProcessingSpinner when >1 session exists.

```swift
private var activeAgentCount: Int {
    sessionMonitor.instances.filter {
        $0.phase == .processing || $0.phase == .compacting || $0.phase.isWaitingForApproval
    }.count
}

private var totalAgentCount: Int {
    sessionMonitor.instances.count
}

private var showAgentCounter: Bool {
    totalAgentCount > 1
}
```

### Rendering

```swift
HStack(spacing: 1) {
    Text("\(activeAgentCount)")
        .foregroundColor(TerminalColors.green)       // active count in green
    Text("/")
        .foregroundColor(.white.opacity(0.3))
    Text("\(totalAgentCount)")
        .foregroundColor(claudeOrange)               // total count in orange
}
.font(.system(size: 9, weight: .bold, design: .monospaced))
```

Only shown when `viewModel.status != .opened && showAgentCounter`. Center Rectangle gains +40pt to prevent clipping.

Counts all sessions (MASS + CC), not subagentState. Each MASS agent run is its own SessionState.

## Bounce Animation

When a session enters `.waitingForInput`, center Rectangle temporarily gains +16pt (`isBouncing`), creating a subtle pulse effect.

## expansionWidth

Calculated but effectively dead code — `closedContentWidth` is defined but never used in layout constraints. Pill width is purely determined by HStack content sizing.

```swift
private var expansionWidth: CGFloat {
    let permissionIndicatorWidth: CGFloat = hasPendingPermission ? 18 : 0
    let agentCounterWidth: CGFloat = showAgentCounter ? 56 : 0
    // ... returns base + addends based on activity state
}
```
