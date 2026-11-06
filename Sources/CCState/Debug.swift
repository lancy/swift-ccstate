@MainActor
public struct DependencyTree {
    public let signal: AnySignal
    public let children: [DependencyTree]
    public var labels: [String] {
        [signal.debugLabel ?? "anonymous"] + children.flatMap(\.labels)
    }
}

@MainActor
public struct GraphNode {
    public let signal: AnySignal
    public let value: Any?
    public let epoch: Int
}

@MainActor
public struct DependencyEdge {
    public let parent: GraphNode
    public let dependency: GraphNode
    public let observedEpoch: Int
}

extension Store {
    public func isMounted<Value>(_ signal: Signal<Value>) -> Bool {
        records[ObjectIdentifier(signal)]?.mounted != nil
    }

    public func getReadDependencies(_ signal: AnySignal) -> DependencyTree {
        DependencyTree(
            signal: signal,
            children: (records[ObjectIdentifier(signal)]?.dependencies?.entries ?? [])
                .map { getReadDependencies($0.signal) })
    }

    public func getReadDependents(_ signal: AnySignal) -> DependencyTree {
        DependencyTree(
            signal: signal,
            children: (records[ObjectIdentifier(signal)]?.mounted?.dependents ?? [])
                .map { getReadDependents($0) })
    }

    public func getDependenciesGraph<Value>(_ signal: Computed<Value>) -> [DependencyEdge] {
        func node(_ signal: AnySignal, _ record: Record) -> GraphNode {
            let value: Any?
            if case .success(let output) = record.result { value = output } else { value = nil }
            return GraphNode(signal: signal, value: value, epoch: record.epoch)
        }
        func edges(_ signal: AnySignal) -> [DependencyEdge] {
            guard let current = records[ObjectIdentifier(signal)] else { return [] }
            var result: [DependencyEdge] = []
            for dependency in current.dependencies?.entries ?? [] {
                guard let child = records[ObjectIdentifier(dependency.signal)] else { continue }
                result.append(
                    DependencyEdge(
                        parent: node(signal, current), dependency: node(dependency.signal, child),
                        observedEpoch: dependency.epoch))
                if dependency.signal.isComputed { result.append(contentsOf: edges(dependency.signal)) }
            }
            return result
        }
        return edges(signal)
    }
}

@MainActor
public enum WatchTarget {
    case signal(AnySignal)
    case substring(String)
    case regex(Regex<Substring>)

    internal func matches(_ signal: AnySignal) -> Bool {
        switch self {
        case .signal(let target): target === signal
        case .substring(let text): signal.description.contains(text)
        case .regex(let pattern): signal.description.firstMatch(of: pattern) != nil
        }
    }
}

@MainActor
public struct DebugWatch {
    public let target: WatchTarget
    public let actions: Set<StoreEvent>?
    public init(_ target: WatchTarget, actions: Set<StoreEvent>? = nil) {
        self.target = target
        self.actions = actions
    }
}

@MainActor
public final class ConsoleInspector {
    private let watches: [DebugWatch]
    private let emit: (String) -> Void
    public init(watches: [DebugWatch], emit: @escaping (String) -> Void = { print($0) }) {
        self.watches = watches
        self.emit = emit
    }

    private func log(_ signal: AnySignal, _ action: StoreEvent, _ tag: String) {
        if watches.contains(where: { $0.target.matches(signal) && ($0.actions?.contains(action) ?? true) }) {
            emit("[R][\(tag)] \(signal)")
        }
    }

    public func makeInterceptor() -> StoreInterceptor {
        var interceptor = StoreInterceptor()
        interceptor.get = { signal, fn in
            self.log(signal, .get, "GET")
            _ = try fn()
        }
        interceptor.set = { signal, _, fn in
            self.log(signal, .set, "SET")
            _ = try fn()
        }
        interceptor.computed = { signal, fn in
            self.log(signal, .computed, "CPT")
            _ = try fn()
        }
        interceptor.mount = { self.log($0, .mount, "MNT") }
        interceptor.unmount = { self.log($0, .unmount, "UNM") }
        return interceptor
    }
}

@MainActor
public func createDebugStore(
    watches: [DebugWatch] = [], defaultActions: Set<StoreEvent>? = nil,
    emit: @escaping (String) -> Void = { print($0) }
) -> Store {
    let watches = watches.map { DebugWatch($0.target, actions: $0.actions ?? defaultActions) }
    return Store(interceptor: ConsoleInspector(watches: watches, emit: emit).makeInterceptor())
}
