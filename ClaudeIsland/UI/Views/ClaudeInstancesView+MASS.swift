//
//  ClaudeInstancesView+MASS.swift
//  ClaudeIsland
//
//  MASS workspace grouping and UI for ClaudeInstancesView.
//  Extracted to extension to minimize upstream diff.
//

import SwiftUI

// MARK: - MASS Grouping & Section

extension ClaudeInstancesView {
    // MARK: - Session Grouping

    /// Whether a session is active (processing/approval/compacting)
    func isActive(_ session: SessionState) -> Bool {
        phasePriority(session.phase) == 0
    }

    /// Whether a workspace group has any active session
    func isWorkspaceActive(_ group: (workspace: String, sessions: [SessionState])) -> Bool {
        group.sessions.contains { isActive($0) }
    }

    /// All MASS workspaces grouped by workspace name
    var massWorkspaces: [(workspace: String, sessions: [SessionState])] {
        let massSessions = sessionMonitor.instances.filter { $0.source == .mass }
        let grouped = Dictionary(grouping: massSessions) { session -> String in
            let parts = session.sessionId.split(separator: "/", maxSplits: 1)
            return parts.count >= 1 ? String(parts[0]) : "default"
        }
        return grouped
            .map { (workspace: $0.key, sessions: sortByPriority($0.value)) }
            .sorted { a, b in
                let activeA = a.sessions.contains { isActive($0) }
                let activeB = b.sessions.contains { isActive($0) }
                if activeA != activeB { return activeA }
                return a.workspace < b.workspace
            }
    }

    /// Active MASS workspaces (any session processing/approval)
    var activeMassWorkspaces: [(workspace: String, sessions: [SessionState])] {
        massWorkspaces.filter { isWorkspaceActive($0) }
    }

    /// Inactive MASS workspaces
    var inactiveMassWorkspaces: [(workspace: String, sessions: [SessionState])] {
        massWorkspaces.filter { !isWorkspaceActive($0) }
    }

    /// Active CC sessions
    var activeCCSessions: [SessionState] {
        sortByPriority(sessionMonitor.instances.filter { $0.source == .claudeCode && isActive($0) })
    }

    /// Inactive CC sessions
    var inactiveCCSessions: [SessionState] {
        sortByPriority(sessionMonitor.instances.filter { $0.source == .claudeCode && !isActive($0) })
    }

    // MARK: - MASS Workspace Section

    /// Render a workspace group (header + rows)
    @ViewBuilder
    func workspaceSection(for group: (workspace: String, sessions: [SessionState])) -> some View {
        WorkspaceSectionHeader(
            workspace: group.workspace,
            agentCount: group.sessions.count,
            isCollapsed: collapsedWorkspaces.contains(group.workspace)
        ) {
            withAnimation(.easeInOut(duration: 0.2)) {
                if collapsedWorkspaces.contains(group.workspace) {
                    collapsedWorkspaces.remove(group.workspace)
                } else {
                    collapsedWorkspaces.insert(group.workspace)
                }
            }
        }

        if !collapsedWorkspaces.contains(group.workspace) {
            ForEach(group.sessions) { session in
                instanceRow(for: session)
                    .padding(.leading, 12)
            }
        }
    }
}

// MARK: - Workspace Section Header

struct WorkspaceSectionHeader: View {
    let workspace: String
    let agentCount: Int
    let isCollapsed: Bool
    let onToggle: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 8) {
                Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.white.opacity(0.4))
                    .frame(width: 10)

                Text("MASS")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(TerminalColors.blue)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 3)
                            .fill(TerminalColors.blue.opacity(0.15))
                    )

                Text(workspace)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white.opacity(0.7))

                Text("\(agentCount)")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(.white.opacity(0.35))

                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isHovered ? Color.white.opacity(0.06) : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}
