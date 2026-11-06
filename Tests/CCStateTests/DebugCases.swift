import Testing

@testable import CCState

@MainActor
func runDebug(_ test: UpstreamCase) throws {
    if test.id.hasPrefix("console-interceptor.") {
        try runConsole(test)
        return
    }
    let base = state(0, debugLabel: "base")
    let derived = computed(debugLabel: "derived") { try $0(base) + 1 }
    var gets: [(AnySignal, Int)] = []
    var sets: [(AnySignal, Int?)] = []
    var mounts: [AnySignal] = []
    var unmounts: [AnySignal] = []
    var computes = 0
    var interceptor = StoreInterceptor()
    interceptor.get = { signal, fn in
        let result = try fn()
        gets.append((signal, result as? Int ?? -1))
    }
    interceptor.set = { signal, value, fn in
        _ = try fn()
        sets.append((signal, value as? Int))
    }
    interceptor.mount = { mounts.append($0) }
    interceptor.unmount = { unmounts.append($0) }
    interceptor.computed = { _, fn in
        computes += 1
        _ = try fn()
    }
    switch test.id {
    case "interceptor.03": interceptor.get = { _, _ in }
    case "interceptor.04": interceptor.set = { _, _, _ in }
    case "interceptor.05": interceptor.get = { signal, fn in if signal === derived { _ = try fn() } }
    case "interceptor.13": interceptor.computed = { _, _ in }
    default: break
    }
    let store = Store(interceptor: interceptor)
    switch test.id {
    case "interceptor.01":
        try store.set(base, 1)
        #expect(try store.get(base) == 1)
        #expect(gets.count == 1 && gets[0].0 === base && gets[0].1 == 1)
    case "interceptor.02":
        try store.set(base, 1)
        #expect(try store.get(derived) == 2)
        #expect(gets.count == 2 && gets[0].0 === base && gets[0].1 == 1)
        #expect(gets[1].0 === derived && gets[1].1 == 2)
    case "interceptor.03", "interceptor.05", "interceptor.13":
        #expect(throws: StoreError.interceptorMustCallSynchronously) {
            if test.id == "interceptor.03" { _ = try store.get(base) } else { _ = try store.get(derived) }
        }
    case "interceptor.04":
        #expect(throws: StoreError.interceptorMustCallSynchronously) { try store.set(base, 1) }
    case "interceptor.06":
        try store.set(base, 1)
        #expect(try store.get(base) == 1)
        #expect(sets.count == 1 && sets[0].0 === base && sets[0].1 == 1)
    case "interceptor.07":
        let action = command { (context: CommandContext, value: Int) in try context.set(base, value * 10) }
        try store.set(action, 1)
        #expect(try store.get(base) == 10)
        #expect(sets.count == 2 && sets[0].0 === base && sets[0].1 == 10)
        #expect(sets[1].0 === action && sets[1].1 == 1)
    case "interceptor.08":
        try store.watch(derived) {}
        #expect(mounts == [derived, base])
    case "interceptor.09":
        try store.watch(derived) {}
        let second = computed { try $0(derived) + 1 }
        mounts.removeAll()
        try store.watch(second) {}
        #expect(mounts == [second])
    case "interceptor.10":
        let stop = try store.watch(derived) {}
        try stop.cancel()
        #expect(unmounts == [derived, base])
    case "interceptor.11":
        try store.set(base, 1)
        #expect(gets.isEmpty)
    case "interceptor.12":
        try store.set(base, 1)
        #expect(computes == 0)
        _ = try store.get(derived)
        #expect(computes == 1)
        computes = 0
        try store.watch(derived) {}
        #expect(computes == 0)
        try store.set(base, 2)
        #expect(computes == 1)
    case "debug.01":
        try store.watch(derived) {}
        #expect(store.isMounted(base) && store.isMounted(derived))
    case "debug.02":
        _ = try store.get(derived)
        #expect(store.getReadDependents(base).children.isEmpty)
    case "debug.03":
        #expect(store.getReadDependencies(state(1)).labels == ["anonymous"])
    case "trace.01":
        try store.set(base, 1)
        try store.set(base, 2)
        _ = try store.get(derived)
        let first = store.getDependenciesGraph(derived)
        #expect(first.count == 1)
        #expect(first[0].parent.signal === derived && first[0].dependency.signal === base)
        #expect(first[0].parent.value as? Int == 3 && first[0].dependency.value as? Int == 2)
        #expect(first[0].parent.epoch == 0 && first[0].dependency.epoch == 1 && first[0].observedEpoch == 1)
        try store.set(base, 3)
        _ = try store.get(derived)
        let second = store.getDependenciesGraph(derived)[0]
        #expect(second.parent.value as? Int == 4 && second.dependency.value as? Int == 3)
        #expect(second.parent.epoch == 1 && second.dependency.epoch == 2 && second.observedEpoch == 2)
    case "trace.02":
        let count = state(0, debugLabel: "count")
        let branch = state(true, debugLabel: "branch")
        let b = computed(debugLabel: "base") { try $0(count) }
        let mid = computed(debugLabel: "mid") { try $0(b) + 1 }
        let top = computed(debugLabel: "top") { get in try get(branch) ? get(mid) : get(b) }
        _ = try store.get(top)
        let first = store.getDependenciesGraph(top)
        #expect(first.map { $0.dependency.signal.debugLabel! } == ["branch", "mid", "base", "count"])
        #expect(first.allSatisfy { $0.observedEpoch == 0 })
        try store.set(branch, false)
        _ = try store.get(top)
        let second = store.getDependenciesGraph(top)
        #expect(second.map { $0.dependency.signal.debugLabel! } == ["branch", "base", "count"])
        #expect(second[0].parent.epoch == 1 && second[0].observedEpoch == 1)
        #expect(second[1].parent.value as? Int == 0 && second[1].observedEpoch == 0)
    default: Issue.record("Unported debug case \(test.id)")
    }
}

