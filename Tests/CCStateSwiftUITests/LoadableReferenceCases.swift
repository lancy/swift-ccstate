import CCState
import Testing

@testable import CCStateSwiftUI

private enum PrimitiveFailure: Error { case text(String) }

@MainActor
func runLoadableReference(_ test: ReactReferenceCase) async throws {
    let store = Store()
    switch test.id {
    case "loadable.01", "loadable.06":
        let pending = Deferred<Int>()
        let signal = CCState.State(pending.task())
        let observation = connect(store, task: signal)
        #expect(observation.state == .loading)
        pending.resolve(5)
        await observation.pending?.value
        #expect(observation.loadable.data == 5)
    case "loadable.02":
        let signal = CCState.State(1)
        let observation = connect(store, signal)
        let changes = track { _ = observation.state }
        try store.set(signal, 2)
        try store.set(signal, 3)
        #expect(changes.value == 0)
        #expect(observation.loadable.data == 3)
    case "loadable.03":
        let first = Deferred<Int>()
        let signal = CCState.State(first.task())
        let observation = connect(store, task: signal)
        let ready = track { _ = observation.state }
        first.resolve(1)
        await observation.pending?.value
        #expect(ready.value == 1 && observation.state == .hasData)
        let loading = track { _ = observation.state }
        let second = Deferred<Int>()
        try store.set(signal, second.task())
        #expect(loading.value == 1 && observation.state == .loading)
        let complete = track { _ = observation.state }
        second.resolve(2)
        await observation.pending?.value
        #expect(complete.value == 1 && observation.state == .hasData)
    case "loadable.04":
        let first = Deferred<String>()
        let signal = CCState.State(first.task())
        let observation = connect(store, task: signal)
        first.resolve("foo")
        await observation.pending?.value
        #expect(observation.resolved == "foo")
        let second = Deferred<String>()
        try store.set(signal, second.task())
        #expect(observation.state == .loading)
        second.resolve("bar")
        await observation.pending?.value
    case "loadable.05", "loadable.19", "loadable.20":
        let first = Deferred<Int>()
        let second = Deferred<Int>()
        let original = first.task()
        let signal = CCState.State(original)
        let observation = connect(store, task: signal, keepLast: test.id != "loadable.05")
        let obsoleteWaiter = observation.pending
        let current = second.task()
        try store.set(signal, current)
        if test.id == "loadable.20" { first.reject(TestFailure("obsolete")) } else { first.resolve(1) }
        await obsoleteWaiter?.value
        #expect(observation.state == .loading)
        #expect(!original.isCancelled && !current.isCancelled)
        second.resolve(2)
        await observation.pending?.value
        #expect(observation.resolved == 2)
    case "loadable.07", "loadable.08", "loadable.14":
        let deferred = Deferred<Int>()
        let signal = CCState.State(deferred.task())
        let observation = connect(store, task: signal)
        let error: Error =
            test.id == "loadable.08" ? PrimitiveFailure.text("An error occurred") : TestFailure("An error occurred")
        deferred.reject(error)
        await observation.pending?.value
        #expect(observation.state == .hasError)
        if test.id == "loadable.08" {
            #expect(observation.loadable.error is PrimitiveFailure)
        } else {
            #expect(observation.loadable.error as? TestFailure === error as? TestFailure)
        }
    case "loadable.09", "loadable.10":
        let reload = CCState.State(0)
        var requests: [Deferred<Int>] = []
        let resource = computedTask { get, _ in
            _ = try get(reload)
            let deferred = Deferred<Int>()
            requests.append(deferred)
            return try await deferred.value()
        }
        let observation = connect(store, task: resource)
        if test.id == "loadable.10" { requests[0].reject(TestFailure("offline")) } else { requests[0].resolve(1) }
        await observation.pending?.value
        #expect(observation.state == (test.id == "loadable.10" ? .hasError : .hasData))
        try store.set(reload, 1)
        #expect(observation.state == .loading && requests.count == 2)
        requests[1].resolve(2)
        await observation.pending?.value
        #expect(observation.resolved == 2)
    case "loadable.11":
        let source = CCState.State(0)
        let gate = Deferred<Int>()
        var reads = 0
        let resource = computedTask { get, _ in
            reads += 1
            _ = try get(source)
            return try await gate.value()
        }
        let observation = connect(store, task: resource)
        try store.set(source, update: { $0 })
        #expect(reads == 1 && observation.state == .loading)
        gate.resolve(5)
        await observation.pending?.value
        #expect(observation.resolved == 5)
    case "loadable.12":
        let failure = Computed<Int> { _ in throw TestFailure("thrown in baseAtom") }
        let resource = computedTask { get, _ in try get(failure) }
        let observation = connect(store, task: resource)
        await observation.pending?.value
        #expect(observation.state == .hasError)
        #expect((observation.loadable.error as? TestFailure)?.message == "thrown in baseAtom")
    case "loadable.13":
        let gate = Deferred<Int>()
        let source = CCState.State(gate.task())
        var reads = 0
        let resource = computed { get in
            reads += 1
            return try get(source)
        }
        let observation = connect(store, task: resource)
        for _ in 0..<20 {
            observation.connect(ReadSource(store: store, task: resource), onCleanupError: { Issue.record("\($0)") })
            #expect(observation.state == .loading)
        }
        #expect(reads <= 3)
        gate.resolve(1)
        await observation.pending?.value
    case "loadable.15", "loadable.16", "loadable.17", "loadable.18":
        try await retainedLoadableReference(test)
    case "loadable.21":
        let source = CCState.State(0)
        let resource = computed { try $0(source) }
        let observation = connect(store, resource)
        #expect(observation.resolved == 0)
    case "loadable.22", "loadable.23", "loadable.24", "loadable.25":
        try await switchedReadReference(
            test, keepLast: test.id == "loadable.24" || test.id == "loadable.25",
            computed: test.id == "loadable.23" || test.id == "loadable.25")
    case "loadable.26":
        let gate = Deferred<Int>()
        let reload = CCState.State(0)
        let resource = computedTask { get, _ in
            _ = try get(reload)
            return try await gate.value()
        }
        let observation = connect(store, task: resource)
        var old: [Task<Void, Never>] = []
        for value in 1...2 {
            if let pending = observation.pending { old.append(pending) }
            try store.set(reload, value)
        }
        gate.reject(CancellationError())
        await observation.pending?.value
        for waiter in old { await waiter.value }
        #expect(observation.loadable.error is CancellationError)
    case "loadable.27":
        let reload = CCState.State(0)
        let gate = Deferred<Void>()
        let resource = computedTask { get, _ in
            _ = try get(reload)
            try await gate.value()
        }
        let observation = connect(store, task: resource)
        var obsolete: [Task<Void, Never>] = []
        for value in 1...3 {
            if let pending = observation.pending { obsolete.append(pending) }
            try store.set(reload, value)
        }
        gate.reject(TestFailure("handled"))
        await observation.pending?.value
        for waiter in obsolete { await waiter.value }
        #expect(observation.state == .hasError)
        #expect((observation.loadable.error as? TestFailure)?.message == "handled")
    default: Issue.record("Missing loadable reference \(test.id)")
    }
}

