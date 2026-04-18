<div align="center">
  <h3 align="center">Mass Island</h3>
  <p align="center">
    macOS notch overlay for monitoring MASS agents and Claude Code sessions.
    <br />
    Fork of <a href="https://github.com/farouqaldori/claude-island">Claude Island</a>, extended with MASS daemon integration.
  </p>
</div>

## What Changed from Claude Island

- **Dual backend** — Claude Code Hook path (original) + MASS daemon ARI (JSON-RPC over Unix socket)
- **Backend toggles** — Claude Code and MASS can be independently enabled/disabled
- **MASS socket config** — UI picker for custom socket path (default `/run/mass/mass.sock`)
- **Connection resilience** — Exponential backoff retry, auto-reconnect on daemon disconnect
- **Protocol alignment** — ARI types matching MASS Go daemon wire format (ACP ContentBlock, runtime state, etc.)
- **SIGPIPE protection** — SO_NOSIGPIPE on Unix sockets to prevent crash on broken pipe
- **Renamed** — Binary, bundle ID (`com.celestial.MassIsland`), logger subsystem all updated

## Architecture

```
┌─────────────────────────────────────────────┐
│                 Mass Island                 │
│                                             │
│  ┌──────────────┐    ┌───────────────────┐  │
│  │  Hook Path   │    │    MASS Path      │  │
│  │  (Claude Code)│    │  (ARI daemon)     │  │
│  │              │    │                   │  │
│  │ HookSocket   │    │ MassClient        │  │
│  │ SessionStore │    │ MassPoller        │  │
│  │ FileWatcher  │    │ EventWatcher      │  │
│  └──────┬───────┘    └────────┬──────────┘  │
│         │    Combine merge    │              │
│         └────────┬────────────┘              │
│                  ▼                           │
│       ClaudeSessionMonitor                  │
│                  │                           │
│                  ▼                           │
│            Notch UI (SwiftUI)               │
└─────────────────────────────────────────────┘
```

## Terminal Multiplexer Support

Mass Island supports both **tmux** and **cmux** as terminal multiplexers. Features like focus (eye icon), message sending, and tool approval work in either.

### cmux Setup

If you run Claude Code inside [cmux](https://github.com/manaflow-ai/cmux), you need to open cmux's socket access:

1. Open **cmux Settings** (gear icon or `Cmd+,`)
2. Find **Socket Control Mode** (套接字控制模式)
3. Change from "Only cmux processes" (仅限 cmux 进程) to **"All local processes"** (所有本地进程)

Without this, Mass Island cannot communicate with cmux to send messages or focus surfaces — you'll see "Broken pipe" errors in logs.

## Requirements

- macOS 15.6+
- MASS daemon and/or Claude Code CLI

## Build

```bash
xcodebuild -scheme ClaudeIsland -configuration Release build
```

## How It Works

**Claude Code path**: Hooks in `~/.claude/hooks/` communicate session state via Unix socket. Same as original Claude Island.

**MASS path**: Connects to MASS daemon socket, polls `agentrun/list` for active agent runs, subscribes to per-agent `runtime/watch_event` for live event streaming (K8s list-watch pattern).

Both paths merge into a unified session list displayed in the notch overlay.

## License

Apache 2.0 — inherited from [Claude Island](https://github.com/farouqaldori/claude-island)
