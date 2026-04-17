import Foundation
import JSONRPC

// MARK: - EventWatcher — connects to agent run socket, watches event stream

actor EventWatcher {
    private let socketPath: String
    private let sessionId: String
    private var session: JSONRPCSession?
    private var lastSeq: Int = 0
    private var running = false

    var onEvent: (@Sendable (String, AgentRunEvent) async -> Void)?
    var onInitialStatus: (@Sendable (String, RuntimeStatusResult) async -> Void)?

    init(socketPath: String, sessionId: String) {
        self.socketPath = socketPath
        self.sessionId = sessionId
    }

    func start() async {
        running = true
        NSLog("[EventWatcher:%@] starting, socket: %@", sessionId, socketPath)
        while running {
            do {
                try await connectAndWatch()
            } catch {
                NSLog("[EventWatcher:%@] connection error: %@", sessionId, "\(error)")
                if running {
                    try? await Task.sleep(for: .seconds(2))
                }
            }
        }
    }

    func stop() {
        running = false
        session = nil
    }

    private func connectAndWatch() async throws {
        NSLog("[EventWatcher:%@] connecting to %@", sessionId, socketPath)
        let channel = try makeUnixSocketDataChannel(path: socketPath)
        let rpcSession = JSONRPCSession(channel: channel)
        self.session = rpcSession

        // Start watching events from last known seq
        let watchParams = WatchEventParams(fromSeq: lastSeq)
        NSLog("[EventWatcher:%@] sending runtime/watch_event fromSeq=%d", sessionId, lastSeq)
        let _: WatchEventResult = try await rpcSession.response(
            to: "runtime/watch_event", params: watchParams
        )
        NSLog("[EventWatcher:%@] watch_event subscribed, listening for events...", sessionId)

        // Fetch initial runtime status (optional, best-effort)
        do {
            nonisolated struct EmptyParams: Codable, Sendable {}
            let status: RuntimeStatusResult = try await rpcSession.response(
                to: "runtime/status", params: EmptyParams()
            )
            NSLog("[EventWatcher:%@] runtime/status: %@", sessionId, status.state.status ?? "unknown")
            await onInitialStatus?(sessionId, status)
        } catch {
            NSLog("[EventWatcher:%@] runtime/status failed (non-fatal): %@", sessionId, "\(error)")
        }

        // Listen for runtime/event_update notifications via eventSequence
        for await event in await rpcSession.eventSequence {
            guard running else { break }

            switch event {
            case .notification(let notification, let data):
                NSLog("[EventWatcher:%@] notification: %@ (%d bytes)", sessionId, notification.method, data.count)
                if notification.method == "runtime/event_update" {
                    await handleEventData(data)
                }
            default:
                NSLog("[EventWatcher:%@] non-notification event received", sessionId)
                break
            }
        }
        NSLog("[EventWatcher:%@] eventSequence ended", sessionId)
    }

    func setOnEvent(_ handler: @escaping @Sendable (String, AgentRunEvent) async -> Void) {
        self.onEvent = handler
    }

    func setOnInitialStatus(_ handler: @escaping @Sendable (String, RuntimeStatusResult) async -> Void) {
        self.onInitialStatus = handler
    }

    private func handleEventData(_ data: Data) async {
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601

            // The notification data contains the full JSON-RPC notification.
            // We need to extract the params field which contains the AgentRunEvent.
            nonisolated struct NotificationWrapper: Decodable, Sendable {
                let params: AgentRunEvent?
            }

            let wrapper = try decoder.decode(NotificationWrapper.self, from: data)
            guard let runEvent = wrapper.params else {
                NSLog("[EventWatcher:%@] decoded notification but params was nil", sessionId)
                return
            }

            // Dedup
            guard runEvent.seq > lastSeq else { return }
            lastSeq = runEvent.seq

            NSLog("[EventWatcher:%@] event seq=%d type=%@", sessionId, runEvent.seq, runEvent.type)
            await onEvent?(sessionId, runEvent)
        } catch {
            NSLog("[EventWatcher:%@] decode error: %@", sessionId, "\(error)")
            if let str = String(data: data, encoding: .utf8) {
                NSLog("[EventWatcher:%@] raw  %@", sessionId, String(str.prefix(500)))
            }
        }
    }
}
