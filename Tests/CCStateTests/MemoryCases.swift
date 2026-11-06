import Testing

@testable import CCState

@MainActor
func runMemory(_ test: UpstreamCase) async throws {
    if test.id.hasPrefix("dynamic-dependency-memory.") {
        try await dynamicMemory(test)
        return
    }
    let store = Store()
    switch test.id {
    case "memory.01":
        var source: State<Box<Int>>? = state(Box(1))
        weak let payload = try store.get(source!)
        source = nil
        #expect(payload == nil)
    case "memory.02":
        var source: State<Box<Int>>? = state(Box(1))
        var derived: Computed<Box<Box<Int>?>>? = computed { get in Box(try source.map { try get($0) }) }
        weak let basePayload = try store.get(source!)
        weak let derivedPayload = try store.get(derived!)
        source = nil
        derived = nil
        #expect(basePayload == nil)
        #expect(derivedPayload == nil)
    case "memory.03", "memory.08", "memory.09":
        let source = state(Box(1))
        var derived: Computed<Box<Box<Int>>>? = computed { get in Box(try get(source)) }
        weak let payload = try store.get(derived!)
        if test.id == "memory.08" {
            let stop = try store.watch(source) {}
            try stop.cancel()
        }
        if test.id == "memory.09" {
            let stop = try store.watch(derived!) {}
            try stop.cancel()
        }
        derived = nil
        #expect(payload == nil)
        #expect(try store.get(source).value == 1)
    case "memory.04":
        let source = state(Box(1))
        var derived: Computed<Box<Int>>? = computed { try $0(source) }
        weak let signal = derived
        _ = try store.get(derived!)
        derived = nil
        #expect(signal == nil)
    case "memory.05":
        func subscribe() throws -> (Subscription, () -> Bool) {
            let payload = Box(1)
            let source = state(Box(2))
            weak let weakPayload = payload
            let stop = try store.watch(source) { _ = payload.value }
            return (stop, { weakPayload == nil })
        }
        let (stop, released) = try subscribe()
        try stop.cancel()
        try stop.cancel()
        #expect(released())
        withExtendedLifetime(stop) {}
    case "memory.06":
        var source: State<Box<Int>>? = state(Box(1))
        weak let payload = try store.get(source!)
        let stop = try store.watch(source!) {}
        try stop.cancel()
        source = nil
        #expect(payload == nil)
        withExtendedLifetime(stop) {}
    case "memory.07":
        var source: State<Box<Int>>? = state(Box(1))
        var derived: Computed<Box<Box<Int>?>>? = computed { get in Box(try source.map { try get($0) }) }
        weak let first = try store.get(source!)
        weak let second = try store.get(derived!)
        let stop = try store.watch(source!) {}
        try stop.cancel()
        source = nil
        derived = nil
        #expect(first == nil && second == nil)
    default: Issue.record("Unported memory case \(test.id)")
    }
    withExtendedLifetime(store) {}
}

@MainActor
private func dynamicMemory(_ test: UpstreamCase) async throws {
    let index = Int(test.id.split(separator: ".")[1])!
    var mounts = 0
    var interceptor = StoreInterceptor()
    interceptor.mount = { if $0.debugLabel == "obsolete" { mounts += 1 } }
    interceptor.unmount = { if $0.debugLabel == "obsolete" { mounts -= 1 } }
    let store = Store(interceptor: interceptor)
    let branch = state(false)
    let old = Box<State<Box<Int>>?>(state(Box(1), debugLabel: "obsolete"))
    weak let oldSignal = old.value
    weak let oldPayload = try store.get(old.value!)
    let current = state(Box(2))
    let gate = Gate<Void>()
    var reads = 0
    if index == 1 {
        let root = computed { get in
            reads += 1
            return try get(branch) ? get(current).value : get(old.value!).value
        }
        let stop = try store.watch(root) {}
        #expect(try store.get(root) == 1)
        try store.set(branch, true)
        #expect(try store.get(root) == 2)
        let count = reads
        try store.set(old.value!, Box(99))
        #expect(reads == count)
        old.value = nil
        #expect(oldSignal == nil && oldPayload == nil)
        try store.set(current, Box(3))
        #expect(reads == count + 1)
        #expect(try store.get(root) == 3)
        try stop.cancel()
    } else {
        let beforeAwait = index == 2 || index == 4
        let obsoleteFinishesLast = index >= 4
        let root = computedTask { get, _ in
            reads += 1
            let selected = try get(branch)
            if selected { return try get(current).value }
            if beforeAwait {
                let value = try get(old.value!).value
                try await gate.wait()
                return value
            }
            try await gate.wait()
            return try get(old.value!).value
        }
        let stop = try store.watch(root) {}
        let first = try store.get(root)
        if !obsoleteFinishesLast {
            gate.resolve(())
            #expect(try await first.value == 1)
        }
        try store.set(branch, true)
        let latest = try store.get(root)
        #expect(try await latest.value == 2)
        if obsoleteFinishesLast {
            gate.resolve(())
            #expect(try await first.value == 1)
        }
        #expect(mounts == 0)
        #expect(try store.get(root) == latest)
        let count = reads
        try store.set(old.value!, Box(99))
        #expect(reads == count)
        old.value = nil
        #expect(oldSignal == nil && oldPayload == nil)
        try store.set(current, Box(3))
        #expect(reads == count + 1)
        #expect(try await store.get(root).value == 3)
        try stop.cancel()
    }
}

@Suite
@MainActor
struct SwiftLifetimeTests {
    @Test func releasingStoreReleasesItsValuesWhileSignalsRemain() throws {
        let source = State<Box<Int>?>(nil)
        var store: Store? = Store()
        try store!.set(source, Box(1))
        weak let payload = try store!.get(source)
        store = nil
        #expect(payload == nil)
        #expect(source.cleanups.isEmpty)
    }

    @Test func manyStoresDoNotAccumulateCleanupClosures() throws {
        let source = state(0)
        for _ in 0..<100 {
            let store = Store()
            _ = try store.get(source)
        }
        #expect(source.cleanups.isEmpty)
    }

    @Test func functionValuedComputedDoesNotKeepItsStoreAlive() throws {
        let source = state(1)
        let function = computed { get in { try get(source) } }
        var store: Store? = Store()
        weak let owner = store
        _ = try store!.get(function)
        store = nil
        #expect(owner == nil)
        #expect(function.cleanups.isEmpty && source.cleanups.isEmpty)
    }

    @Test func retainedGetterReportsReleasedOwner() throws {
        let source = state(1)
        let function = computed { get in { try get(source) } }
        var store: Store? = Store()
        let read = try store!.get(function)
        #expect(try read() == 1)
        store = nil
        #expect(throws: StoreError.storeReleased) { try read() }
    }
}
