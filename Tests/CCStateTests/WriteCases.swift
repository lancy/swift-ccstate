import Testing

@testable import CCState

@MainActor
func runWrites(_ test: UpstreamCase) async throws {
    let store = Store()
    let source = state(0)
    var seen: [Int] = []
    var reads = 0
    let target = computed { get in
        reads += 1
        return try get(source) * 2
    }
    switch test.id {
    case "batch-command.01", "watch-listener-prototype.09":
        let stop = try store.watch(target) { seen.append(try store.get(target)) }
        reads = 0
        try store.set(
            command { context in
                try context.set(source, 1)
                try context.set(source, 2)
                try context.set(source, 3)
            })
        #expect(reads == 1)
        #expect(seen == [6])
        try stop.cancel()
    case "batch-command.02", "batch-command.03":
        let stop = try store.watch(target) { seen.append(try store.get(target)) }
        reads = 0
        var intermediate: [Int] = []
        try store.set(
            command { context in
                try context.set(source, 1)
                intermediate.append(try test.id == "batch-command.03" ? store.get(target) : context.get(target))
                try context.set(source, 2)
                if test.id == "batch-command.02" { intermediate.append(try context.get(target)) }
                try context.set(source, 3)
            })
        #expect(intermediate == (test.id == "batch-command.02" ? [2, 4] : [2]))
        #expect(reads == (test.id == "batch-command.02" ? 3 : 2))
        #expect(seen == [6])
        try stop.cancel()
    case "batch-command.04":
        try store.watch(target) { seen.append(try store.get(target)) }
        let inner = command { context in
            try context.set(source, 2)
            try context.set(source, 3)
        }
        reads = 0
        try store.set(
            command { context in
                try context.set(source, 1)
                try context.set(inner)
                try context.set(source, 4)
            })
        #expect(reads == 1)
        #expect(seen == [8])
    case "batch-command.05":
        try store.watch(source) { seen.append(try store.get(source)) }
        let escaped = try store.set(command { $0 })
        try escaped.set(source, 1)
        try escaped.set(source, 2)
        #expect(seen == [1, 2])
    case "batch-command.06", "external.01":
        try store.watch(source) { seen.append(try store.get(source)) }
        let gate = Gate<Void>()
        let action = asyncCommand { (context: CommandContext, _: Void) in
            try context.set(source, 1)
            try context.set(source, 2)
            try await gate.wait()
            try context.set(source, 3)
            try context.set(source, 4)
        }
        let pending = try store.set(action)
        #expect(seen == [2])
        gate.resolve(())
        try await pending.value
        #expect(seen == [2, 3, 4])
    case "batch-command.07":
        try store.watch(source) { seen.append(try store.get(source)) }
        let gate = Gate<Void>()
        let inner = asyncCommand { (context: CommandContext, _: Void) in
            try context.set(source, 1)
            try await gate.wait()
            try context.set(source, 3)
        }
        var pending: Task<Void, Error>?
        try store.set(
            command { context in
                pending = try context.set(inner)
                try context.set(source, 2)
            })
        #expect(seen == [2])
        gate.resolve(())
        try await pending!.value
        #expect(seen == [2, 3])
    case "batch-command.08":
        let other = state(0)
        let sum = computed { try $0(source) + $0(other) }
        try store.watch(sum) { seen.append(try store.get(sum)) }
        try store.set(
            command { context in
                try context.set(source, 1)
                try store.set(other, 1)
                try context.set(source, 2)
            })
        #expect(seen == [2, 3])
    case "batch-command.09":
        try store.watch(source) { seen.append(try store.get(source)) }
        try store.set(
            command { context in
                try context.set(source, 1)
                try store.set(source, 2)
            })
        #expect(seen == [2])
    case "batch-command.10":
        var stop: Subscription?
        try store.set(
            command { context in
                try context.set(source, 1)
                stop = try store.watch(target) { seen.append(try store.get(target)) }
                #expect(try context.get(target) == 2)
                #expect(seen.isEmpty)
                try context.set(source, 2)
            })
        #expect(seen == [4])
        try stop?.cancel()
    case "batch-command.11":
        let enabled = state(false)
        let branch = computed { get -> Int? in try get(enabled) ? get(source) : nil }
        var observed: [Int?] = []
        try store.watch(branch) { observed.append(try store.get(branch)) }
        try store.set(
            command { context in
                try context.set(enabled, true)
                #expect(try context.get(branch) == 0)
                try context.set(source, 1)
            })
        #expect(observed == [1])
        try store.set(source, 2)
        #expect(observed == [1, 2])
    case "batch-command.12":
        let first = state(Box(0))
        let second = state(Box(0))
        let a = computed { try $0(first).value }
        let b = computed { try $0(second).value }
        let join = computed { try [$0(a), $0(b)] }
        var observed: [[Int]] = []
        try store.watch(join) { observed.append(try store.get(join)) }
        try store.set(
            command { context in
                try context.set(first, Box(0))
                try context.set(second, Box(1))
            })
        #expect(observed == [[0, 1]])
    case "batch-command.13", "watch-listener-prototype.03", "watch-listener-prototype.08":
        let other = test.id == "batch-command.13" ? state(0) : source
        let second = computed { get in
            try test.id == "watch-listener-prototype.03" ? get(source) % 2 : get(source) * 2
        }
        let first: Signal<Int> = test.id == "watch-listener-prototype.08" ? computed { try $0(source) } : source
        var observed: [[Int]] = []
        let listener = Listener {
            observed.append(
                try [store.get(source), test.id == "batch-command.13" ? store.get(other) : store.get(second)])
        }
        try store.watch(first, listener)
        if test.id == "batch-command.13" { try store.watch(other, listener) } else { try store.watch(second, listener) }
        if test.id == "batch-command.13" {
            try store.set(
                command { context in
                    try context.set(source, 1)
                    try context.set(other, 1)
                })
            #expect(observed == [[1, 1]])
        } else {
            try store.set(source, 1)
            #expect(observed == [[1, test.id == "watch-listener-prototype.03" ? 1 : 2]])
            if test.id == "watch-listener-prototype.03" {
                try store.set(source, 3)
                #expect(observed == [[1, 1], [3, 1]])
            }
        }
    case "batch-command.14", "watch-listener-prototype.10":
        try store.watch(source) { seen.append(try store.get(source)) }
        let action = command { context in
            try context.set(source, 1)
            if test.id == "batch-command.14" { try context.set(source, 2) }
            throw TestError("write failed")
        }
        #expect(throws: TestError.self) { try store.set(action) }
        #expect(seen == [test.id == "batch-command.14" ? 2 : 1])
    case "batch-command.15":
        var stop: Subscription?
        try store.set(
            source,
            update: { current in
                stop = try store.watch(source) { seen.append(try store.get(source)) }
                return current + 1
            })
        #expect(seen == [1])
        try stop?.cancel()
    case "batch-command.16":
        let stable = state(0)
        let changing = state(0)
        let closure = computed { get in { (value: Int) throws in try value + get(stable) } }
        let upstream = computed { get in try get(closure)(get(changing)) }
        let downstream = computed { try $0(upstream) * 2 }
        try store.watch(downstream) { seen.append(try store.get(downstream)) }
        try store.set(changing, 1)
        try store.set(changing, 2)
        try store.set(stable, 10)
        #expect(seen == [2, 4, 24])
    case "batch-command.17":
        let other = state(0)
        let primary = computed { get, options in
            let value = try get(source)
            if value == 0 { options.signal.onCancel { try! store.set(other, 1) } }
            return value
        }
        let join = computed { try $0(primary) + $0(other) }
        try store.watch(join) { seen.append(try store.get(join)) }
        try store.set(source, 1)
        #expect(seen == [2])
    case "watch-listener-prototype.01":
        let parity = computed { get in
            reads += 1
            return try get(source) % 2
        }
        var calls = 0
        let stop = try store.watch(parity) { calls += 1 }
        #expect(reads == 1 && calls == 0)
        try store.set(source, 2)
        #expect(reads == 2 && calls == 0)
        try store.set(source, 3)
        #expect(calls == 1)
        #expect(try store.get(parity) == 1)
        try stop.cancel()
    case "watch-listener-prototype.02", "external.02", "external.04", "external.06":
        let stop = try store.watch(source) { seen.append(try store.get(source)) }
        #expect(try store.get(source) == 0)
        #expect(seen.isEmpty)
        try store.set(source, 1)
        try store.set(source, 1)
        #expect(seen == [1])
        if test.id == "external.06" {
            for _ in 0..<3 { try store.set(source, update: { $0 + 1 }) }
            #expect(seen == [1, 2, 3, 4])
        }
        try stop.cancel()
        try store.set(source, 9)
        #expect(seen.last != 9)
    case "watch-listener-prototype.04":
        let other = Store()
        var first = 0
        var second = 0
        let a = try store.watch(source) { first += 1 }
        let b = try other.watch(source) { second += 1 }
        try store.set(source, 1)
        #expect(first == 1 && second == 0)
        #expect(try other.get(source) == 0)
        try a.cancel()
        try other.set(source, 2)
        #expect(second == 1)
        try b.cancel()
    case "watch-listener-prototype.05":
        // Swift rejects command subscription at compile time; the negative fixture
        // is checked by Scripts/check-negative-compilation.sh, rather than casting.
        let action = command { _ in 1 }
        #expect(try store.set(action) == 1)
    case "watch-listener-prototype.06":
        var first = 0
        var second = 0
        let a = try store.watch(target) { first += 1 }
        let b = try store.watch(target) { second += 1 }
        try a.cancel()
        try a.cancel()
        try store.set(source, 1)
        #expect(first == 0 && second == 1)
        try b.cancel()
        try store.set(source, 2)
        #expect(reads == 2 && second == 1)
        #expect(try store.get(target) == 4)
        #expect(reads == 3)
    case "watch-listener-prototype.07":
        let short = computed { try $0(source) }
        let middle = computed { try $0(source) + 1 }
        let long: Computed<Int>
        long = computed { try $0(middle) + 1 }
        let join = computed { try [$0(short), $0(long)] }
        var observed: [[Int]] = []
        try store.watch(join) { observed.append(try store.get(join)) }
        try store.set(source, 1)
        #expect(observed == [[1, 3]])
    case "watch-listener-prototype.11":
        let root = computed { try $0(source) }
        try store.watch(root) {
            let value = try store.get(root)
            seen.append(value)
            if value < 3 { try store.set(source, value + 1) }
        }
        try store.set(source, 1)
        #expect(seen == [1, 2, 3])
    case "watch-listener-prototype.12":
        var second = 0
        try store.watch(target) { throw TestError("listener failed") }
        try store.watch(target) { second += 1 }
        do {
            try store.set(source, 1)
            Issue.record("Expected aggregate listener error")
        } catch let error as ListenerErrors { #expect(error.errors.count == 1) }
        #expect(second == 1)
    case "watch-listener-prototype.13":
        let error = TestError("computed failed")
        let root = Computed { get in
            if try get(source) > 0 { throw error }
            return 42
        }
        var calls = 0
        try store.watch(root) { calls += 1 }
        try store.set(source, 1)
        #expect(calls == 1)
        #expect(throws: TestError.self) { try store.get(root) }
        try store.set(source, 2)
        #expect(calls == 1)
        try store.set(source, 0)
        #expect(calls == 2)
        #expect(try store.get(root) == 42)
    case "watch-listener-prototype.14":
        var stop: Subscription?
        var calls = 0
        stop = try store.watch(target) {
            calls += 1
            try stop?.cancel()
        }
        try store.set(source, 1)
        try store.set(source, 2)
        #expect(calls == 1)
    case "watch-listener-prototype.15":
        try await runMemory(UpstreamCase(id: "dynamic-dependency-memory.01", name: test.name, file: test.file))
    case "watch-listener-prototype.16":
        let gate = Gate<Void>()
        let root = computedTask { get, _ in
            reads += 1
            try await gate.wait()
            return try get(source)
        }
        var calls = 0
        try store.watch(root) { calls += 1 }
        let first = try store.get(root)
        gate.resolve(())
        #expect(try await first.value == 0)
        try store.set(source, 1)
        #expect(calls == 1)
        #expect(try await store.get(root).value == 1)
        #expect(reads == 2)
    case "watch-listener-prototype.17":
        try await obsoleteEvaluation(store: store)
    case "watch-listener-prototype.18":
        var signals: [EvaluationSignal] = []
        let root = computed { get, options in
            signals.append(options.signal)
            return try get(source)
        }
        let stop = try store.watch(root) {}
        try store.set(source, 1)
        #expect(signals[0].isCancelled && !signals[1].isCancelled)
        try stop.cancel()
        #expect(!signals[1].isCancelled)
    case "external.03":
        let gate = Gate<Void>()
        let root = computedTask { get, options in
            _ = try get(source)
            let evaluation = options.signal
            try await gate.wait()
            return Task.isCancelled || evaluation.isCancelled
        }
        var calls = 0
        let stop = try store.watch(root) { calls += 1 }
        let pending = try store.get(root)
        try stop.cancel()
        pending.cancel()
        gate.resolve(())
        #expect(try await pending.value)
        try store.set(source, 1)
        #expect(calls == 0)
    case "external.05":
        let gate = Gate<Void>()
        let root = computedTask { get, options in
            _ = try get(source)
            let signal = options.signal
            try await gate.wait()
            return signal.isCancelled
        }
        try store.watch(root) {}
        let first = try store.get(root)
        try store.set(source, 1)
        let second = try store.get(root)
        gate.resolve(())
        #expect(try await first.value)
        #expect(try await !second.value)
    default: Issue.record("Unported write case \(test.id)")
    }
}

@MainActor
func obsoleteEvaluation(store: Store) async throws {
    let branch = state(false)
    let old = state(1)
    let current = state(2)
    let gate = Gate<Void>()
    var reads = 0
    var calls = 0
    let root = computedTask { get, _ in
        reads += 1
        if try get(branch) { return try get(current) }
        try await gate.wait()
        return try get(old)
    }
    let stop = try store.watch(root) { calls += 1 }
    let obsolete = try store.get(root)
    try store.set(branch, true)
    let latest = try store.get(root)
    #expect(try await latest.value == 2)
    gate.resolve(())
    #expect(try await obsolete.value == 1)
    try store.set(old, 99)
    #expect(reads == 2 && calls == 1)
    #expect(try store.get(root) == latest)
    try store.set(current, 3)
    #expect(try await store.get(root).value == 3)
    #expect(calls == 2)
    try stop.cancel()
}
