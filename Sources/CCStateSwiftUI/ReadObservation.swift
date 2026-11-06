// Subscription and generation rules adapted from ccstate-react 6.1.0 (MIT).
import CCState
import Observation

@MainActor
internal enum ReadResult<Value> {
    case value(Value)
    case task(@MainActor () async throws -> Value)
}

internal struct SignalIdentity: Hashable {
    let store: ObjectIdentifier?
    let signal: ObjectIdentifier
    let isTask: Bool
}

@MainActor
internal struct ReadSource<Value> {
    let identity: SignalIdentity
    let read: () throws -> ReadResult<Value>
    let subscribe: (@escaping () -> Void) throws -> Subscription

    init(store: Store?, signal: Signal<Value>) {
        identity = SignalIdentity(
            store: store.map(ObjectIdentifier.init), signal: ObjectIdentifier(signal), isTask: false)
        read = {
            guard let store else { throw StoreObservationError.missingStore }
            return .value(try store.get(signal))
        }
        subscribe = { listener in
            guard let store else { throw StoreObservationError.missingStore }
            return try store.watch(signal, listener)
        }
    }

    init<Failure: Error>(store: Store?, task signal: Signal<Task<Value, Failure>>) where Value: Sendable {
        identity = SignalIdentity(
            store: store.map(ObjectIdentifier.init), signal: ObjectIdentifier(signal), isTask: true)
        read = {
            guard let store else { throw StoreObservationError.missingStore }
            let task = try store.get(signal)
            return .task { try await task.value }
        }
        subscribe = { listener in
            guard let store else { throw StoreObservationError.missingStore }
            return try store.watch(signal, listener)
        }
    }
}

@MainActor
@Observable
internal final class ReadObservation<Value> {
    private var resultRevision = 0
    private var dataRevision = 0
    private var stateRevision = 0
    @ObservationIgnored private var snapshot: Loadable<Value> = .loading
    @ObservationIgnored private var latestOutcome: Loadable<Value>?
    @ObservationIgnored private var source: ReadSource<Value>?
    @ObservationIgnored private var subscription: Subscription?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var isConnecting = false
    @ObservationIgnored private var keepLast = false
    @ObservationIgnored private var equals: (Value, Value) -> Bool = defaultEquality
    @ObservationIgnored private var onCleanupError: (any Error) -> Void = { _ in }
    @ObservationIgnored internal private(set) var pending: Task<Void, Never>?

    var loadable: Loadable<Value> {
        _ = resultRevision
        return snapshot
    }
    var resolved: Value? {
        _ = dataRevision
        return snapshot.data
    }
    var state: LoadableState {
        _ = stateRevision
        return snapshot.state
    }

    /// Called by DynamicProperty.update before the owning view reads a snapshot.
    /// Configuration writes do not invalidate SwiftUI while it is updating views.
    func connect(
        _ next: ReadSource<Value>, keepLast: Bool = false,
        equals: @escaping (Value, Value) -> Bool = defaultEquality,
        onCleanupError: @escaping (any Error) -> Void
    ) {
        isConnecting = true
        defer { isConnecting = false }
        self.equals = equals
        self.onCleanupError = onCleanupError
        let sameSource = source?.identity == next.identity
        let samePolicy = self.keepLast == keepLast
        self.keepLast = keepLast
        if sameSource, samePolicy, subscription != nil {
            source = next
            if !next.identity.isTask { refresh() } else if let latestOutcome { publish(latestOutcome) }
            return
        }
        disconnect()
        source = next
        do {
            subscription = try next.subscribe { [weak self] in self?.refresh() }
            // Core watch does not notify initially. Read after subscribing to
            // catch values changed between view construction and registration.
            refresh()
        } catch {
            latestOutcome = .hasError(error)
            publish(.hasError(error))
        }
    }

    private func refresh() {
        guard let source else { return }
        generation += 1
        let version = generation
        pending?.cancel()
        pending = nil
        latestOutcome = nil
        do {
            switch try source.read() {
            case .value(let value):
                latestOutcome = .hasData(value)
                publish(.hasData(value))
            case .task(let resolve):
                if !keepLast { publish(.loading) }
                pending = Task.immediate { @MainActor [weak self] in
                    let result: Loadable<Value>
                    do { result = .hasData(try await resolve()) } catch { result = .hasError(error) }
                    guard !Task.isCancelled, let self, self.source != nil, self.generation == version else { return }
                    self.latestOutcome = result
                    self.publish(result)
                }
            }
        } catch {
            latestOutcome = .hasError(error)
            publish(.hasError(error))
        }
    }

    private func sameData(_ lhs: Loadable<Value>, _ rhs: Loadable<Value>) -> Bool {
        switch (lhs, rhs) {
        case (.hasData(let a), .hasData(let b)): equals(a, b)
        case (.hasData, _), (_, .hasData): false
        default: true
        }
    }

    private func publish(_ next: Loadable<Value>) {
        let dataUnchanged = sameData(snapshot, next)
        if keepLast || source?.identity.isTask == false,
            case .hasData = snapshot, case .hasData = next, dataUnchanged
        {
            return
        }
        let oldState = snapshot.state
        snapshot = next
        if !isConnecting {
            resultRevision += 1
            if !dataUnchanged { dataRevision += 1 }
            if oldState != next.state { stateRevision += 1 }
        }
    }

    func disconnect() {
        generation += 1
        pending?.cancel()
        pending = nil
        latestOutcome = nil
        source = nil
        let old = subscription
        subscription = nil
        do { try old?.cancel() } catch { onCleanupError(error) }
    }

    isolated deinit { disconnect() }
}
