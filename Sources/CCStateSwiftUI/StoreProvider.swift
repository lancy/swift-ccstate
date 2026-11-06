import CCState
import OSLog
import SwiftUI

private struct StoreKey: EnvironmentKey {
    static let defaultValue: Store? = nil
}

private struct CleanupErrorKey: EnvironmentKey {
    static let defaultValue: @MainActor (any Error) -> Void = { error in
        Logger(subsystem: "CCStateSwiftUI", category: "Observation")
            .error("Subscription cleanup failed: \(String(describing: error), privacy: .private)")
    }
}

extension EnvironmentValues {
    public var ccstateStore: Store? {
        get { self[StoreKey.self] }
        set { self[StoreKey.self] = newValue }
    }

    internal var ccstateCleanupError: @MainActor (any Error) -> Void {
        get { self[CleanupErrorKey.self] }
        set { self[CleanupErrorKey.self] = newValue }
    }
}

/// Supplies an explicitly owned Store. The provider never creates a new cache.
@MainActor
public struct StoreProvider<Content: View>: View {
    private let store: Store
    private let onCleanupError: (@MainActor (any Error) -> Void)?
    private let content: Content

    public init(
        _ store: Store, onCleanupError: (@MainActor (any Error) -> Void)? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.store = store
        self.onCleanupError = onCleanupError
        self.content = content()
    }

    public var body: some View {
        if let onCleanupError {
            content.environment(\.ccstateStore, store).environment(\.ccstateCleanupError, onCleanupError)
        } else {
            content.environment(\.ccstateStore, store)
        }
    }
}
