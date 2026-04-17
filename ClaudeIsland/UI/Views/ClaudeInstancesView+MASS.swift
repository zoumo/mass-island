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
    /// Claude Code sessions sorted by priority then date
    var ccSessions: [SessionState] {
        sortByPriority(sessionMonitor.instances.filter { $0.source == .claudeCode })
    }

    /// MASS sessions grouped by workspace
    var massWorkspaces: [(workspace: String, sessions: [SessionState])] {
        let massSessions = sessionMonitor.instances.filter { $0.source == .mass }
        let grouped = Dictionary(grouping: massSessions) { session -> String in
            // sessionId is "workspace/name", extract workspace
            let parts = session.sessionId.split(separator: "/", maxSplits: 1)
            return parts.count >= 1 ? String(parts[0]) : "default"
        }
        return grouped
            .map { (workspace: $0.key, sessions: sortByPriority($0.value)) }
            .sorted { a, b in
                // Sort workspaces: any active agent first, then alphabetical
                let activeA = a.sessions.contains { phasePriority($0.phase) == 0 }
                let activeB = b.sessions.contains { phasePriority($0.phase) == 0 }
                if activeA != activeB { return activeA }
                return a.workspace < b.workspace
            }
    }

    /// MASS workspaces section for the instances list
    @ViewBuilder
    var massWorkspacesSection: some View {
        ForEach(massWorkspaces, id: \.workspace) { group in
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
