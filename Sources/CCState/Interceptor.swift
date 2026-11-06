public enum StoreEvent: String, CaseIterable, Hashable, Sendable {
    case get, set, computed, mount, unmount
}

@MainActor
public struct StoreInterceptor {
    public var get: ((AnySignal, () throws -> Any) throws -> Void)?
    public var set: ((AnySignal, Any?, () throws -> Any) throws -> Void)?
    public var computed: ((AnySignal, () throws -> Any) throws -> Void)?
    public var mount: ((AnySignal) -> Void)?
    public var unmount: ((AnySignal) -> Void)?
    public init() {}
}

extension Store {
    internal func intercept(
        _ signal: AnySignal, event: StoreEvent, argument: Any? = nil,
        _ body: () throws -> Any
    ) throws -> Any {
        let callback: ((() throws -> Any) throws -> Void)?
        switch event {
        case .get: callback = interceptor.get.map { hook in { try hook(signal, $0) } }
        case .set: callback = interceptor.set.map { hook in { try hook(signal, argument, $0) } }
        case .computed: callback = interceptor.computed.map { hook in { try hook(signal, $0) } }
        default: callback = nil
        }
        guard let callback else { return try body() }
        var result: Result<Any, Error>?
        try callback {
            result = Result { try body() }
            return try result!.get()
        }
        guard let result else { throw StoreError.interceptorMustCallSynchronously }
        return try result.get()
    }
}
