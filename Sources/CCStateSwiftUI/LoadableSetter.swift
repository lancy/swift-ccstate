import CCState
import Observation
import SwiftUI

/// A UI-owned operation observer. It preserves the original return value and never
/// cancels business work merely because this observer is replaced or destroyed.
@MainActor
@Observable
public final class LoadableAction<Value, Input, Return> {
    public private(set) var phase: OperationPhase<Value> = .idle
    @ObservationIgnored private let invoke: (Input) throws -> Return
    @ObservationIgnored private let resolve: (Return) -> ReadResult<Value>
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var active = true
    @ObservationIgnored internal private(set) var pending: Task<Void, Never>?

    internal init(invoke: @escaping (Input) throws -> Return, resolve: @escaping (Return) -> ReadResult<Value>) {
        self.invoke = invoke
        self.resolve = resolve
    }

    @discardableResult
    public func callAsFunction(_ input: Input) throws -> Return {
        generation += 1
        let version = generation
        pending?.cancel()
        pending = nil
        let returned = try invoke(input)
        // A synchronous command or listener can invoke this action again.
        guard active, generation == version else { return returned }
        switch resolve(returned) {
        case .value(let value):
            phase = .hasData(value)
        case .task(let awaitResult):
            phase = .loading
            if active, generation == version {
                pending = Task.immediate { @MainActor [weak self] in
                    let result: OperationPhase<Value>
                    do { result = .hasData(try await awaitResult()) } catch { result = .hasError(error) }
                    guard !Task.isCancelled, let self, self.active, self.generation == version else { return }
                    self.phase = result
                }
            }
        }
        return returned
    }

    @discardableResult
    public func callAsFunction() throws -> Return where Input == Void { try self(()) }

    internal func disconnect() {
        active = false
        generation += 1
        pending?.cancel()
        pending = nil
    }
    isolated deinit { pending?.cancel() }
}

/// The native counterpart of experimental useLoadableSet. Synchronous invocation
/// errors are thrown to the caller; asynchronous failures become phase.hasError.
@MainActor
@propertyWrapper
public struct LoadableSetter<Value, Input, Return>: @MainActor DynamicProperty {
    @Environment(\.ccstateStore) private var store
    @SwiftUI.State private var storage = ActionStorage<LoadableAction<Value, Input, Return>>(dispose: {
        $0.disconnect()
    })
    private let target: AnySignal
    private let make: (Store?) -> LoadableAction<Value, Input, Return>

    public init(_ command: Command<Value, Input>) where Return == Value {
        target = command
        make = { store in
            LoadableAction(
                invoke: { input in
                    guard let store else { throw StoreObservationError.missingStore }
                    return try store.set(command, input)
                }, resolve: { .value($0) })
        }
    }

    public init<Failure: Error>(task command: Command<Task<Value, Failure>, Input>)
    where Return == Task<Value, Failure>, Value: Sendable {
        target = command
        make = { store in
            LoadableAction(
                invoke: { input in
                    guard let store else { throw StoreObservationError.missingStore }
                    return try store.set(command, input)
                }, resolve: { task in .task { try await task.value } })
        }
    }

    public init(_ state: CCState.State<Input>) where Value == Void, Return == Void {
        target = state
        make = { store in
            LoadableAction(
                invoke: { input in
                    guard let store else { throw StoreObservationError.missingStore }
                    try store.set(state, input)
                }, resolve: { .value($0) })
        }
    }

    public var wrappedValue: LoadableAction<Value, Input, Return> {
        storage.get(store: store, signal: target) { make(store) }
    }
    public mutating func update() { _ = wrappedValue }
}
