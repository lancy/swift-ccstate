import Testing

@testable import CCState

private enum ThrownValue: Error, Equatable {
    case undefined, null, zero, falseValue, emptyString
}

@MainActor
func runValues(_ test: UpstreamCase) async throws {
    if test.id.hasPrefix("result.") {
        try runResults(test)
        return
    }
    switch test.id {
    case "basic.01":
        let first = state(0)
        let second = state(1)
        let doubled = computed { try $0(first) * 2 }
        let sum = computed { try $0(first) + $0(second) }
        let add = command { (context: CommandContext, value: Int) in
            try context.set(first, update: { $0 + value / 2 })
            try context.set(second, update: { $0 + value / 2 })
        }
        let decrement = command { try $0.set(first, update: { $0 - 1 }) }
        let store = createStore()
        #expect(first.initialValue == 0)
        #expect(try store.get(doubled) == 0)
        try store.set(add, 4)
        #expect(try store.get(sum) == 5)
        try store.set(decrement)
        #expect(try store.get(first) == 1)
    case "basic.02":
        let source = state(0)
        let store = Store()
        let value = Computed { get in
            let value = try get(source)
            if value != 0 { throw TestError() }
            return value
        }
        var calls = 0
        try store.watch(value) {
            _ = try? store.get(value)
            calls += 1
        }
        #expect(try store.get(value) == 0)
        #expect(calls == 0)
        try store.set(source, 1)
        #expect(calls == 1)
        #expect(throws: TestError.self) { try store.get(value) }
        calls = 0
        let normal = computed { try $0(source) + 1 }
        try store.watch(normal) { calls += 1 }
        #expect(try store.get(normal) == 2)
        try store.set(source, 2)
        #expect(calls == 2)
    case "basic.03", "basic.04":
        let error = TestError()
        let broken = Computed<Int> { _ in throw error }
        let derived = computed { try $0(broken) }
        let store = Store()
        if test.id == "basic.03" {
            #expect(throws: TestError.self) { try store.get(derived) }
        } else {
            var calls = 0
            try store.watch(derived) { calls += 1 }
            #expect(calls == 0)
        }
    case "distinct.01":
        let store = Store()
        let source = state(0)
        let value = computed { try $0(source) }
        var stateCalls = 0
        var computedCalls = 0
        try store.watch(source) { stateCalls += 1 }
        try store.watch(value) { computedCalls += 1 }
        try store.set(source, 0)
        #expect(stateCalls == 0 && computedCalls == 0)
    case "distinct.02":
        let store = Store()
        let source = state(Box(1))
        let value = computed { try $0(source).value }
        var reads = 0
        let child = computed { get in
            reads += 1
            return try get(value)
        }
        try store.watch(child) {}
        #expect(reads == 1)
        try store.set(source, Box(1))
        #expect(reads == 1)
    case "empty-state.01":
        let store = Store()
        let value = State<Int?>(1)
        try store.set(value, nil)
        #expect(try store.get(value) == nil)
    case "empty-state.02", "empty-state.03":
        let store = Store()
        let value = State<Int?>(nil)
        var called = false
        try store.set(
            value,
            update: { previous in
                #expect(previous == nil)
                called = true
                return 1
            })
        #expect(called)
        #expect(try store.get(value) == 1)
    case "effect.01":
        let store = Store()
        let value = state(0)
        var seen: [Int] = []
        try store.watch(value) { seen.append(try store.get(value)) }
        let inner = command { try $0.set(value, 2) }
        let outer = command { context in
            try context.set(value, 1)
            try context.set(inner)
            try context.set(value, 3)
        }
        try store.set(outer)
        #expect(seen == [3])
    case "effect.02":
        let store = Store()
        let value = state(0)
        var calls = 0
        try store.watch(value) { calls += 1 }
        let action = command { context in
            try context.set(value, 1)
            throw TestError()
        }
        #expect(throws: TestError.self) { try store.set(action) }
        #expect(calls == 1)
        #expect(try store.get(value) == 1)
    case "cache.01":
        let store = Store()
        let source = state(1)
        let unrelated = state(0)
        var evaluations = 0
        func counted(_ read: @escaping (Getter) throws -> Int) -> Computed<Int> {
            computed { get in
                evaluations += 1
                return try read(get)
            }
        }
        var left = counted { try $0(source) }
        var right = counted { try $0(source) }
        let depth = 8
        let nodeCount = 17
        for _ in 1..<depth {
            let oldLeft = left
            let oldRight = right
            left = counted { try $0(oldLeft) + $0(oldRight) }
            right = counted { try $0(oldLeft) + $0(oldRight) }
        }
        let root = counted { try $0(left) + $0(right) }
        #expect(try store.get(root) == 256)
        #expect(evaluations == nodeCount)
        #expect(store.cacheLookups <= 2 * nodeCount)
        store.cacheLookups = 0
        #expect(try store.get(root) == 256)
        #expect(store.cacheLookups == 1)
        try store.set(unrelated, 1)
        store.cacheLookups = 0
        #expect(try store.get(root) == 256)
        #expect(store.cacheLookups <= 2 * nodeCount)
        #expect(evaluations == nodeCount)
        store.cacheLookups = 0
        _ = try store.get(root)
        #expect(store.cacheLookups == 1)
        try store.set(source, 2)
        store.cacheLookups = 0
        #expect(try store.get(root) == 512)
        #expect(store.cacheLookups <= 3 * nodeCount)
        #expect(evaluations == 2 * nodeCount)
        store.cacheLookups = 0
        _ = try store.get(root)
        #expect(store.cacheLookups == 1)
    case "cache.02":
        let store = Store()
        let source = state(1)
        let shared = computed { try $0(source) }
        let first = computed { try $0(shared) + 1 }
        let second = computed { try $0(shared) + 2 }
        #expect(try store.get(first) == 2)
        #expect(try store.get(second) == 3)
        try store.set(source, 2)
        #expect(try store.get(first) == 3)
        #expect(try store.get(second) == 4)
        for root in [first, second] {
            store.cacheLookups = 0
            _ = try store.get(root)
            #expect(store.cacheLookups == 1)
        }
    default: Issue.record("Unported value case \(test.id)")
    }
}

