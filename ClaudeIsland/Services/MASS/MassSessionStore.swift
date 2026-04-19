//
//  MassSessionStore.swift
//  ClaudeIsland
//
//  Bridges MASS daemon events (MassPoller + EventWatcher) into SessionState
//  objects, replacing the hook-based SessionStore for MASS backend.
//

import Combine
import Foundation
import os.log

// MARK: - Connection State

enum MassConnectionState: Sendable, Equatable {
    case disconnected
    case connecting
    case connected
    case retrying(attempt: Int, nextRetryIn: TimeInterval)
}

actor MassSessionStore {
    static let shared = MassSessionStore()

    nonisolated static let logger = Logger(subsystem: "com.claudeisland", category: "MassSession")

    // MARK: - State

    private var sessions: [String: SessionState] = [:]
    private var watchers: [String: EventWatcher] = [:]
    private var textBuffers: [String: String] = [:]
    private var poller: MassPoller?
    private var massClient: MassClient?
    private var pollerTask: Task<Void, Never>?

    // Dedup flag: set true when we send a prompt, cleared on next user_message
    private var sentPrompt: Bool = false

    // MARK: - Published State

    private nonisolated(unsafe) let sessionsSubject = CurrentValueSubject<[SessionState], Never>([])
    private nonisolated(unsafe) let connectionSubject = CurrentValueSubject<MassConnectionState, Never>(.disconnected)

    nonisolated var sessionsPublisher: AnyPublisher<[SessionState], Never> {
        sessionsSubject.eraseToAnyPublisher()
    }

    nonisolated var connectionPublisher: AnyPublisher<MassConnectionState, Never> {
        connectionSubject.eraseToAnyPublisher()
    }

    private var currentSocketPath: String = ""

    private init() {}

    // MARK: - Lifecycle

    func start(socketPath: String) {
        currentSocketPath = socketPath
        let client = MassClient(socketPath: socketPath)
        self.massClient = client

        let poller = MassPoller(client: client)
        self.poller = poller

        pollerTask = Task { [weak self] in
            await poller.setCallbacks(
                onDiscovered: { [weak self] run in
                    await self?.handleDiscovered(run)
                },
                onRemoved: { [weak self] key in
                    await self?.handleRemoved(key)
                },
                onStateChanged: { [weak self] run in
                    await self?.handleStateChanged(run)
                },
                onConnectionLost: { [weak self] in
                    Self.logger.warning("Connection lost, will reconnect")
                    await self?.reconnect()
                }
            )

            // Retry loop with exponential backoff
            var attempt = 0
            self?.connectionSubject.send(.connecting)

            while !Task.isCancelled {
                do {
                    try await client.connect()
                    Self.logger.info("Connected to MASS daemon")
                    self?.connectionSubject.send(.connected)
                    break
                } catch {
                    attempt += 1
                    let delay = min(pow(2.0, Double(attempt)), 30.0)
                    Self.logger.error("Connection attempt \(attempt) failed: \(error). Retry in \(delay)s")
                    self?.connectionSubject.send(.retrying(attempt: attempt, nextRetryIn: delay))
                    try? await Task.sleep(for: .seconds(delay))
                }
            }

            guard !Task.isCancelled else { return }
            await poller.start()
        }
    }

    func stop() {
        pollerTask?.cancel()
        pollerTask = nil
        connectionSubject.send(.disconnected)
        Task {
            await poller?.stop()
            await massClient?.disconnect()
            for (_, watcher) in watchers {
                await watcher.stop()
            }
            watchers.removeAll()
            sessions.removeAll()
            sentPrompt = false
            publishState()
        }
    }

    func restart(socketPath: String) {
        stop()
        start(socketPath: socketPath)
    }

    private func reconnect() {
        let path = currentSocketPath
        stop()
        start(socketPath: path)
    }

    // MARK: - MassClient access (for prompt/cancel)

    func client() -> MassClient? {
        massClient
    }

    /// Mark that we sent a prompt, so the echoed user_message can be deduped.
    func markPromptSent() {
        sentPrompt = true
    }

    // MARK: - Poller Callbacks

    private func handleDiscovered(_ run: AgentRun) {
        let ws = run.metadata.workspace ?? "default"
        let id = "\(ws)/\(run.metadata.name)"
        let phase = massStateToPhase(run.status.state)

        sessions[id] = SessionState(
            sessionId: id,
            source: .mass,
            cwd: ws,
            projectName: run.metadata.name,
            phase: phase
        )

        Self.logger.info("Discovered agent run: \(id)")
        publishState()

        if let socketPath = run.status.run?.socketPath {
            NSLog("[MassSessionStore] agent %@ has runtime socket at: %@", id, socketPath)
            startWatcher(id: id, socketPath: socketPath)
        } else {
            NSLog("[MassSessionStore] agent %@ has no runtime socket yet", id)
        }
    }

    private func handleRemoved(_ key: String) {
        sessions.removeValue(forKey: key)
        if let watcher = watchers.removeValue(forKey: key) {
            Task { await watcher.stop() }
        }
        Self.logger.info("Removed agent run: \(key)")
        publishState()
    }

    private func handleStateChanged(_ run: AgentRun) {
        let ws = run.metadata.workspace ?? "default"
        let id = "\(ws)/\(run.metadata.name)"
        let newPhase = massStateToPhase(run.status.state)

        if sessions[id] != nil {
            // MASS agent state is authoritative from daemon — override even from .ended
            // (daemon may restart an agent, so .ended is not truly terminal for MASS)
            sessions[id]!.phase = newPhase
            sessions[id]!.lastActivity = Date()
        }

        // Start watcher if runtime socket appeared
        if let socketPath = run.status.run?.socketPath, watchers[id] == nil {
            startWatcher(id: id, socketPath: socketPath)
        }

        publishState()
    }

    // MARK: - EventWatcher

    private func startWatcher(id: String, socketPath: String) {
        guard watchers[id] == nil else { return }

        let watcher = EventWatcher(socketPath: socketPath, sessionId: id)
        watchers[id] = watcher

        Task {
            await watcher.setOnEvent { [weak self] sessionId, event in
                await self?.handleRunEvent(sessionId, event)
            }
            await watcher.setOnInitialStatus { [weak self] sessionId, status in
                await self?.handleInitialStatus(sessionId, status)
            }
            await watcher.start()
        }
    }

    // MARK: - Initial Status (from runtime/status)

    private func handleInitialStatus(_ id: String, _ status: RuntimeStatusResult) {
        guard sessions[id] != nil else { return }
        if let runtimeStatus = status.state.status {
            let newPhase = massStateToPhase(runtimeStatus)
            sessions[id]!.phase = newPhase
        }
        publishState()
    }

    // MARK: - Agent Run Event Handling

    private func handleRunEvent(_ id: String, _ event: AgentRunEvent) {
        guard var session = sessions[id] else { return }

        switch event.type {

        case EventType.runtimeUpdate:
            // Consolidated runtime_update: status, sessionInfo, usage are nested
            if let rtStatus = event.payload?.runtimeStatus,
               let newStatus = rtStatus.status {
                let newPhase = massStateToPhase(newStatus)
                session.phase = newPhase
                // Backup turn_end: idle status means turn is done
                if newStatus == "idle" {
                    session.phase = .waitingForInput
                }
            }
            if let info = event.payload?.sessionInfo, let title = info.title {
                let ci = session.conversationInfo
                session.conversationInfo = ConversationInfo(
                    summary: title,
                    lastMessage: ci.lastMessage,
                    lastMessageRole: ci.lastMessageRole,
                    lastToolName: ci.lastToolName,
                    firstUserMessage: ci.firstUserMessage,
                    lastUserMessageDate: ci.lastUserMessageDate,
                    usage: ci.usage
                )
            }
            if let usageData = event.payload?.usage {
                let ci = session.conversationInfo
                var usage = ci.usage
                if let cost = usageData.cost {
                    usage.outputTokens = Int(cost.amount * 100)
                }
                if let size = usageData.size {
                    usage.inputTokens = size
                }
                session.conversationInfo = ConversationInfo(
                    summary: ci.summary,
                    lastMessage: ci.lastMessage,
                    lastMessageRole: ci.lastMessageRole,
                    lastToolName: ci.lastToolName,
                    firstUserMessage: ci.firstUserMessage,
                    lastUserMessageDate: ci.lastUserMessageDate,
                    usage: usage
                )
            }
            // availableCommands, currentMode, configOptions: decoded and available
            // in event.payload but not yet surfaced in UI — ready for future use

        case EventType.agentMessage:
            mergeTextChunk(id: id, event: event, role: .assistant)
            sessions[id].map { session = $0 }

        case EventType.agentThinking:
            mergeTextChunk(id: id, event: event, role: .thinking)
            sessions[id].map { session = $0 }

        case EventType.userMessage:
            // Dedup: skip user_message if we sent this prompt ourselves
            if sentPrompt {
                sentPrompt = false
                break
            }
            let text = event.payload?.content?.text ?? ""
            session.chatItems.append(
                ChatHistoryItem(
                    id: UUID().uuidString,
                    type: .user(text),
                    timestamp: Date()
                )
            )

        case EventType.toolCall:
            // Tool call ends any in-progress assistant message streaming
            flushTextBuffer(id: id, role: .assistant)
            sessions[id].map { session = $0 }

            let payload = event.payload
            var input: [String: String] = [:]
            if let raw = payload?.rawInput, let dict = raw.value as? [String: Any] {
                for (k, v) in dict {
                    input[k] = "\(v)"
                }
            }
            let toolId = payload?.id ?? UUID().uuidString
            // Tool calls arrive as "already executed" — initial status is success
            session.chatItems.append(
                ChatHistoryItem(
                    id: toolId,
                    type: .toolCall(ToolCallItem(
                        name: payload?.title ?? "unknown",
                        input: input,
                        status: .success,
                        result: nil,
                        structuredResult: nil,
                        subagentTools: []
                    )),
                    timestamp: Date()
                )
            )

        case EventType.toolResult:
            let payload = event.payload
            let toolId = payload?.id ?? ""
            if let idx = session.chatItems.lastIndex(where: { $0.id == toolId }),
               case .toolCall(var tool) = session.chatItems[idx].type {
                // Incremental merge: only update fields when new event has actual data
                if let status = payload?.status {
                    tool.status = (status == "error") ? .error : .success
                }
                let resultText = payload?.toolContent?.compactMap { wire -> String? in
                    wire.content?.text
                }.joined(separator: "\n")
                if let text = resultText, !text.isEmpty {
                    tool.result = text
                }
                session.chatItems[idx] = ChatHistoryItem(
                    id: toolId,
                    type: .toolCall(tool),
                    timestamp: session.chatItems[idx].timestamp
                )
            }
            // Orphan tool_result (no matching tool_call): silently skip

        case EventType.plan:
            // Each plan event replaces the entire plan view
            if let entries = event.payload?.entries, !entries.isEmpty {
                let planText = entries.map { entry in
                    let icon: String
                    switch entry.status {
                    case "completed": icon = "[x]"
                    case "in_progress": icon = "[>]"
                    default: icon = "[ ]"
                    }
                    return "\(icon) \(entry.content)"
                }.joined(separator: "\n")

                // Replace existing plan item or create new one
                let planItemId = "\(id):plan"
                if let idx = session.chatItems.lastIndex(where: { $0.id == planItemId }) {
                    session.chatItems[idx] = ChatHistoryItem(
                        id: planItemId,
                        type: .thinking(planText),
                        timestamp: Date()
                    )
                } else {
                    session.chatItems.append(
                        ChatHistoryItem(
                            id: planItemId,
                            type: .thinking(planText),
                            timestamp: Date()
                        )
                    )
                }
            }

        case EventType.error:
            session.chatItems.append(
                ChatHistoryItem(
                    id: UUID().uuidString,
                    type: .assistant("Error: \(event.payload?.message ?? "unknown")"),
                    timestamp: Date()
                )
            )

        case EventType.turnStart:
            session.phase = .processing

        case EventType.turnEnd:
            // Flush any in-progress text buffers
            flushTextBuffer(id: id, role: .assistant)
            flushTextBuffer(id: id, role: .thinking)
            sessions[id].map { session = $0 }

            session.phase = .waitingForInput

        default:
            break
        }

        session.lastActivity = Date()
        sessions[id] = session
        publishState()
    }

    // MARK: - Text Chunk Merging (streaming blocks)

    private enum TextRole { case assistant, thinking }

    private func mergeTextChunk(id: String, event: AgentRunEvent, role: TextRole) {
        let text = event.payload?.content?.text ?? ""
        let blockStatus = event.payload?.status
        let bufferKey = "\(id):\(role)"

        switch blockStatus {
        case BlockStatus.start:
            textBuffers[bufferKey] = text
            let itemType: ChatHistoryItemType =
                role == .assistant ? .assistant(text) : .thinking(text)
            sessions[id]?.chatItems.append(
                ChatHistoryItem(id: UUID().uuidString, type: itemType, timestamp: Date())
            )

        case BlockStatus.streaming:
            // Late join: if we get streaming without a start, auto-create the item
            if textBuffers[bufferKey] == nil {
                textBuffers[bufferKey] = ""
                let itemType: ChatHistoryItemType =
                    role == .assistant ? .assistant("") : .thinking("")
                sessions[id]?.chatItems.append(
                    ChatHistoryItem(id: UUID().uuidString, type: itemType, timestamp: Date())
                )
            }
            textBuffers[bufferKey, default: ""] += text
            updateLastItem(id: id, role: role)

        case BlockStatus.end:
            // Late join: if we get end without prior chunks, auto-create
            if textBuffers[bufferKey] == nil {
                textBuffers[bufferKey] = ""
                let itemType: ChatHistoryItemType =
                    role == .assistant ? .assistant("") : .thinking("")
                sessions[id]?.chatItems.append(
                    ChatHistoryItem(id: UUID().uuidString, type: itemType, timestamp: Date())
                )
            }
            textBuffers[bufferKey, default: ""] += text
            updateLastItem(id: id, role: role)
            textBuffers.removeValue(forKey: bufferKey)

        default:
            // Single-shot message (no streaming)
            let itemType: ChatHistoryItemType =
                role == .assistant ? .assistant(text) : .thinking(text)
            sessions[id]?.chatItems.append(
                ChatHistoryItem(id: UUID().uuidString, type: itemType, timestamp: Date())
            )
        }
    }

    /// Flush any in-progress text buffer (e.g. when tool_call truncates assistant message)
    private func flushTextBuffer(id: String, role: TextRole) {
        let bufferKey = "\(id):\(role)"
        if textBuffers[bufferKey] != nil {
            updateLastItem(id: id, role: role)
            textBuffers.removeValue(forKey: bufferKey)
        }
    }

    private func updateLastItem(id: String, role: TextRole) {
        let bufferKey = "\(id):\(role)"
        guard let buffer = textBuffers[bufferKey],
              let items = sessions[id]?.chatItems,
              let idx = items.lastIndex(where: { item in
                  switch (role, item.type) {
                  case (.assistant, .assistant): return true
                  case (.thinking, .thinking): return true
                  default: return false
                  }
              })
        else { return }

        let existingId = items[idx].id
        let existingTimestamp = items[idx].timestamp
        let newType: ChatHistoryItemType =
            role == .assistant ? .assistant(buffer) : .thinking(buffer)
        sessions[id]?.chatItems[idx] = ChatHistoryItem(
            id: existingId, type: newType, timestamp: existingTimestamp
        )
    }

    // MARK: - State Mapping

    private func massStateToPhase(_ state: String) -> SessionPhase {
        switch state {
        case "creating", "running":
            return .processing
        case "idle":
            return .waitingForInput
        case "stopped", "error":
            return .ended
        default:
            return .idle
        }
    }

    // MARK: - Publishing

    private func publishState() {
        let sorted = Array(sessions.values).sorted { $0.projectName < $1.projectName }
        sessionsSubject.send(sorted)
    }

    // MARK: - Queries

    func session(for id: String) -> SessionState? {
        sessions[id]
    }

    func allSessions() -> [SessionState] {
        Array(sessions.values)
    }
}
