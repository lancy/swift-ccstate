// Algorithm and write-boundary semantics ported from e7h4n/ccstate 6.1.0 (MIT).

internal struct OrderedSet<Element: Hashable> {
    private var membership: Set<Element> = []
    private(set) var elements: [Element] = []
    var count: Int { membership.count }
    var isEmpty: Bool { membership.isEmpty }
    func contains(_ value: Element) -> Bool { membership.contains(value) }
    mutating func insert(_ value: Element) {
        if membership.insert(value).inserted { elements.append(value) }
    }
    mutating func remove(_ value: Element) {
        if membership.remove(value) != nil { elements.removeAll { $0 == value } }
    }
    mutating func removeAll() {
        membership.removeAll(keepingCapacity: true)
        elements.removeAll(keepingCapacity: true)
    }
}

@MainActor
internal final class WeakSignal {
    weak let signal: AnySignal?
    init(_ signal: AnySignal) { self.signal = signal }
}

@MainActor
internal final class Dependencies {
    var entries: [(signal: AnySignal, epoch: Int)] = []
    private var indices: [AnySignal: Int] = [:]
    func set(_ signal: AnySignal, epoch: Int) {
        if let index = indices[signal] {
            entries[index].epoch = epoch
        } else {
            indices[signal] = entries.count
            entries.append((signal, epoch))
        }
    }
    func contains(_ signal: AnySignal) -> Bool { indices[signal] != nil }
}

@MainActor
internal final class Mount {
    private var reverse: [WeakSignal] = []
    var listeners = OrderedSet<Listener>()
    var dependents: [AnySignal] { reverse.compactMap(\.signal) }
    func add(_ signal: AnySignal) {
        reverse.removeAll { $0.signal == nil }
        if !reverse.contains(where: { $0.signal === signal }) { reverse.append(WeakSignal(signal)) }
    }
    func remove(_ signal: AnySignal) { reverse.removeAll { $0.signal == nil || $0.signal === signal } }
}

@MainActor
internal final class Record {
    weak let signal: AnySignal?
    var result: Result<Any, Error>?
    var epoch: Int
    var dependencies: Dependencies?
    var verifiedAt: Int?
    var mounted: Mount?
    var cancellation: EvaluationSignal?
    init(signal: AnySignal, result: Result<Any, Error>?, epoch: Int) {
        self.signal = signal
        self.result = result
        self.epoch = epoch
    }
}

@MainActor
internal final class RecordCache {
    private var storage: [ObjectIdentifier: Record] = [:]
    #if DEBUG || CCSTATE_TESTING
        var lookups = 0
    #endif
    subscript(key: ObjectIdentifier) -> Record? {
        get {
            #if DEBUG || CCSTATE_TESTING
                lookups += 1
            #endif
            return storage[key]
        }
        set { storage[key] = newValue }
    }
    var values: Dictionary<ObjectIdentifier, Record>.Values { storage.values }
    // Return the record so ARC releases it after the dictionary's exclusive
    // mutation ends: its dependencies may destroy signals and reenter cleanup.
    @discardableResult
    func removeValue(forKey key: ObjectIdentifier) -> Record? { storage.removeValue(forKey: key) }
}

@MainActor
internal final class Mutation {
    var dirty = Set<AnySignal>()
    var oldEpochs: [AnySignal: Int] = [:]
    var changedSources = OrderedSet<AnySignal>()
    var isFlushing = false
}

/// Reuse one Listener when the same callback observes several roots.
@MainActor
public final class Listener: Hashable {
    internal let call: () throws -> Void
    public init(_ call: @escaping () throws -> Void) { self.call = call }
    public nonisolated static func == (lhs: Listener, rhs: Listener) -> Bool { lhs === rhs }
    public nonisolated func hash(into hasher: inout Hasher) { hasher.combine(ObjectIdentifier(self)) }
}

/// Explicit, idempotent cleanup. Retaining a cancelled subscription retains no graph.
@MainActor
public final class Subscription {
    private var cleanup: (() throws -> Void)?
    internal init(_ cleanup: @escaping () throws -> Void) { self.cleanup = cleanup }
    public func cancel() throws {
        let action = cleanup
        cleanup = nil
        try action?()
    }
}

public struct ListenerErrors: Error {
    public let errors: [any Error]
}

public enum StoreError: Error, Equatable {
    case interceptorMustCallSynchronously
    case storeReleased
}

@MainActor
public final class Store {
    internal let records = RecordCache()
    internal let interceptor: StoreInterceptor
    private var writeVersion = 0
    private var changed = OrderedSet<AnySignal>()
    private var mutation: Mutation?
    private let work = Mutation()
    // Exposed to @testable tests, so complexity assertions measure graph visits.
    #if DEBUG || CCSTATE_TESTING
        internal var cacheLookups = 0
        internal var recordLookups: Int {
            get { records.lookups }
            set { records.lookups = newValue }
        }
    #endif

    public init(interceptor: StoreInterceptor = StoreInterceptor()) { self.interceptor = interceptor }

