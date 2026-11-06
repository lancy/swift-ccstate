/// Cancellation belongs to an evaluation, independently of its subscribers.
/// The store never cancels a returned Task implicitly.
@MainActor
public final class EvaluationSignal {
    public private(set) var isCancelled = false
    private var handlers: [() -> Void] = []

    public func checkCancellation() throws {
        if isCancelled { throw CancellationError() }
    }

    public func onCancel(_ handler: @escaping () -> Void) {
        if isCancelled { handler() } else { handlers.append(handler) }
    }

    internal func cancel() {
        guard !isCancelled else { return }
        isCancelled = true
        let pending = handlers
        handlers.removeAll()
        for handler in pending { handler() }
    }
}

@MainActor
public final class ComputedOptions {
    private weak let record: Record?
    private let dependencies: Dependencies
    private var storedSignal: EvaluationSignal?

    internal init(record: Record, dependencies: Dependencies) {
        self.record = record
        self.dependencies = dependencies
    }

    public var signal: EvaluationSignal {
        if let storedSignal { return storedSignal }
        let signal = EvaluationSignal()
        storedSignal = signal
        if record?.dependencies === dependencies {
            record?.cancellation = signal
        } else {
            signal.cancel()
        }
        return signal
    }
}

/// Starts synchronously until the first actual suspension, like an async JS read.
@MainActor
public func computedTask<Value: Sendable>(
    debugLabel: String? = nil,
    _ read: @escaping @MainActor (Getter, ComputedOptions) async throws -> Value
) -> Computed<Task<Value, Error>> {
    Computed(debugLabel: debugLabel) { get, options in
        Task.immediate { @MainActor in try await read(get, options) }
    }
}
