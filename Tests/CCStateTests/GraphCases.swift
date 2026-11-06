import Testing

@testable import CCState

@MainActor
func runGraphs(_ test: UpstreamCase) async throws {
    if test.id.hasPrefix("store.") {
        try await runStoreCases(test)
        return
    }
    if test.id.hasPrefix("ccstate.") {
        try await runCoreCases(test)
        return
    }
    let store = Store()
    switch test.id {
    case "glitch.01", "glitch.02":
        let source = state(0)
        let zero: Computed<Int>
        let one: Computed<Int>
        zero = computed { try $0(source) }
        one = computed { try $0(zero) + 1 }
        var seen: [Bool] = []
        let root = computed { get in
            let result: Bool
            if test.id == "glitch.01" {
                let n = try get(zero)
                result = try get(one) > n
            } else {
                result = try get(one) > get(zero)
            }
            seen.append(result)
            return result
        }
        try store.watch(root) {}
        #expect(try store.get(root))
        seen.removeAll()
        try store.set(source, 1)
        #expect(seen == [true])
    case "glitch.03", "glitch.04", "glitch.05", "glitch.06", "glitch.07":
        var calls = 0
        let (base, top) = asymmetricDiamond(test.id) { calls += 1 }
        let stop = try store.watch(top) {}
        calls = 0
        try store.set(base, update: { $0 + 1 })
        if test.id == "glitch.07" { #expect(calls == 99) }
        #expect(try store.get(top) == 2)
        try stop.cancel()
    case "propagation.01", "propagation.02", "propagation.03":
        let index = Int(test.id.split(separator: ".")[1])!
        let depth = [4, 8, 12][index - 1]
        let source = state(1)
        var calls = 0
        func counted(_ read: @escaping (Getter) throws -> Int) -> Computed<Int> {
            computed { get in
                calls += 1
                return try read(get)
            }
        }
        var left = counted { try $0(source) }
        var right = counted { try $0(source) }
        for _ in 1..<depth {
            let a = left
            let b = right
            left = counted { try $0(a) + $0(b) }
            right = counted { try $0(a) + $0(b) }
        }
        let root = counted { try $0(left) + $0(right) }
        let count = 2 * depth + 1
        var seen: [Int] = []
        let stop = try store.watch(root) { seen.append(try store.get(root)) }
        #expect(try store.get(root) == 1 << depth)
        #expect(calls == count && seen.isEmpty)
        for value in 2...3 {
            store.cacheLookups = 0
            store.recordLookups = 0
            calls = 0
            try store.set(source, value)
            #expect(seen == (2...value).map { $0 * (1 << depth) })
            #expect(calls == count)
            #expect(store.cacheLookups <= 6 * (count + 1))
            #expect(store.recordLookups <= 16 * (count + 1))
        }
        try stop.cancel()
    case "propagation.04":
        let source = state(1)
        let first = computed { try $0(source) * 2 }
        let second = computed { try $0(first) * 3 }
        let third = computed { try $0(second) * 5 }
        var calls = 0
        var seen: [Int] = []
        let root = computed { get in
            calls += 1
            return try get(source) + get(third)
        }
        try store.watch(root) { seen.append(try store.get(root)) }
        calls = 0
        try store.set(source, 2)
        #expect(try store.get(root) == 62)
        #expect(seen == [62] && calls == 1)
    case "propagation.05":
        let branch = state(true)
        let left = state(1)
        let right = state(1)
        let selected = computed { get in try get(branch) ? get(left) : get(right) }
        let double = computed { try $0(selected) * 2 }
        var calls = 0
        var seen: [Int] = []
        let root = computed { get in
            calls += 1
            return try get(selected) + get(double)
        }
        try store.watch(root) { seen.append(try store.get(root)) }
        calls = 0
        try store.set(branch, false)
        try store.set(left, 2)
        #expect(try store.get(root) == 3)
        #expect(seen.isEmpty && calls == 0)
        try store.set(right, 2)
        #expect(seen == [6] && calls == 1)
        try store.set(branch, true)
        try store.set(right, 3)
        #expect(seen == [6] && calls == 1)
        try store.set(left, 3)
        #expect(seen == [6, 9] && calls == 2)
    default: Issue.record("Unported graph case \(test.id)")
    }
}

@MainActor
private func asymmetricDiamond(_ id: String, trace: @escaping () -> Void) -> (State<Int>, Signal<Int>) {
    let base = state(0)
    var current: Signal<Int> = computed { get in
        trace()
        return try get(base)
    }
    let first = current
    var top: Signal<Int> = computed { get in
        trace()
        return try get(first) + 1
    }
    var seed: UInt64 = 0xCC57A7E
    for layer in 4...100 {
        let oldCurrent = current
        let oldTop = top
        let next = computed { try $0(oldCurrent) }
        seed = seed &* 6_364_136_223_846_793_005 &+ 1
        let left =
            id == "glitch.03" || (id == "glitch.05" && layer % 7 == 0)
            || ((id == "glitch.06" || id == "glitch.07") && seed >> 63 == 1)
        top = Computed { get in
            trace()
            if left {
                if try get(oldTop) > get(next) { return try get(oldTop) }
            } else {
                if try get(next) <= get(oldTop) { return try get(oldTop) }
            }
            throw TestError("Glitch in diamond")
        }
        current = next
    }
    return (base, top)
}

@MainActor
private func runCoreCases(_ test: UpstreamCase) async throws {
    let store = Store()
    let base = state(1)
    switch test.id {
    case "ccstate.01":
        #expect(try store.get(base) == 1)
        try store.set(base, 2)
        #expect(try store.get(base) == 2)
        #expect(try Store().get(base) == 1)
    case "ccstate.02", "ccstate.03":
        let doubled = computed { try $0(base) * 2 }
        // The negative compilation fixture verifies that doubled cannot be set.
        #expect(try store.get(doubled) == 2)
    case "ccstate.04":
        let gate = Gate<Void>()
        let root = computedTask { get, _ in
            try await gate.wait()
            return try get(base) * 2
        }
        let task = try store.get(root)
        gate.resolve(())
        #expect(try await task.value == 2)
    case "ccstate.05":
        let source = state("foo")
        let gate = Gate<Void>()
        let twice = computedTask { get, _ in
            let value = try get(source)
            try await gate.wait()
            return value + value
        }
        let root = computedTask { get, _ in
            let value = try get(source)
            return try await value + get(twice).value
        }
        let old = try store.get(root)
        try store.set(source, "bar")
        let latest = try store.get(root)
        gate.resolve(())
        #expect(try await old.value == "foofoofoo")
        #expect(try await latest.value == "barbarbar")
    case "ccstate.06":
        let doubled = state(0)
        let action = command { (context: CommandContext, value: Int) in
            try context.set(base, value)
            try context.set(doubled, context.get(base) * 2)
        }
        try store.set(action, 2)
        #expect(try store.get(base) == 2 && store.get(doubled) == 4)
    case "ccstate.07", "ccstate.08", "ccstate.10":
        var calls = 0
        let derived = computed { try $0(base) * 2 }
        let root: Signal<Int> = test.id == "ccstate.10" ? derived : base
        try store.watch(root) { calls += 1 }
        #expect(calls == 0)
        if test.id == "ccstate.08" {
            try store.set(
                command { context in
                    for value in 2...4 { try context.set(base, value) }
                })
            #expect(try store.get(base) == 4)
        } else {
            try store.set(base, 2)
        }
        #expect(calls == 1)
        if test.id == "ccstate.10" { #expect(try store.get(derived) == 4) }
    case "ccstate.09":
        let second = state(2)
        let root = computed { try [$0(base), $0(second)] }
        var calls = 0
        try store.watch(root) { calls += 1 }
        try store.set(base, update: { $0 + 1 })
        try store.set(second, update: { $0 + 1 })
        #expect(calls == 2)
    case "ccstate.11":
        let derived = computed { try $0(base) }
        #expect(store.getReadDependencies(derived).children.isEmpty)
        _ = try store.get(derived)
        #expect(store.getReadDependencies(derived).children.map(\.signal) == [base])
    case "ccstate.12":
        let source = state(Box((a: 1, b: 0)))
        let derived = computed { get in
            let box = try get(source)
            box.value.b = 1
            return box
        }
        let old = try store.get(derived)
        try store.set(source, Box((a: 2, b: 0)))
        #expect(old.value.a == 1 && old.value.b == 1)
        old.value.b = 2
        #expect(try store.get(derived).value.a == 2 && store.get(derived).value.b == 1)
    case "ccstate.13":
        let branch = state(0)
        let left = state(0)
        let right = state(0)
        var leftReads = 0
        var rightReads = 0
        let root = computed { get in
            if try get(branch) == 0 {
                leftReads += 1
                return try get(left)
            }
            rightReads += 1
            return try get(right)
        }
        #expect(try store.get(root) == 0)
        try store.set(right, 1)
        #expect(rightReads == 0)
        _ = try store.get(root)
        #expect(rightReads == 0)
        try store.set(left, 100)
        _ = try store.get(root)
        #expect(rightReads == 0)
        leftReads = 0
        try store.set(branch, 1)
        #expect(leftReads == 0 && rightReads == 0)
        #expect(try store.get(root) == 1)
        #expect(leftReads == 0 && rightReads == 1)
    case "ccstate.14":
        let branch = state(true)
        let refresh = state(0)
        let gate = Gate<Void>()
        let root = computedTask { get, _ in
            if try get(branch) {
                try await gate.wait()
                _ = try get(refresh)
                return "A"
            }
            return "B"
        }
        var calls = 0
        try store.watch(root) { calls += 1 }
        let first = try store.get(root)
        gate.resolve(())
        #expect(try await first.value == "A")
        try store.set(branch, false)
        #expect(try await store.get(root).value == "B")
        #expect(calls == 1)
        try store.set(refresh, 1)
        #expect(calls == 1)
    case "ccstate.15":
        var reads = 0
        let root = computed { get in
            reads += 1
            return try get(base) * 2
        }
        _ = try store.get(root)
        _ = try store.get(root)
        #expect(reads == 1)
    case "ccstate.16":
        let last = State<Task<String, Error>?>(nil)
        let result = computed { try $0(last) }
        let inner = asyncCommand { (_: CommandContext, _: Void) in "ok" }
        let setup = command { context in
            let task = try context.set(inner)
            try context.set(last, task)
            return task
        }
        #expect(try store.get(result) == nil)
        let task = try store.set(setup)
        #expect(try store.get(result) == task)
        #expect(try await task.value == "ok")
    case "ccstate.17":
        let step = state(0)
        let generator = command { context in
            var index = 0
            return AnyIterator<Int> {
                guard index < 3 else { return nil }
                index += 1
                try! context.set(step, index)
                return index
            }
        }
        let iterator = try store.set(generator)
        for index in 1...3 {
            #expect(iterator.next() == index)
            #expect(try store.get(step) == index)
        }
    case "ccstate.18":
        let source = state(Box((id: 1, node: 2)))
        let id = computed { try $0(source).value.id }
        let node = computed { try $0(source).value.node }
        var reads = 0
        let id2 = computed { get in
            reads += 1
            return try get(id)
        }
        let root = computed { try $0(id2) + $0(node) }
        try store.watch(root) {}
        reads = 0
        try store.set(source, Box((id: 1, node: 3)))
        #expect(reads == 0)
    default: Issue.record("Unported core case \(test.id)")
    }
}
