import CCState
import SwiftUI

@MainActor
public final class StateWriter<Value> {
    private let store: Store?
    private let signal: CCState.State<Value>
    internal init(store: Store?, signal: CCState.State<Value>) {
        self.store = store
        self.signal = signal
    }

    public func callAsFunction(_ value: Value) throws {
        guard let store else { throw StoreObservationError.missingStore }
        try store.set(signal, value)
    }
    public func update(_ transform: (Value) throws -> Value) throws {
        guard let store else { throw StoreObservationError.missingStore }
        try store.set(signal, update: transform)
    }
}

@MainActor
public final class CommandWriter<Value, Input> {
    private let store: Store?
    private let command: Command<Value, Input>
    internal init(store: Store?, command: Command<Value, Input>) {
        self.store = store
        self.command = command
    }

    @discardableResult
    public func callAsFunction(_ input: Input) throws -> Value {
        guard let store else { throw StoreObservationError.missingStore }
        return try store.set(command, input)
    }
    @discardableResult
    public func callAsFunction() throws -> Value where Input == Void { try self(()) }
}

@MainActor
internal final class ActionStorage<Action: AnyObject> {
    private var identity: SignalIdentity?
    private var action: Action?
    private let dispose: (Action) -> Void
    init(dispose: @escaping (Action) -> Void = { _ in }) { self.dispose = dispose }

    func get(store: Store?, signal: AnySignal, make: () -> Action) -> Action {
        let next = SignalIdentity(
            store: store.map(ObjectIdentifier.init), signal: ObjectIdentifier(signal), isTask: false)
        if identity == next, let action { return action }
        if let action { dispose(action) }
        identity = next
        let new = make()
        action = new
        return new
    }
    isolated deinit { if let action { dispose(action) } }
}

/// Stable while the Store and target are unchanged. Escaped writers retain their original target.
@MainActor
@propertyWrapper
public struct SignalSetter<Value>: @MainActor DynamicProperty {
    @Environment(\.ccstateStore) private var store
    @SwiftUI.State private var storage = ActionStorage<StateWriter<Value>>()
    private let signal: CCState.State<Value>
    public init(_ signal: CCState.State<Value>) { self.signal = signal }
    public var wrappedValue: StateWriter<Value> {
        storage.get(store: store, signal: signal) { StateWriter(store: store, signal: signal) }
    }
    public mutating func update() { _ = wrappedValue }
}

@MainActor
@propertyWrapper
public struct CommandSetter<Value, Input>: @MainActor DynamicProperty {
    @Environment(\.ccstateStore) private var store
    @SwiftUI.State private var storage = ActionStorage<CommandWriter<Value, Input>>()
    private let command: Command<Value, Input>
    public init(_ command: Command<Value, Input>) { self.command = command }
    public var wrappedValue: CommandWriter<Value, Input> {
        storage.get(store: store, signal: command) { CommandWriter(store: store, command: command) }
    }
    public mutating func update() { _ = wrappedValue }
}
