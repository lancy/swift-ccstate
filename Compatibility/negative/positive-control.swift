import CCState

@MainActor
func validAPI() throws {
    let store = Store()
    let source = State(0)
    let derived = Computed { try $0(source) * 2 }
    let action = Command<Void, Int> { context, value in try context.set(source, value) }
    let stop = try store.watch(derived) {}
    try store.set(action, 2)
    _ = try store.get(derived)
    try stop.cancel()
}
