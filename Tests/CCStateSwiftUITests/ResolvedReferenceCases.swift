import CCState
import Testing

@testable import CCStateSwiftUI

@MainActor
func runResolvedReference(_ test: ReactReferenceCase) async throws {
    let store = Store()
    switch test.id {
    case "resolved.01", "resolved.02":
        let deferred = Deferred<String>()
        let source = CCState.State(deferred.task())
        let observation = connect(store, task: source)
        #expect(observation.resolved == nil)
        deferred.resolve("foo")
        await observation.pending?.value
        #expect(observation.resolved == "foo")
    case "resolved.03":
        let first = Deferred<Int>()
        let source = CCState.State(first.task())
        let observation = connect(store, task: source, keepLast: true)
        first.resolve(1)
        await observation.pending?.value
        let changes = track { _ = observation.resolved }
        let next = Deferred<Int>()
        try store.set(source, next.task())
        #expect(observation.resolved == 1 && changes.value == 0)
        next.resolve(2)
        await observation.pending?.value
        #expect(observation.resolved == 2 && changes.value == 1)
    case "resolved.04":
        let first = Deferred<Bool>()
        let source = CCState.State(first.task())
        let observation = connect(store, task: source, keepLast: true)
        first.resolve(false)
        await observation.pending?.value
        let changes = track { _ = observation.resolved }
        let next = Deferred<Bool>()
        try store.set(source, next.task())
        next.resolve(false)
        await observation.pending?.value
        #expect(observation.resolved == false && changes.value == 0)
    case "resolved.05":
        let first = Deferred<Payload<Int>>()
        let source = CCState.State(first.task())
        let observation = connect(store, task: source, keepLast: true, equals: { $0.value == $1.value })
        first.resolve(Payload(1))
        await observation.pending?.value
        let changes = track { _ = observation.resolved }
        let same = Deferred<Payload<Int>>()
        try store.set(source, same.task())
        same.resolve(Payload(1))
        await observation.pending?.value
        #expect(changes.value == 0 && observation.resolved?.value == 1)
        let next = Deferred<Payload<Int>>()
        try store.set(source, next.task())
        next.resolve(Payload(2))
        await observation.pending?.value
        #expect(changes.value == 1 && observation.resolved?.value == 2)
    case "resolved.06":
        let source = CCState.State(0)
        let derived = computed { try $0(source) }
        let observation = connect(store, derived)
        #expect(observation.resolved == 0)
    case "resolved.07", "resolved.08", "resolved.09", "resolved.10":
        try await switchedReadReference(
            test, keepLast: test.id == "resolved.09" || test.id == "resolved.10",
            computed: test.id == "resolved.08" || test.id == "resolved.10")
    default: Issue.record("Missing resolved reference \(test.id)")
    }
}

@MainActor
func runMigrationReference(_ test: ReactReferenceCase) async throws {
    switch test.id {
    case "readable-watch-migration.01":
        let source = CCState.State(0)
        var wrote = false
        var interceptor = StoreInterceptor()
        let owner = Payload<Store?>(nil)
        interceptor.mount = { target in
            if target === source, !wrote {
                wrote = true
                try! owner.value!.set(source, 1)
            }
        }
        let store = Store(interceptor: interceptor)
        owner.value = store
        #expect(try store.get(source) == 0)
        let first = connect(store, source)
        let second = connect(store, source)
        #expect(first.resolved == 1 && second.resolved == 1)
        first.disconnect()
        second.disconnect()
        owner.value = nil
    case "readable-watch-migration.02":
        let store = Store()
        let broken = CCState.State(true)
        let failure = TestFailure("sync failure")
        let resource = Computed { get in
            if try get(broken) { throw failure }
            return 42
        }
        let observation = connect(store, resource)
        #expect(observation.state == .hasError && observation.loadable.error as? TestFailure === failure)
        try store.set(broken, false)
        #expect(observation.resolved == 42)
        try store.set(broken, true)
        #expect(observation.state == .hasError)
    case "readable-watch-migration.03":
        let first = Deferred<Int>()
        let second = Deferred<Int>()
        let source = CCState.State(first.task())
        let a = Store()
        let b = Store()
        try b.set(source, second.task())
        let observation = connect(a, task: source)
        let obsolete = observation.pending
        observation.connect(ReadSource(store: b, task: source), onCleanupError: { Issue.record("\($0)") })
        #expect(!a.isMounted(source) && b.isMounted(source))
        second.resolve(2)
        await observation.pending?.value
        #expect(observation.resolved == 2)
        let changes = track { _ = observation.loadable }
        first.reject(TestFailure("obsolete"))
        await obsolete?.value
        #expect(observation.resolved == 2 && changes.value == 0)
    case "readable-watch-migration.04":
        let store = Store()
        let initial = CCState.State(1)
        let deferred = Deferred<Int>()
        let source = CCState.State(deferred.task())
        let equalCalls = ChangeCount()
        let equals: (Int, Int) -> Bool = { a, b in
            equalCalls.increment()
            return a == b
        }
        let observation = connect(store, initial, keepLast: true, equals: equals)
        observation.connect(
            ReadSource(store: store, task: source), keepLast: true, equals: equals,
            onCleanupError: { Issue.record("\($0)") })
        #expect(observation.resolved == 1)
        let count = equalCalls.value
        let pending = observation.pending
        observation.disconnect()
        deferred.resolve(2)
        await pending?.value
        #expect(equalCalls.value == count && !store.isMounted(source))
    case "readable-watch-migration.05":
        let store = Store()
        let deferred = Deferred<Int>()
        let shared = deferred.task()
        let first = CCState.State(shared)
        let second = CCState.State(shared)
        let equalCalls = ChangeCount()
        let equals: (Int, Int) -> Bool = { a, b in
            equalCalls.increment()
            return a == b
        }
        let observation = connect(store, task: first, keepLast: true, equals: equals)
        let obsolete = observation.pending
        observation.connect(
            ReadSource(store: store, task: second), keepLast: true, equals: equals,
            onCleanupError: { Issue.record("\($0)") })
        let changes = track { _ = observation.loadable }
        deferred.resolve(7)
        await observation.pending?.value
        await obsolete?.value
        #expect(observation.resolved == 7 && changes.value == 1)
        #expect(equalCalls.value == 0)
    default: Issue.record("Missing migration reference \(test.id)")
    }
}

@MainActor
func runMemoryReference(_ test: ReactReferenceCase) async throws {
    let store = Store()
    switch test.id {
    case "memory.01":
        var source: CCState.State<Payload<String>>? = CCState.State(Payload("bar"))
        weak let payload = try store.get(source!)
        var observation: ReadObservation<Payload<String>>? = connect(store, source!)
        weak let lease = observation
        #expect(observation?.resolved?.value == "bar")
        source = nil
        observation = nil
        #expect(lease == nil && payload == nil)
    case "memory.02":
        let gate = Deferred<String>()
        var source: CCState.State<Task<String, Error>>? = CCState.State(gate.task())
        weak let signal = source
        var observation: ReadObservation<String>? = connect(store, task: source!, keepLast: true)
        gate.resolve("bar")
        await observation?.pending?.value
        #expect(observation?.resolved == "bar")
        weak let lease = observation
        source = nil
        observation = nil
        #expect(lease == nil && signal == nil)
    default: Issue.record("Missing memory reference \(test.id)")
    }
    withExtendedLifetime(store) {}
}