@MainActor
private func runConsole(_ test: UpstreamCase) throws {
    let index = Int(test.id.split(separator: ".")[1])!
    let first = state(0, debugLabel: "base")
    let second = state(0, debugLabel: "base")
    let doubled = computed(debugLabel: "doubleBase") { try $0(first) * 2 }
    let action = command(debugLabel: "callback") { _ in }
    var messages: [String] = []
    if index >= 8 {
        let watch: DebugWatch
        let actions: Set<StoreEvent>?
        switch index {
        case 8:
            watch = DebugWatch(.substring("base"))
            actions = [.mount]
        case 9:
            watch = DebugWatch(.regex(try Regex(".")))
            actions = [.mount]
        case 10:
            watch = DebugWatch(.signal(first), actions: [.set])
            actions = nil
        case 11:
            watch = DebugWatch(.signal(first))
            actions = [.set]
        default:
            watch = DebugWatch(.signal(first))
            actions = nil
        }
        let store = createDebugStore(watches: [watch], defaultActions: actions, emit: { messages.append($0) })
        try store.set(first, 1)
        if index != 12 { _ = try store.get(first) }
        #expect(messages.count == (index == 8 || index == 9 ? 0 : 1))
        return
    }
    let watches: [DebugWatch]
    switch index {
    case 1: watches = [DebugWatch(.signal(first), actions: [.set])]
    case 2: watches = [DebugWatch(.signal(first), actions: [.mount])]
    case 3: watches = [DebugWatch(.signal(first), actions: [.unmount])]
    case 4: watches = [DebugWatch(.signal(doubled), actions: [.computed])]
    case 5: watches = [first, second, doubled, action].map { DebugWatch(.signal($0)) }
    case 6: watches = [DebugWatch(.substring("doubleBase"))]
    default: watches = [DebugWatch(.regex(try Regex("(?i)doublebase")))]
    }
    let store = Store(interceptor: ConsoleInspector(watches: watches, emit: { messages.append($0) }).makeInterceptor())
    try store.set(first, 1)
    try store.set(second, 2)
    func notify() throws {
        _ = try store.get(doubled)
        try store.set(action)
    }
    let stop = try store.watch(doubled) { try notify() }
    try notify()
    _ = try store.get(first)
    try store.set(first, 3)
    try stop.cancel()
    switch index {
    case 1, 4: #expect(messages.count == 2)
    case 2, 3: #expect(messages.count == 1)
    case 5:
        #expect(messages.filter { !$0.contains("[MNT]") && !$0.contains("[UNM]") }.count == 12)
    default: #expect(!messages.isEmpty && messages.allSatisfy { $0.contains("doubleBase") })
    }
}