@MainActor
private func runResults(_ test: UpstreamCase) throws {
    let index = Int(test.id.split(separator: ".")[1])!
    let mounted = index > 8
    let variant = (index - 1) % 8 + 1
    let store = Store()
    if variant <= 6 {
        let errors: [Error] = [
            TestError("offline"), ThrownValue.undefined, ThrownValue.null,
            ThrownValue.zero, ThrownValue.falseValue, ThrownValue.emptyString,
        ]
        let error = errors[variant - 1]
        let broken = state(false)
        let output = Computed<Int?> { get in
            if try get(broken) { throw error }
            return nil
        }
        let caught = computed { get in
            do {
                _ = try get(output)
                return "value:nil"
            } catch { return "error:\(String(reflecting: error))" }
        }
        let relay = computed { try $0(caught) }
        var seen: [String] = []
        if mounted { try store.watch(relay) { seen.append(try store.get(relay)) } }
        #expect(try store.get(relay) == "value:nil")
        try store.set(broken, true)
        #expect(try store.get(relay) == "error:\(String(reflecting: error))")
        try store.set(broken, false)
        #expect(try store.get(output) == nil)
        #expect(try store.get(relay) == "value:nil")
        if mounted { #expect(seen == ["error:\(String(reflecting: error))", "value:nil"]) }
    } else if variant == 7 {
        let first = TestError("first")
        let second = TestError("second")
        let reason = state(first)
        let output = Computed<Int> { get in throw try get(reason) }
        let caught = computed { get -> TestError? in
            do {
                _ = try get(output)
                return nil
            } catch { return error as? TestError }
        }
        let relay = computed { try $0(caught) }
        var calls = 0
        if mounted { try store.watch(relay) { calls += 1 } }
        #expect(try store.get(relay) === first)
        #expect(throws: TestError.self) { try store.get(output) }
        try store.set(reason, second)
        #expect(try store.get(relay) === second)
        #expect(throws: TestError.self) { try store.get(output) }
        #expect(calls == (mounted ? 1 : 0))
    } else {
        let trigger = state(0)
        let error = TestError("unchanged")
        let output = Computed<Int> { get in
            _ = try get(trigger)
            throw error
        }
        var reads = 0
        let caught = computed { get -> TestError? in
            reads += 1
            do {
                _ = try get(output)
                return nil
            } catch { return error as? TestError }
        }
        if mounted { try store.watch(caught) {} }
        #expect(try store.get(caught) === error)
        try store.set(trigger, 1)
        #expect(try store.get(caught) === error)
        #expect(reads == 1)
    }
}