    isolated deinit {
        let key = ObjectIdentifier(self)
        for record in records.values { record.signal?.cleanups.removeValue(forKey: key) }
    }

    public func get<Value>(_ signal: Signal<Value>) throws -> Value { try readValue(signal) as! Value }

    public func set<Value>(_ signal: State<Value>, _ value: Value) throws {
        try publicWrite { try writeState(signal, value) }
    }

    public func set<Value>(_ signal: State<Value>, update: (Value) throws -> Value) throws {
        try publicWrite { try updateState(signal, update) }
    }

    @discardableResult
    public func set<Value, Input>(_ command: Command<Value, Input>, _ input: Input) throws -> Value {
        try publicWrite { try invoke(command, input) }
    }

    @discardableResult
    public func set<Value>(_ command: Command<Value, Void>) throws -> Value { try set(command, ()) }

    @discardableResult
    public func watch<Value>(_ signal: Signal<Value>, _ listener: Listener) throws -> Subscription {
        let mounted = try mount(signal)
        mounted.listeners.insert(listener)
        try flush()
        return Subscription { [self, signal, mounted, listener] in
            mounted.listeners.remove(listener)
            unmount(signal)
            try flush()
        }
    }

    @discardableResult
    public func watch<Value>(_ signal: Signal<Value>, _ listener: @escaping () throws -> Void) throws -> Subscription {
        try watch(signal, Listener(listener))
    }

    internal func record(_ signal: AnySignal) -> Record {
        let key = ObjectIdentifier(signal)
        if let existing = records[key] { return existing }
        let record = signal.initialRecord()
        records[key] = record
        signal.cleanups[ObjectIdentifier(self)] = { [weak self] in self?.records.removeValue(forKey: key) }
        return record
    }

    internal func readValue(_ signal: AnySignal) throws -> Any {
        try intercept(signal, event: .get) { try self.read(signal).result!.get() }
    }

    private func read(_ signal: AnySignal) throws -> Record {
        let current = record(signal)
        guard signal.isComputed else { return current }
        #if DEBUG || CCSTATE_TESTING
            cacheLookups += 1
        #endif
        if current.result != nil {
            let dirty = mutation?.dirty.contains(signal) ?? false
            if !dirty && (current.mounted != nil || current.verifiedAt == writeVersion) { return current }
            var valid = true
            for dependency in current.dependencies?.entries ?? [] {
                if try read(dependency.signal).epoch != dependency.epoch {
                    valid = false
                    break
                }
            }
            if valid {
                current.verifiedAt = writeVersion
                mutation?.dirty.remove(signal)
                return current
            }
        }
        _ = try intercept(signal, event: .computed) {
            self.evaluate(signal, record: current)
            // An interceptor observes the returned value; errors stay cached.
            if case .success(let value) = current.result { return value }
            return ()
        }
        return current
    }

    private func evaluate(_ signal: AnySignal, record current: Record) {
        let version = writeVersion
        let previousEpoch = current.epoch
        let wasDirty = mutation?.dirty.contains(signal) ?? false
        let oldDependencies = current.dependencies
        let dependencies = Dependencies()
        current.dependencies = dependencies
        let previousCancellation = current.cancellation
        current.cancellation = nil
        previousCancellation?.cancel()
        let options = ComputedOptions(record: current, dependencies: dependencies)
        let getter = Getter { [weak self, weak current, weak signal] dependency in
            guard let self else { throw StoreError.storeReleased }
            return try intercept(dependency, event: .get) {
                let dependencyRecord = try self.read(dependency)
                // Older async continuations can read, but cannot reattach edges.
                if let current, current.dependencies === dependencies {
                    dependencies.set(dependency, epoch: dependencyRecord.epoch)
                    if current.mounted != nil, let signal {
                        try self.mount(dependency).add(signal)
                    }
                }
                return try dependencyRecord.result!.get()
            }
        }
        let result = Result { try signal.evaluate(getter, options) }
        mutation?.dirty.remove(signal)
        for old in oldDependencies?.entries ?? [] where !dependencies.contains(old.signal) {
            records[ObjectIdentifier(old.signal)]?.mounted?.remove(signal)
            unmount(old.signal)
        }
        if !sameResult(current.result, result, signal: signal) {
            current.result = result
            current.epoch += 1
        }
        if wasDirty && current.epoch != previousEpoch { changed.insert(signal) }
        current.verifiedAt = version
    }

    private func sameResult(_ old: Result<Any, Error>?, _ new: Result<Any, Error>, signal: AnySignal) -> Bool {
        switch (old, new) {
        case (.success(let lhs), .success(let rhs)): signal.equals(lhs, rhs)
        case (.failure(let lhs), .failure(let rhs)): defaultEquality(lhs, rhs)
        default: false
        }
    }

    private func mount(_ signal: AnySignal) throws -> Mount {
        if let mounted = records[ObjectIdentifier(signal)]?.mounted { return mounted }
        interceptor.mount?(signal)
        let current = try read(signal)
        let mounted = Mount()
        current.mounted = mounted
        for dependency in current.dependencies?.entries ?? [] { try mount(dependency.signal).add(signal) }
        return mounted
    }

