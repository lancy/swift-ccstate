import Testing

@testable import CCState

@MainActor
func runAsync(_ test: UpstreamCase) async throws {
    if test.id.hasPrefix("abort.") {
        try await runAbort(test)
        return
    }
    let store = Store()
    switch test.id {
    case "dependencies.01":
        let source = state(1)
        let gate = Box(Gate<Void>())
        let first = computedTask { get, _ in
            let n = try get(source)
            try await gate.value.wait()
            return n
        }
        let second = computed { try $0(first) }
        let third = computed { try $0(second) }
        for n in 1...3 {
            if n > 1 {
                gate.value = Gate<Void>()
                try store.set(source, n)
            }
            let task = try store.get(third)
            gate.value.resolve(())
            #expect(try await task.value == n)
        }
    case "dependencies.02":
        let source = state(0)
        let gate = Gate<Void>()
        let root = computedTask { get, _ in
            let n = try get(source)
            try await gate.wait()
            return n
        }
        try store.set(source, 1)
        let old = try store.get(root)
        try store.set(source, 2)
        let latest = try store.get(root)
        gate.resolve(())
        #expect(try await latest.value == 2)
        #expect(try await old.value == 1)
    case "dependencies.03":
        let source = state(0)
        let root = computedTask { get, _ in try get(source) + 1 }
        let update = asyncCommand { (context: CommandContext, value: Int) in try context.set(source, value) }
        #expect(try await store.get(root).value == 1)
        try await store.set(update, 2).value
        #expect(try store.get(source) == 2)
        #expect(try await store.get(root).value == 3)
    case "dependencies.04":
        let data = computedTask { _, _ in "Asynchronous Data" }
        let counter = state(0)
        let root = computed { get in
            _ = try get(counter)
            return try get(data)
        }
        let first = try store.get(root)
        try store.set(counter, 1)
        let second = try store.get(root)
        #expect(first == second)
        #expect(try await second.value == "Asynchronous Data")
    case "dependencies.05":
        let source = state(0)
        let gate = Box(Gate<Void>())
        let root = computedTask { get, _ in
            try await gate.value.wait()
            return try get(source)
        }
        #expect(store.getReadDependents(source).children.isEmpty)
        let stop = try store.watch(root) {}
        let first = try store.get(root)
        gate.value.resolve(())
        _ = try await first.value
        #expect(store.getReadDependents(source).children.first?.signal === root)
        gate.value = Gate<Void>()
        try store.set(source, 1)
        #expect(store.getReadDependents(source).children.isEmpty)
        let second = try store.get(root)
        gate.value.resolve(())
        _ = try await second.value
        try stop.cancel()
    case "dependencies.06":
        let base = state([100])
        let hasFilter = state(false)
        let derived = computed { get in try get(hasFilter) ? [] : get(base) }
        let stage = computed { get in
            try get(hasFilter) ? (get(derived).isEmpty ? "is-empty" : "has-data") : "no-filter"
        }
        try store.watch(derived) {}
        try store.watch(stage) {}
        #expect(try store.get(stage) == "no-filter")
        try store.set(hasFilter, true)
        #expect(try store.get(stage) == "is-empty")
    case "dependencies.07", "dependencies.08":
        let oldGate = Gate<Void>()
        let nextGate = Gate<Void>()
        let entry = Gate<Void>()
        let attached = Gate<Void>()
        let source = state(oldGate)
        let root = computedTask { get, _ in
            if test.id == "dependencies.08" { try await entry.wait() }
            let selected = try get(source)
            attached.resolve(())
            try await selected.wait()
        }
        let oldTask = try store.get(root)
        var subscriptions = 0
        var completed = 0
        var consumers: [Task<Void, Error>] = []
        func consume() throws {
            subscriptions += 1
            let task = try store.get(root)
            consumers.append(
                Task.immediate { @MainActor in
                    try await task.value
                    completed += 1
                })
        }
        let stop = try store.watch(root) { try consume() }
        try consume()
        entry.resolve(())
        try await attached.wait()
        try store.set(source, nextGate)
        let current = try store.get(root)
        nextGate.resolve(())
        try await current.value
        try await consumers[1].value
        #expect(subscriptions == 2)
        #expect(completed == 1)
        try stop.cancel()
        oldGate.resolve(())
        try await oldTask.value
        try await consumers[0].value
    case "dependencies.09":
        let count = state(0)
        let extra = state(false)
        let gate = Gate<Void>()
        var seen: [Int] = []
        let root = computedTask { get, _ in
            let n = try get(count)
            seen.append(n)
            if n == 0 { _ = try get(extra) }
            try await gate.wait()
            return n
        }
        let first = try store.get(root)
        try store.set(count, 1)
        let second = try store.get(root)
        gate.resolve(())
        #expect(try await second.value == 1)
        #expect(seen == [0, 1])
        seen.removeAll()
        try store.set(extra, true)
        #expect(try await store.get(root).value == 1)
        #expect(seen.isEmpty)
        _ = try await first.value
    case "dependencies.10":
        let count = state(0)
        let branch = state(false)
        let stable = computed { get in
            _ = try get(branch)
            return 1
        }
        var reads = 0
        let child = computed { get in
            _ = try get(stable)
            reads += 1
            return try 2 + get(count)
        }
        let root = computed { get in try get(branch) || get(count) > 0 ? get(child) : get(stable) }
        try store.watch(child) {}
        try store.watch(root) {}
        #expect(try store.get(child) == 2)
        #expect(reads == 1)
        try store.set(branch, true)
        #expect(try store.get(root) == 2)
        #expect(reads == 1)
        reads = 0
        try store.set(branch, false)
        #expect(reads == 0)
        try store.set(count, 1)
        #expect(reads == 1)
        #expect(try store.get(root) == 3)
    case "dependencies.11":
        let source = state(1)
        let gate = Gate<Void>()
        let first = computed { try $0(source) * 2 }
        let second = computed { try $0(first) + 1 }
        let root = computedTask { get, _ in
            let n = try get(second)
            try await gate.wait()
            return n * 2
        }
        let old = try store.get(root)
        gate.resolve(())
        #expect(try await old.value == 6)
        try store.set(source, 2)
        #expect(try await store.get(root).value == 10)
    case "promise.01", "promise.02", "promise.03":
        // Swift has no process-level unhandledRejection event. These three native
        // adaptations verify that the store preserves failing Tasks unchanged;
        // error observation belongs to each caller awaiting task.value.
        let source = state(0)
        let gate = Gate<Void>()
        let error = TestError("task failure")
        var tasks: [Task<Int, Error>] = []
        let root = computedTask { get, _ -> Int in
            _ = try get(source)
            try await gate.wait()
            throw error
        }
        let stop = try store.watch(root) { tasks.append(try store.get(root)) }
        tasks.insert(try store.get(root), at: 0)
        #expect(try store.get(root) == tasks[0])
        if test.id != "promise.01" {
            try store.set(source, 1)
            #expect(tasks.count == 2)
        }
        gate.resolve(())
        for task in tasks {
            do {
                _ = try await task.value
                Issue.record("Expected task failure")
            } catch { #expect((error as? TestError)?.message == "task failure") }
        }
        try stop.cancel()
    default: Issue.record("Unported async case \(test.id)")
    }
}

@MainActor
private func runAbort(_ test: UpstreamCase) async throws {
    let index = Int(test.id.split(separator: ".")[1])!
    let store = Store()
    let source = state(0)
    if index == 1 {
        let gates = [Gate<Void>(), Gate<Void>()]
        var calls = 0
        let root = computedTask { get, options in
            let revision = try get(source)
            options.signal.onCancel { gates[revision].reject(CancellationError()) }
            try await gates[revision].wait()
            calls += 1
            return revision
        }
        let first = try store.get(root)
        try store.set(source, 1)
        let second = try store.get(root)
        gates[1].resolve(())
        await #expect(throws: CancellationError.self) { try await first.value }
        #expect(try await second.value == 1)
        #expect(calls == 1)
        return
    }
    if index >= 16 {
        var options: [ComputedOptions] = []
        var calls = 0
        let root = computed { get, option in
            options.append(option)
            return try get(source)
        }
        let stop = try store.watch(root) { calls += 1 }
        let first: EvaluationSignal? = index == 17 ? nil : options[0].signal
        if index == 18 {
            try stop.cancel()
            #expect(!first!.isCancelled)
            try store.set(source, 1)
            #expect(options.count == 1 && calls == 0)
            #expect(try store.get(root) == 1)
            #expect(first!.isCancelled && !options[1].signal.isCancelled)
        } else {
            try store.set(source, 1)
            let second = options[1].signal
            #expect(options[0].signal.isCancelled)
            if let first { #expect(options[0].signal === first) }
            #expect(!second.isCancelled && options[1].signal === second)
            try stop.cancel()
        }
        return
    }
    let mounted = index >= 9
    let variant = mounted ? index - 7 : index
    switch variant {
    case 2:
        var options: [ComputedOptions] = []
        let root = computed { get, option in
            _ = try get(source)
            options.append(option)
            let signal = option.signal
            #expect(option.signal === signal && !signal.isCancelled)
            return signal
        }
        if mounted { try store.watch(root) {} }
        let first = try store.get(root)
        #expect(options[0].signal === first && !first.isCancelled)
        try store.set(source, 1)
        let second = try store.get(root)
        #expect(first !== second && first.isCancelled && !second.isCancelled)
        #expect(options[0].signal === first && options[1].signal === second)
    case 3, 4:
        let before = variant == 4
        let gate = Gate<Void>()
        var current: EvaluationSignal?
        let root = computedTask { get, options in
            let revision = try get(source)
            let initial = before || revision > 0 ? options.signal : nil
            if revision > 0 { current = initial }
            try await gate.wait()
            let signal = options.signal
            if let initial { #expect(signal === initial) }
            #expect(options.signal === signal)
            return signal
        }
        if mounted { try store.watch(root) {} }
        let first = try store.get(root)
        try store.set(source, 1)
        let second = try store.get(root)
        #expect(current?.isCancelled == false)
        gate.resolve(())
        let oldSignal = try await first.value
        let newSignal = try await second.value
        #expect(oldSignal.isCancelled && !newSignal.isCancelled)
        #expect(newSignal === current)
    case 5:
        let unrelated = state(0)
        var signal: EvaluationSignal?
        let root = computed { get, options in
            let result = try get(source)
            if result == 0 { signal = options.signal }
            return result
        }
        if mounted { try store.watch(root) {} }
        #expect(try store.get(root) == 0)
        _ = try store.get(root)
        try store.set(unrelated, 1)
        _ = try store.get(root)
        try store.set(source, 0)
        _ = try store.get(root)
        #expect(signal?.isCancelled == false)
        try store.set(source, 1)
        #expect(signal?.isCancelled == mounted)
        #expect(try store.get(root) == 1)
        #expect(signal?.isCancelled == true)
    case 6:
        let other = Store()
        let root = computed { get, options in
            _ = try get(source)
            return options.signal
        }
        if mounted {
            try store.watch(root) {}
            try other.watch(root) {}
        }
        let first = try store.get(root)
        let second = try other.get(root)
        #expect(first !== second)
        try store.set(source, 1)
        let next = try store.get(root)
        #expect(first.isCancelled && !next.isCancelled && !second.isCancelled)
        #expect(try other.get(root) === second)
        try other.set(source, 1)
        #expect(try other.get(root) !== second)
        #expect(second.isCancelled && !next.isCancelled)
    case 7:
        let error = TestError("failed")
        var signal: EvaluationSignal?
        let root = Computed { get, options in
            let n = try get(source)
            if n == 1 { throw error }
            signal = options.signal
            return n
        }
        let caught = computed { get -> Int in do { return try get(root) } catch { return -1 } }
        if mounted { try store.watch(caught) {} }
        #expect(try store.get(caught) == 0)
        let first = signal!
        try store.set(source, 1)
        #expect(try store.get(caught) == -1)
        #expect(first.isCancelled)
        try store.set(source, 2)
        #expect(try store.get(caught) == 2)
        #expect(signal !== first && signal?.isCancelled == false)
    case 8:
        let gates = [Gate<Int>(), Gate<Int>()]
        let tasks = gates.map { gate in Task.immediate { @MainActor in try await gate.wait() } }
        var signals: [EvaluationSignal] = []
        let root = computed { get, options in
            signals.append(options.signal)
            return try tasks[get(source)]
        }
        let stop = mounted ? try store.watch(root) {} : nil
        #expect(try store.get(root) == tasks[0])
        try store.set(source, 1)
        #expect(try store.get(root) == tasks[1])
        #expect(signals[0].isCancelled && !signals[1].isCancelled)
        #expect(!tasks[0].isCancelled && !tasks[1].isCancelled)
        gates[1].resolve(2)
        #expect(try await tasks[1].value == 2)
        gates[0].resolve(1)
        #expect(try await tasks[0].value == 1)
        #expect(try store.get(root) == tasks[1])
        try stop?.cancel()
    default: Issue.record("Unported abort case \(test.id)")
    }
}
