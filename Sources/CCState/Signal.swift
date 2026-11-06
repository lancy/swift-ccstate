// Ported from e7h4n/ccstate (MIT). See LICENSE and Compatibility/README.md.

@MainActor
public class AnySignal: Hashable, CustomStringConvertible {
    private static var nextID = 0
    public nonisolated let id: Int
    public nonisolated let debugLabel: String?
    private nonisolated let prefix: String
    // A store must not keep an otherwise unreachable signal or its value alive.
    // Isolated destruction removes the cache entry without periodic sweeping.
    internal var cleanups: [ObjectIdentifier: @MainActor () -> Void] = [:]

    internal init(prefix: String, debugLabel: String?) {
        id = Self.nextID
        Self.nextID += 1
        self.prefix = prefix
        self.debugLabel = debugLabel
    }

    isolated deinit {
        for cleanup in cleanups.values { cleanup() }
    }

    public nonisolated var description: String {
        "\(prefix)\(id)" + (debugLabel.map { ":\($0)" } ?? "")
    }

    public nonisolated static func == (lhs: AnySignal, rhs: AnySignal) -> Bool { lhs === rhs }
    public nonisolated func hash(into hasher: inout Hasher) { hasher.combine(ObjectIdentifier(self)) }

    internal var isComputed: Bool { false }
    internal func initialRecord() -> Record { preconditionFailure("Abstract signal") }
    internal func evaluate(_ get: Getter, _ options: ComputedOptions) throws -> Any {
        preconditionFailure("Only computed signals can be evaluated")
    }
    internal func equals(_ lhs: Any, _ rhs: Any) -> Bool { false }
}

@MainActor
public class Signal<Value>: AnySignal {}

@MainActor
public final class State<Value>: Signal<Value> {
    public let initialValue: Value
    private let isEqual: (Value, Value) -> Bool

    public init(
        _ initialValue: Value, debugLabel: String? = nil,
        equals: @escaping (Value, Value) -> Bool = defaultEquality
    ) {
        self.initialValue = initialValue
        isEqual = equals
        super.init(prefix: "S", debugLabel: debugLabel)
    }

    override func initialRecord() -> Record {
        Record(signal: self, result: .success(initialValue as Any), epoch: 0)
    }
    override func equals(_ lhs: Any, _ rhs: Any) -> Bool { isEqual(lhs as! Value, rhs as! Value) }
}

@MainActor
public final class Computed<Value>: Signal<Value> {
    private let read: (Getter, ComputedOptions) throws -> Value
    private let isEqual: (Value, Value) -> Bool

    public init(
        debugLabel: String? = nil, equals: @escaping (Value, Value) -> Bool = defaultEquality,
        _ read: @escaping (Getter, ComputedOptions) throws -> Value
    ) {
        self.read = read
        isEqual = equals
        super.init(prefix: "CPT", debugLabel: debugLabel)
    }

    public convenience init(
        debugLabel: String? = nil,
        equals: @escaping (Value, Value) -> Bool = defaultEquality,
        _ read: @escaping (Getter) throws -> Value
    ) {
        self.init(debugLabel: debugLabel, equals: equals) { get, _ in try read(get) }
    }

    override var isComputed: Bool { true }
    override func initialRecord() -> Record { Record(signal: self, result: nil, epoch: -1) }
    override func evaluate(_ get: Getter, _ options: ComputedOptions) throws -> Any { try read(get, options) }
    override func equals(_ lhs: Any, _ rhs: Any) -> Bool { isEqual(lhs as! Value, rhs as! Value) }
}

/// Swift value types use Equatable; reference types use identity, as JS objects do.
/// Supply `equals:` for values with another equality contract.
public func defaultEquality<Value>(_ lhs: Value, _ rhs: Value) -> Bool {
    let left: Any = lhs
    let right: Any = rhs
    // Erase before inspecting: type(of:) on an Error existential otherwise
    // reports the existential metatype, and bridging Error may create NSError.
    if type(of: left) is AnyObject.Type { return (left as AnyObject) === (right as AnyObject) }
    if let value = lhs as? any Equatable { return value.equalsErased(rhs) }
    return false
}

extension Equatable {
    fileprivate func equalsErased(_ other: Any) -> Bool { (other as? Self).map { self == $0 } ?? false }
}

@MainActor
public struct Getter {
    internal let read: (AnySignal) throws -> Any
    public func callAsFunction<Value>(_ signal: Signal<Value>) throws -> Value {
        try read(signal) as! Value
    }
}

@MainActor
public func state<Value>(_ initialValue: Value, debugLabel: String? = nil) -> State<Value> {
    State(initialValue, debugLabel: debugLabel)
}

@MainActor
public func computed<Value>(
    debugLabel: String? = nil,
    _ read: @escaping (Getter) throws -> Value
) -> Computed<Value> {
    Computed(debugLabel: debugLabel, read)
}

@MainActor
public func computed<Value>(
    debugLabel: String? = nil,
    _ read: @escaping (Getter, ComputedOptions) throws -> Value
) -> Computed<Value> {
    Computed(debugLabel: debugLabel, read)
}
