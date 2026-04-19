# Connection Lifecycle

Connection management between Mass Island and the MASS daemon.

## Connection States

```swift
enum MassConnectionState: Sendable, Equatable {
    case disconnected
    case connecting
    case connected
    case retrying(attempt: Int, nextRetryIn: TimeInterval)
}
```

Published via `connectionSubject: CurrentValueSubject<MassConnectionState, Never>`.

## Startup Flow

```
MassSessionStore.start(socketPath:)
    │
    ├── Create MassClient(socketPath:)
    ├── Create MassPoller(client:)
    ├── Wire poller callbacks
    │
    └── Connection retry loop:
        ├── connectionSubject.send(.connecting)
        │
        ├── try client.connect()
        │   ├── success → .connected → poller.start()
        │   └── failure → attempt++ → .retrying(attempt, delay)
        │       └── sleep(delay) → retry
        │
        └── Exponential backoff:
            delay = min(2^attempt, 30.0) seconds
```

## Reconnection

Triggered by `MassPoller.onConnectionLost` callback:

```swift
private func reconnect() {
    let path = currentSocketPath
    stop()                    // cancel poller, disconnect client, clear state
    start(socketPath: path)   // full restart with same socket path
}
```

`stop()` tears down everything:
- Cancels poller task
- Stops all EventWatchers
- Clears sessions dict
- Sends `.disconnected`

## MassPoller Error Handling

```swift
let maxConsecutiveErrors = 3
var consecutiveErrors = 0
```

Each failed `poll()` increments `consecutiveErrors`. Three consecutive failures triggers `onConnectionLost()` → full reconnect.

Successful poll resets counter to 0.

## EventWatcher Reconnection

Per-agent EventWatchers have independent reconnect:

```swift
// Inside connectAndWatch()
while running {
    do {
        try await connectAndWatch()
    } catch {
        // Reconnect delay: 2 seconds
        try? await Task.sleep(for: .seconds(2))
    }
}
```

EventWatcher reconnects are independent of the main poller — a single agent's socket disconnecting doesn't trigger full daemon reconnect.

## State Diagram

```
              start()
                │
                ▼
         ┌─────────────┐
         │  connecting  │
         └──────┬───────┘
                │
     ┌──────────┴──────────┐
     │ connect()            │ error
     ▼                      ▼
┌──────────┐    ┌─────────────────────┐
│ connected │    │ retrying(attempt,   │
│           │    │   delay)            │
└─────┬─────┘    └────────┬────────────┘
      │                    │ sleep(delay)
      │                    └─── retry ──→ try connect()
      │
      │  3 consecutive poll errors
      │  (onConnectionLost)
      ▼
┌──────────────┐     stop() + start()
│ disconnected │ ──────────────────→ connecting
└──────────────┘
```

## Lifecycle Methods

```swift
func start(socketPath: String)    // initial connection
func stop()                       // full teardown
func restart(socketPath: String)  // stop + start (e.g., config change)
```
