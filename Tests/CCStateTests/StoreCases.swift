import Testing

@testable import CCState

@MainActor
func runStoreCases(_ test: UpstreamCase) async throws {
    let store = Store()
    let source = state(0)
    var calls = 0
    let doubled = computed { try $0(source) * 2 }
    switch test.id {
    case "store.01":
        var second = 0
        try store.watch(source) { calls += 1 }
        try store.watch(source) { second += 1 }
        #expect(calls == 0 && second == 0)
        try store.set(source, 1)
        #expect(calls == 1 && second == 1)
    case "store.02", "store.03":
        let root: Signal<Int> = test.id == "store.02" ? source : computed { try $0(source) * 0 }
        try store.watch(root) { calls += 1 }
        try store.set(source, test.id == "store.02" ? 0 : 1)
        #expect(calls == 0)
    case "store.04", "store.05", "store.26":
        let root: Signal<Int> = test.id == "store.05" ? doubled : source
        let stop = try store.watch(root) { calls += 1 }
        if test.id == "store.04" {
            try store.set(source, 1)
            #expect(calls == 1)
            calls = 0
        }
        try stop.cancel()
        try store.set(source, 2)
        #expect(calls == 0)
        #expect(!store.isMounted(source))
    case "store.06":
        var gates: [Gate<Void>] = []
        let root = computedTask { get, _ in
            let n = try get(source)
            let gate = Gate<Void>()
            gates.append(gate)
            try await gate.wait()
            return n
        }
        let first = try store.get(root)
        try store.set(source, 1)
        for gate in gates { gate.resolve(()) }
        #expect(try await first.value == 0)
        let second = try store.get(root)
        for gate in gates { gate.resolve(()) }
        #expect(try await second.value == 1)
    case "store.07":
        let initial = Task.immediate { 0 }
        let gate = Gate<Int>()
        let pending = Task.immediate { @MainActor in try await gate.wait() }
        let value = State<Task<Int, Error>>(Task.immediate { await initial.value })
        try store.set(value, pending)
        #expect(try store.get(value) == pending)
        let current: Task<Int, Error> = Task.immediate { 1 }
        try store.set(value, current)
        #expect(try await store.get(value).value == 1)
        gate.resolve(0)
        _ = try await pending.value
    case "store.08":
        let gate = Box(Gate<Void>())
        let delayed = computedTask { get, _ in
            try await gate.value.wait()
            return try get(source)
        }
        let derived = computedTask { get, _ in try await get(delayed).value }
        var last = try store.get(derived)
        let stop = try store.watch(derived) { last = try store.get(derived) }
        for n in 1...3 {
            if n > 1 { gate.value = Gate<Void>() }
            try store.set(source, n)
            gate.value.resolve(())
            #expect(try await last.value == n)
        }
        try stop.cancel()
    case "store.09":
        let task = Task.immediate { 0 }
        let value = state(Task.immediate { 0 })
        try store.set(value, task)
        var reads = 0
        var stateCalls = 0
        let derived = computed { get in
            reads += 1
            return try get(value)
        }
        let a = try store.watch(value) { stateCalls += 1 }
        let b = try store.watch(derived) { calls += 1 }
        #expect(reads == 1 && stateCalls == 0 && calls == 0)
        _ = try store.get(value)
        _ = try store.get(derived)
        #expect(reads == 1)
        reads = 0
        try store.set(value, task)
        try store.set(value, task)
        #expect(reads == 0 && stateCalls == 0 && calls == 0)
        try a.cancel()
        try b.cancel()
    case "store.10":
        let value = state(1)
        let double: Computed<Int>
        let sum: Computed<Int>
        let mirror: Computed<Int>
        double = computed { try $0(value) * 2 }
        sum = computed { try $0(value) + $0(double) }
        mirror = computed { try $0(double) }
        try store.watch(sum) {}
        try store.watch(mirror) { calls += 1 }
        #expect(try store.get(mirror) == 2)
        try store.set(value, 2)
        #expect(try store.get(mirror) == 4)
        #expect(calls == 1)
    case "store.11":
        let value = state(1)
        let first = computed { try $0(value) * 2 }
        let second = computed { try $0(value) * 0 }
        let root = computed { try $0(first) + $0(second) }
        try store.watch(first) {}
        try store.watch(root) { calls += 1 }
        #expect(try store.get(root) == 2 && calls == 0)
        try store.set(value, 2)
        #expect(try calls == 1 && store.get(root) == 4)
    case "store.12":
        let value = state(Box(1))
        let count = computed { try $0(value).value }
        var reads = 0
        var furtherReads = 0
        let derived = computed { get in
            reads += 1
            return try get(count)
        }
        let further = computed { get in
            furtherReads += 1
            _ = try get(value)
            return try get(derived)
        }
        try store.watch(further) { calls += 1 }
        #expect(try store.get(derived) == 1 && store.get(further) == 1)
        #expect(reads == 1 && furtherReads == 1 && calls == 0)
        try store.set(value, Box(1))
        #expect(calls == 0)
    case "store.13":
        let value = state(1)
        var aReads = 0
        var bReads = 0
        let a = computed { get in
            aReads += 1
            return try get(value)
        }
        let b = computed { get in
            bReads += 1
            return try get(value)
        }
        #expect(try store.get(a) == 1 && store.get(b) == 1)
        try store.watch(b) {}
        try store.set(value, 2)
        #expect(aReads == 1 && bReads == 2)
    case "store.14":
        let a = state(false)
        let b = state(false)
        let c = computed { try $0(a) && $0(b) }
        let action = command { (context: CommandContext, value: Bool) in
            try context.set(a, value)
            try context.set(b, value)
        }
        try store.watch(a) {}
        try store.watch(b) {}
        try store.watch(c) {}
        try store.set(action, true)
        #expect(try store.get(c))
    case "store.15":
        let root = computed { try $0(source) }
        try store.watch(root) {}
        let action = command { (context: CommandContext, value: Int) in
            try context.set(source, value)
            #expect(try context.get(root) == value)
        }
        try store.set(action, 2)
        #expect(try store.get(root) == 2)
    case "store.16":
        let value = state(1)
        let zero = computed { try $0(value) * 0 }
        let derived = computed { get in
            calls += 1
            return try get(zero)
        }
        #expect(try store.get(derived) == 0)
        try store.set(value, 2)
        #expect(try store.get(derived) == 0)
        #expect(calls == 1)
    case "store.17":
        let value = state("initial")
        let gate = Gate<Void>()
        var seen: [String] = []
        let stop = try store.watch(value) { seen.append(try store.get(value)) }
        let indirect = command { try $0.set(value, "next") }
        let action = asyncCommand { (context: CommandContext, _: Void) in
            try await gate.wait()
            try context.set(indirect)
        }
        let pending = try store.set(action)
        gate.resolve(())
        try await pending.value
        #expect(seen == ["next"])
        try stop.cancel()
    case "store.18", "store.19":
        let value = state(1)
        let gate = Gate<Void>()
        let root = computedTask { get, _ in
            if test.id == "store.19" {
                let n = try get(value)
                try await gate.wait()
                return n
            }
            try await gate.wait()
            return try get(value)
        }
        let first = try store.get(root)
        try store.set(value, 2)
        gate.resolve(())
        let second = try store.get(root)
        #expect(try await first.value == (test.id == "store.19" ? 1 : 2))
        #expect(try await second.value == 2)
    case "store.20", "store.32", "store.33":
        let branch = state(true)
        let root = computed { get -> Int? in try get(branch) ? get(source) : nil }
        try store.watch(root) { calls += 1 }
        if test.id == "store.33" { try store.watch(source) {} }
        #expect(store.isMounted(source))
        try store.set(branch, false)
        #expect(try store.get(root) == nil)
        #expect(store.isMounted(source) == (test.id == "store.33"))
        try store.set(source, 2)
        #expect(calls == 1)
    case "store.21":
        let value = State<Int?>(nil)
        let derived = computed { try $0(value) }
        let conditional = computed { get -> Int? in
            guard try get(value) != nil else { return nil }
            return try get(derived)
        }
        try store.watch(derived) { calls += 1 }
        try store.watch(conditional) {}
        #expect(calls == 0)
        try store.set(value, 1)
        #expect(calls == 1)
    case "store.22", "store.23":
        let first = try store.watch(source) {}
        let second = test.id == "store.23" ? try store.watch(source) {} : nil
        try first.cancel()
        try first.cancel()
        try second?.cancel()
        #expect(!store.isMounted(source))
    case "store.24":
        let root = Computed<Int?> { _ in nil }
        let stop = try store.watch(root) { calls += 1 }
        #expect(try store.get(root) == nil && calls == 0)
        try store.set(state(0), 1)
        #expect(calls == 0)
        try stop.cancel()
    case "store.25":
        try store.watch(source) { calls += 1 }
        try store.set(source, 1)
        #expect(calls == 1)
    case "store.27":
        let other = state(0)
        let root = computed { try [$0(source), $0(other)] }
        let stop = try store.watch(root) { calls += 1 }
        try stop.cancel()
        try store.set(source, 1)
        try store.set(other, 2)
        #expect(calls == 0)
    case "store.28":
        let first = computed { get in
            calls += 1
            return try get(source)
        }
        let root = computed { try $0(first) }
        let stop = try store.watch(root) {}
        calls = 0
        try store.set(source, 1)
        #expect(calls == 1)
        try stop.cancel()
        calls = 0
        try store.set(source, 2)
        #expect(calls == 0)
    case "store.29":
        let root = computed { get in
            calls += 1
            return try get(source) * 2
        }
        _ = try store.get(root)
        #expect(calls == 1)
        calls = 0
        try store.set(source, 1)
        _ = try store.get(root)
        #expect(calls == 1)
    case "store.30":
        let first = computed { try $0(source) }
        let second = computed { get in
            calls += 1
            _ = try get(source)
            return 0
        }
        let stop = try store.watch(first) {}
        _ = try store.get(second)
        try stop.cancel()
        calls = 0
        try store.set(source, 1)
        #expect(calls == 0)
        #expect(store.getReadDependents(source).children.isEmpty)
    case "store.31":
        let other = state(0)
        let branch = state(true)
        let root = computed { get in try get(branch) ? get(source) : get(other) }
        let stop = try store.watch(root) {}
        try store.set(branch, false)
        try stop.cancel()
        #expect(store.getReadDependents(other).children.isEmpty)
        #expect(!store.isMounted(source) && !store.isMounted(other))
    case "store.34":
        let base = computed { try $0(source) }
        let middle = computed { try $0(base) + 1 }
        let branch = state(true)
        let top = computed { get in try get(branch) ? get(middle) : get(base) }
        #expect(try store.get(top) == 1)
        try store.set(branch, false)
        #expect(try store.get(top) == 0)
        try store.set(source, 1)
        #expect(try store.get(top) == 1)
    default: Issue.record("Unported store case \(test.id)")
    }
}
