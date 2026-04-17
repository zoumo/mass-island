//
//  MassSocketPickerRow.swift
//  ClaudeIsland
//
//  Settings row for configuring the MASS daemon socket path.
//  Expandable inline with a text field for direct path editing.
//

import SwiftUI

struct MassSocketPickerRow: View {
    @ObservedObject private var selector = MassSocketSelector.shared
    @State private var editingPath: String = ""
    @State private var isHovered: Bool = false

    private var isExpanded: Bool { selector.isPickerExpanded }

    var body: some View {
        VStack(spacing: 0) {
            // Main row
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    if !isExpanded {
                        editingPath = AppSettings.massSocketPath
                    }
                    selector.isPickerExpanded.toggle()
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "network")
                        .font(.system(size: 12))
                        .foregroundColor(textColor)
                        .frame(width: 16)

                    Text("MASS Socket")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(textColor)

                    Spacer()

                    connectionIndicator

                    Text(shortenedPath(AppSettings.massSocketPath))
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.4))
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.4))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(isHovered ? Color.white.opacity(0.08) : Color.clear)
                )
            }
            .buttonStyle(.plain)
            .onHover { isHovered = $0 }

            // Expanded: inline text field
            if isExpanded {
                VStack(spacing: 6) {
                    HStack(spacing: 6) {
                        TextField("Socket path", text: $editingPath)
                            .textFieldStyle(.plain)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.white.opacity(0.9))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(Color.white.opacity(0.06))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
                            )
                            .onSubmit { applyPath() }

                        Button {
                            applyPath()
                        } label: {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 14))
                                .foregroundColor(TerminalColors.green)
                        }
                        .buttonStyle(.plain)
                    }

                    // Quick action: reset to default
                    Button {
                        editingPath = ""
                        applyPath()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.counterclockwise")
                                .font(.system(size: 9))
                            Text("Reset to default (/run/mass/mass.sock)")
                                .font(.system(size: 10))
                        }
                        .foregroundColor(.white.opacity(0.4))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.leading, 28)
                .padding(.trailing, 12)
                .padding(.top, 6)
                .padding(.bottom, 4)
            }
        }
    }

    // MARK: - Connection Indicator

    @ViewBuilder
    private var connectionIndicator: some View {
        switch selector.connectionState {
        case .connected:
            Circle()
                .fill(TerminalColors.green)
                .frame(width: 6, height: 6)
        case .connecting, .retrying:
            Circle()
                .fill(TerminalColors.amber)
                .frame(width: 6, height: 6)
                .opacity(0.8)
        case .disconnected:
            Circle()
                .fill(Color.white.opacity(0.3))
                .frame(width: 6, height: 6)
        }
    }

    // MARK: - Helpers

    private var textColor: Color {
        .white.opacity(isHovered ? 1.0 : 0.7)
    }

    private func shortenedPath(_ raw: String) -> String {
        let home = NSHomeDirectory()
        if raw.hasPrefix(home) {
            return "~" + raw.dropFirst(home.count)
        }
        return raw
    }

    private func applyPath() {
        let path = editingPath.trimmingCharacters(in: .whitespaces)
        AppSettings.massSocketPath = path
        editingPath = AppSettings.massSocketPath
        Task {
            await MassSessionStore.shared.restart(socketPath: AppSettings.massSocketPath)
        }
    }
}