    private func unmount(_ signal: AnySignal) {
        guard let current = records[ObjectIdentifier(signal)], let mounted = current.mounted,
            mounted.dependents.isEmpty, mounted.listeners.isEmpty
        else { return }
        interceptor.unmount?(signal)
        for dependency in current.dependencies?.entries ?? [] {
            records[ObjectIdentifier(dependency.signal)]?.mounted?.remove(signal)
            unmount(dependency.signal)
        }
        current.mounted = nil
    }

    internal func writeState<Value>(_ signal: State<Value>, _ value: Value) throws {
        _ = try intercept(signal, event: .set, argument: value) {
            self.assign(signal, value)
            return ()
        }
    }

    internal func updateState<Value>(_ signal: State<Value>, _ updater: (Value) throws -> Value) throws {
        _ = try intercept(signal, event: .set) {
            let old = self.records[ObjectIdentifier(signal)]
            let value = try updater(old.map { try! $0.result!.get() as! Value } ?? signal.initialValue)
            // The updater may have subscribed or written; fetch the record again.
            self.assign(signal, value)
            return ()
        }
    }

    private func assign<Value>(_ signal: State<Value>, _ value: Value) {
        if let existing = records[ObjectIdentifier(signal)],
            case .success(let previous) = existing.result, signal.equals(previous, value)
        {
            return
        }
        writeVersion += 1
        let current: Record
        if let existing = records[ObjectIdentifier(signal)] {
            current = existing
            current.result = .success(value)
            current.epoch += 1
        } else {
            current = record(signal)
            current.result = .success(value)
        }
        changed.insert(signal)
        let dependents = current.mounted?.dependents ?? []
        if !dependents.isEmpty {
            let pending = pendingMutation()
            pending.changedSources.insert(signal)
            markDirty(dependents, pending)
        }
    }

    internal func invoke<Value, Input>(_ command: Command<Value, Input>, _ input: Input) throws -> Value {
        let result = try intercept(command, event: .set, argument: input) {
            let invocation = Invocation()
            defer { invocation.isSynchronous = false }
            return try command.write(CommandContext(store: self, invocation: invocation), input)
        }
        return result as! Value
    }

    private func publicWrite<Value>(_ body: () throws -> Value) throws -> Value {
        let previousSize = changed.count
        do {
            let result = try body()
            if changed.count != previousSize { try flush() }
            return result
        } catch {
            if changed.count != previousSize { try flush() }
            throw error
        }
    }

    private func pendingMutation() -> Mutation {
        if let mutation { return mutation }
        mutation = work
        return work
    }

    private func markDirty(_ dependents: [AnySignal], _ pending: Mutation) {
        var queue = dependents
        while !queue.isEmpty {
            var next: [AnySignal] = []
            for signal in queue {
                if pending.dirty.contains(signal) { continue }
                if pending.oldEpochs[signal] == nil {
                    pending.oldEpochs[signal] = records[ObjectIdentifier(signal)]?.epoch
                }
                pending.dirty.insert(signal)
                next.append(contentsOf: records[ObjectIdentifier(signal)]?.mounted?.dependents ?? [])
            }
            queue = next
        }
    }

    private func pullEvaluate(_ dependents: [AnySignal], _ pending: Mutation) throws {
        var queue = dependents
        var visited = Set<AnySignal>()
        while !queue.isEmpty {
            var next: [AnySignal] = []
            for signal in queue where visited.insert(signal).inserted {
                let current = try read(signal)
                guard let epoch = pending.oldEpochs[signal], epoch != current.epoch else { continue }
                changed.insert(signal)
                next.append(contentsOf: current.mounted?.dependents ?? [])
            }
            queue = next
        }
    }

    internal func flush() throws {
        if let pending = mutation {
            if pending.isFlushing { return }
            pending.isFlushing = true
            defer { pending.isFlushing = false }
            while !pending.changedSources.isEmpty {
                let sources = pending.changedSources.elements
                pending.changedSources.removeAll()
                for source in sources {
                    try pullEvaluate(records[ObjectIdentifier(source)]?.mounted?.dependents ?? [], pending)
                }
            }
            pending.dirty.removeAll(keepingCapacity: true)
            pending.oldEpochs.removeAll(keepingCapacity: true)
            mutation = nil
        }
        var errors: [any Error] = []
        while !changed.isEmpty {
            var callbacks = OrderedSet<Listener>()
            for signal in changed.elements {
                for listener in records[ObjectIdentifier(signal)]?.mounted?.listeners.elements ?? [] {
                    callbacks.insert(listener)
                }
            }
            changed.removeAll()
            for listener in callbacks.elements {
                do { try listener.call() } catch { errors.append(error) }
            }
        }
        if !errors.isEmpty { throw ListenerErrors(errors: errors) }
    }
}

@MainActor
public func createStore() -> Store { Store() }
