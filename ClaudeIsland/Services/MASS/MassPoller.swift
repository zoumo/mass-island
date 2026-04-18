import Foundation

// MARK: - MassPoller — polls daemon agentrun/list, diffs against known set

actor MassPoller {
    private let client: MassClient
    private let interval: TimeInterval
    private var knownRuns: [String: AgentRun] = [:]  // key: "workspace/name"
    private var running = false

    var onDiscovered: (@Sendable (AgentRun) async -> Void)?
    var onRemoved: (@Sendable (String) async -> Void)?
    var onStateChanged: (@Sendable (AgentRun) async -> Void)?
    var onConnectionLost: (@Sendable () async -> Void)?

    private var consecutiveErrors = 0
    private let maxConsecutiveErrors = 3

    init(client: MassClient, interval: TimeInterval = 3.0) {
        self.client = client
        self.interval = interval
    }

    func start() async {
        running = true
        consecutiveErrors = 0
        while running {
            do {
                try await poll()
                consecutiveErrors = 0
            } catch {
                consecutiveErrors += 1
                NSLog("[MassPoller] poll error (%d/%d): %@", consecutiveErrors, maxConsecutiveErrors, "\(error)")
                if consecutiveErrors >= maxConsecutiveErrors {
                    NSLog("[MassPoller] Too many consecutive errors, signaling connection lost")
                    running = false
                    await onConnectionLost?()
                    return
                }
            }
            try? await Task.sleep(for: .seconds(interval))
        }
    }

    func stop() {
        running = false
    }

    private func poll() async throws {
        let runs = try await client.agentRunList()
        NSLog("[MassPoller] polled %d runs", runs.count)
        let currentKeys = Set(runs.map { agentRunKey($0) })
        let knownKeys = Set(knownRuns.keys)

        for run in runs {
            let key = agentRunKey(run)
            let isNew = !knownKeys.contains(key)
            let stateChanged = knownRuns[key]?.status.state != run.status.state

            if isNew || stateChanged {
                // Fetch full run detail (list doesn't include runtime socket info)
                let fullRun: AgentRun
                do {
                    fullRun = try await client.agentRunGet(
                        workspace: run.metadata.workspace ?? "default",
                        name: run.metadata.name
                    )
                } catch {
                    NSLog("[MassPoller] agentrun/get failed for %@: %@", key, "\(error)")
                    fullRun = run
                }

                knownRuns[key] = fullRun
                if isNew {
                    await onDiscovered?(fullRun)
                } else {
                    await onStateChanged?(fullRun)
                }
            } else {
                // State unchanged — still reconcile phase in case watcher missed an event
                await onStateChanged?(run)
            }
        }

        // Removed
        for key in knownKeys.subtracting(currentKeys) {
            knownRuns.removeValue(forKey: key)
            await onRemoved?(key)
        }
    }

    private func agentRunKey(_ run: AgentRun) -> String {
        "\(run.metadata.workspace ?? "default")/\(run.metadata.name)"
    }

    func setCallbacks(
        onDiscovered: @escaping @Sendable (AgentRun) async -> Void,
        onRemoved: @escaping @Sendable (String) async -> Void,
        onStateChanged: @escaping @Sendable (AgentRun) async -> Void,
        onConnectionLost: @escaping @Sendable () async -> Void
    ) {
        self.onDiscovered = onDiscovered
        self.onRemoved = onRemoved
        self.onStateChanged = onStateChanged
        self.onConnectionLost = onConnectionLost
    }
}
