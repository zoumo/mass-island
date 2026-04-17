//
//  NotchMenuView+MASS.swift
//  ClaudeIsland
//
//  MASS backend toggle logic for NotchMenuView.
//  Extracted to extension to minimize upstream diff.
//

import Foundation

extension NotchMenuView {
    /// Toggle Claude Code backend on/off
    func toggleClaudeCode() {
        claudeCodeEnabled.toggle()
        AppSettings.claudeCodeEnabled = claudeCodeEnabled
        if claudeCodeEnabled {
            viewModel.sessionMonitor?.startClaudeMonitoring()
        } else {
            viewModel.sessionMonitor?.stopClaudeMonitoring()
        }
    }

    /// Toggle MASS backend on/off
    func toggleMass() {
        massEnabled.toggle()
        AppSettings.massEnabled = massEnabled
        if massEnabled {
            viewModel.sessionMonitor?.startMassMonitoring()
        } else {
            viewModel.sessionMonitor?.stopMassMonitoring()
        }
    }
}
