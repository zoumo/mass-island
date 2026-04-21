//
//  TerminalVisibilityDetector.swift
//  ClaudeIsland
//
//  Detects if terminal windows are visible on current space
//

import AppKit
import CoreGraphics
import Foundation

struct TerminalVisibilityDetector {
    /// Check if another app is in fullscreen mode on the current space.
    /// Queries on-screen windows (current space) for any standard-layer window
    /// whose size covers the full screen — this indicates a native-fullscreen app.
    /// Our own windows (Mass Island) are excluded.
    static func isFullscreenAppActive() -> Bool {
        guard let screen = NSScreen.main else { return false }

        let selfPid = getpid()
        guard let windowList = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID
        ) as? [[String: Any]] else {
            return false
        }

        let screenW = screen.frame.width
        let screenH = screen.frame.height

        for window in windowList {
            guard let pid = window[kCGWindowOwnerPID as String] as? Int32,
                  pid != selfPid,
                  let layer = window[kCGWindowLayer as String] as? Int,
                  layer == 0,
                  let bounds = window[kCGWindowBounds as String] as? [String: CGFloat] else {
                continue
            }
            let w = bounds["Width"] ?? 0
            let h = bounds["Height"] ?? 0
            if w >= screenW && h >= screenH {
                return true
            }
        }
        return false
    }

    /// Check if any terminal window is visible on the current space
    static func isTerminalVisibleOnCurrentSpace() -> Bool {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]

        guard let windowList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return false
        }

        for window in windowList {
            guard let ownerName = window[kCGWindowOwnerName as String] as? String,
                  let layer = window[kCGWindowLayer as String] as? Int,
                  layer == 0 else { continue }

            if TerminalAppRegistry.isTerminal(ownerName) {
                return true
            }
        }

        return false
    }

    /// Check if the frontmost (active) application is a terminal
    static func isTerminalFrontmost() -> Bool {
        guard let frontmostApp = NSWorkspace.shared.frontmostApplication,
              let bundleId = frontmostApp.bundleIdentifier else {
            return false
        }

        return TerminalAppRegistry.isTerminalBundle(bundleId)
    }

    /// Check if a Claude session is currently focused (user is looking at it)
    /// - Parameter sessionPid: The PID of the Claude process
    /// - Returns: true if the session's terminal is frontmost and (for tmux) the pane is active
    static func isSessionFocused(sessionPid: Int) async -> Bool {
        // If no terminal is frontmost, session is definitely not focused
        guard isTerminalFrontmost() else {
            return false
        }

        let tree = ProcessTreeBuilder.shared.buildTree()
        let mux = ProcessTreeBuilder.shared.detectMultiplexer(pid: sessionPid, tree: tree)

        switch mux {
        case .tmux:
            // For tmux sessions, check if the session's pane is active
            return await TmuxTargetFinder.shared.isSessionPaneActive(claudePid: sessionPid)
        case .cmux:
            // For cmux sessions, assume focused if terminal is frontmost
            // (cmux doesn't expose a "which surface is active" query yet)
            return true
        case .none:
            // For non-multiplexer sessions, check if the session's terminal app is frontmost
            guard let sessionTerminalPid = ProcessTreeBuilder.shared.findTerminalPid(forProcess: sessionPid, tree: tree),
                  let frontmostApp = NSWorkspace.shared.frontmostApplication else {
                return false
            }

            return sessionTerminalPid == Int(frontmostApp.processIdentifier)
        }
    }
}
