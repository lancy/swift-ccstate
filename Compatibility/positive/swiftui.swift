import CCState
import CCStateSwiftUI
import SwiftUI

@MainActor
private enum ExampleSignals {
    static let count = CCState.State(0)
    static let profile = computedTask { _, _ in "profile" }
    static let increment = Command<Void, Void> { context in try context.set(count, update: { $0 + 1 }) }
    static let save = asyncCommand { (context: CommandContext, value: Int) in
        try context.set(count, value)
        return value
    }
}

@MainActor
private struct ExampleView: View {
    @LoadableValue(ExampleSignals.count) private var count
    @ResolvedValue(task: ExampleSignals.profile, keepLast: true) private var profile
    @LoadableStatus(task: ExampleSignals.profile) private var status
    @SignalSetter(ExampleSignals.count) private var setCount
    @CommandSetter(ExampleSignals.increment) private var increment
    @LoadableSetter(task: ExampleSignals.save) private var save

    var body: some View {
        VStack {
            Text(String(count.data ?? 0))
            Text(profile ?? "waiting")
            Text(String(describing: status))
            Text(String(describing: $profile.state))
            Text(String(describing: save.phase.state))
        }
    }

    func actions() throws {
        try setCount(2)
        try setCount.update { $0 + 1 }
        try increment()
        let task = try save(3)
        task.cancel()
    }
}

@MainActor
func sampleRoot(store: Store) -> some View { StoreProvider(store) { ExampleView() } }
