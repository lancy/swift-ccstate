/// Display state for a synchronous signal or a shared asynchronous task.
public enum Loadable<Value> {
    case loading
    case hasData(Value)
    case hasError(any Error)

    public var state: LoadableState {
        switch self {
        case .loading: .loading
        case .hasData: .hasData
        case .hasError: .hasError
        }
    }

    public var data: Value? {
        if case .hasData(let value) = self { return .some(value) }
        return nil
    }

    public var error: (any Error)? {
        if case .hasError(let error) = self { return error }
        return nil
    }
}

extension Loadable: Sendable where Value: Sendable {}

public enum LoadableState: Sendable, Equatable {
    case loading, hasData, hasError
}

/// Command status is local to one UI consumer, independently of shared read caches.
public enum OperationPhase<Value> {
    case idle
    case loading
    case hasData(Value)
    case hasError(any Error)

    public var state: OperationState {
        switch self {
        case .idle: .idle
        case .loading: .loading
        case .hasData: .hasData
        case .hasError: .hasError
        }
    }
    public var data: Value? {
        if case .hasData(let value) = self { return .some(value) }
        return nil
    }
    public var error: (any Error)? {
        if case .hasError(let error) = self { return error }
        return nil
    }
}

extension OperationPhase: Sendable where Value: Sendable {}

public enum OperationState: Sendable, Equatable {
    case idle, loading, hasData, hasError
}

public enum StoreObservationError: Error, Equatable {
    case missingStore
}
