//
//  MassSocketSelector.swift
//  ClaudeIsland
//
//  Manages the expand/collapse state of the MASS socket picker row
//  and tracks the daemon connection state for UI display.
//

import Combine
import Foundation

@MainActor
class MassSocketSelector: ObservableObject {
    static let shared = MassSocketSelector()

    @Published var isPickerExpanded: Bool = false
    @Published var connectionState: MassConnectionState = .disconnected

    private let expandedHeight: CGFloat = 70
    private var cancellable: AnyCancellable?

    private init() {
        cancellable = MassSessionStore.shared.connectionPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                self?.connectionState = state
            }
    }

    var expandedPickerHeight: CGFloat {
        guard isPickerExpanded else { return 0 }
        return expandedHeight
    }
}