@MainActor
private func retainedLoadableReference(_ test: ReactReferenceCase) async throws {
    if test.id == "loadable.17" {
        let store = Store()
        let initial = Deferred<Payload<Int>>()
        let source = CCState.State(initial.task())
        let observation = connect(store, task: source, keepLast: true, equals: { $0.value == $1.value })
        initial.resolve(Payload(1))
        await observation.pending?.value
        let changes = track { _ = observation.loadable }
        let same = Deferred<Payload<Int>>()
        try store.set(source, same.task())
        same.resolve(Payload(1))
        await observation.pending?.value
        #expect(changes.value == 0)
        let next = Deferred<Payload<Int>>()
        try store.set(source, next.task())
        next.resolve(Payload(2))
        await observation.pending?.value
        #expect(changes.value == 1 && observation.resolved?.value == 2)
        return
    }
    let store = Store()
    let first = Deferred<Int>()
    let source = CCState.State(first.task())
    let observation = connect(store, task: source, keepLast: true)
    if test.id == "loadable.18" { first.reject(TestFailure("error")) } else { first.resolve(1) }
    await observation.pending?.value
    let changes = track { _ = observation.loadable }
    let second = Deferred<Int>()
    try store.set(source, second.task())
    #expect(changes.value == 0)
    if test.id == "loadable.18" { #expect(observation.state == .hasError) } else { #expect(observation.resolved == 1) }
    second.resolve(test.id == "loadable.16" ? 1 : 2)
    await observation.pending?.value
    #expect(changes.value == (test.id == "loadable.16" ? 0 : 1))
    #expect(observation.resolved == (test.id == "loadable.16" ? 1 : 2))
}

@MainActor
func switchedReadReference(_ test: ReactReferenceCase, keepLast: Bool, computed: Bool) async throws {
    let store = Store()
    let first = CCState.State("A0")
    let second = CCState.State("B0")
    let a: Signal<String> = computed ? Computed { try $0(first) } : first
    let b: Signal<String> = computed ? Computed { try $0(second) } : second
    let observation = connect(store, a, keepLast: keepLast)
    #expect(observation.resolved == "A0")
    observation.connect(
        ReadSource(store: store, signal: b), keepLast: keepLast, onCleanupError: { Issue.record("\($0)") })
    #expect(observation.resolved == "B0")
    #expect(!store.isMounted(a) && store.isMounted(b))
    try store.set(first, "A1")
    #expect(observation.resolved == "B0")
    try store.set(second, "B1")
    #expect(observation.resolved == "B1")
}
