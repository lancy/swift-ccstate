import CCState
import SwiftUI

/// A view-local subscription. Requests and computed caches remain in the Store.
@MainActor
@propertyWrapper
public struct LoadableValue<Value>: @MainActor DynamicProperty {
    @Environment(\.ccstateStore) private var store
    @Environment(\.ccstateCleanupError) private var onCleanupError
    @SwiftUI.State private var observation = ReadObservation<Value>()
    private let source: (Store?) -> ReadSource<Value>
    private let keepLast: Bool
    private let equals: (Value, Value) -> Bool

    public init(
        _ signal: Signal<Value>, keepLast: Bool = false,
        equals: @escaping (Value, Value) -> Bool = defaultEquality
    ) {
        source = { ReadSource(store: $0, signal: signal) }
        self.keepLast = keepLast
        self.equals = equals
    }

    public init<Failure: Error>(
        task signal: Signal<Task<Value, Failure>>, keepLast: Bool = false,
        equals: @escaping (Value, Value) -> Bool = defaultEquality
    ) where Value: Sendable {
        source = { ReadSource(store: $0, task: signal) }
        self.keepLast = keepLast
        self.equals = equals
    }

    public var wrappedValue: Loadable<Value> { observation.loadable }
    internal var resolved: Value? { observation.resolved }
    internal var state: LoadableState { observation.state }

    public mutating func update() {
        observation.connect(source(store), keepLast: keepLast, equals: equals, onCleanupError: onCleanupError)
    }
}

/// Reads only resolved data. The projected value exposes loading and failures.
@MainActor
@propertyWrapper
public struct ResolvedValue<Value>: DynamicProperty {
    @LoadableValue private var value: Loadable<Value>

    public init(
        _ signal: Signal<Value>, keepLast: Bool = false,
        equals: @escaping (Value, Value) -> Bool = defaultEquality
    ) {
        _value = LoadableValue(signal, keepLast: keepLast, equals: equals)
    }

    public init<Failure: Error>(
        task signal: Signal<Task<Value, Failure>>, keepLast: Bool = false,
        equals: @escaping (Value, Value) -> Bool = defaultEquality
    ) where Value: Sendable {
        _value = LoadableValue(task: signal, keepLast: keepLast, equals: equals)
    }

    public var wrappedValue: Value? { _value.resolved }
    public var projectedValue: Loadable<Value> { value }
}

/// Observes only loading/data/error transitions, without payload invalidations.
@MainActor
@propertyWrapper
public struct LoadableStatus<Value>: DynamicProperty {
    @LoadableValue private var value: Loadable<Value>

    public init(_ signal: Signal<Value>) { _value = LoadableValue(signal) }

    public init<Failure: Error>(task signal: Signal<Task<Value, Failure>>) where Value: Sendable {
        _value = LoadableValue(task: signal)
    }

    public var wrappedValue: LoadableState { _value.state }
}
