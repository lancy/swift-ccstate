@MainActor
public final class Command<Value, Input>: AnySignal {
    internal let write: (CommandContext, Input) throws -> Value

    public init(
        debugLabel: String? = nil,
        _ write: @escaping (CommandContext, Input) throws -> Value
    ) {
        self.write = write
        super.init(prefix: "CMD", debugLabel: debugLabel)
    }

    public convenience init(
        debugLabel: String? = nil,
        _ write: @escaping (CommandContext) throws -> Value
    ) where Input == Void {
        self.init(debugLabel: debugLabel) { context, _ in try write(context) }
    }
}

@MainActor
internal final class Invocation {
    var isSynchronous = true
}

@MainActor
public struct CommandContext {
    private let store: Store
    private let invocation: Invocation
    public let get: Getter

    internal init(store: Store, invocation: Invocation) {
        self.store = store
        self.invocation = invocation
        get = Getter(read: store.readValue)
    }

    public func set<Value>(_ signal: State<Value>, _ value: Value) throws {
        try write { try store.writeState(signal, value) }
    }

    public func set<Value>(_ signal: State<Value>, update: (Value) throws -> Value) throws {
        try write { try store.updateState(signal, update) }
    }

    public func set<Value, Input>(_ command: Command<Value, Input>, _ input: Input) throws -> Value {
        try write { try store.invoke(command, input) }
    }

    public func set<Value>(_ command: Command<Value, Void>) throws -> Value { try set(command, ()) }

    private func write<Value>(_ body: () throws -> Value) throws -> Value {
        do {
            let value = try body()
            if !invocation.isSynchronous { try store.flush() }
            return value
        } catch {
            if !invocation.isSynchronous { try store.flush() }
            throw error
        }
    }
}

@MainActor
public func command<Value, Input>(
    debugLabel: String? = nil,
    _ write: @escaping (CommandContext, Input) throws -> Value
) -> Command<Value, Input> {
    Command(debugLabel: debugLabel, write)
}

@MainActor
public func command<Value>(
    debugLabel: String? = nil,
    _ write: @escaping (CommandContext) throws -> Value
) -> Command<Value, Void> {
    Command(debugLabel: debugLabel, write)
}

@MainActor
public func asyncCommand<Value: Sendable, Input>(
    debugLabel: String? = nil,
    _ write: @escaping @MainActor (CommandContext, Input) async throws -> Value
) -> Command<Task<Value, Error>, Input> {
    Command(debugLabel: debugLabel) { context, input in
        Task.immediate { @MainActor in try await write(context, input) }
    }
}
