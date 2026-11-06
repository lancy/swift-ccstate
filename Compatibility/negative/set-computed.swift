import CCState

@MainActor
func cannotWriteComputed() throws {
    let store = Store()
    let value = Computed { _ in 1 }
    try store.set(value, 2)
}
