import CCState

@MainActor
func cannotObserveCommand() throws {
    let store = Store()
    let action = Command<Int, Void> { _ in 1 }
    try store.watch(action) {}
}
