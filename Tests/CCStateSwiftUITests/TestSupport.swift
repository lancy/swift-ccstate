import CCState
import Foundation
import Observation
import Synchronization
import Testing

@testable import CCStateSwiftUI

@MainActor
final class TestFailure: Error {
    nonisolated let message: String
    nonisolated init(_ message: String = "test failure") { self.message = message }
}

@MainActor
final class Payload<Value> {
    var value: Value
    init(_ value: Value) { self.value = value }
}

@MainActor
final class Deferred<Value: Sendable> {
    private var result: Result<Value, Error>?
    private var waiters: [CheckedContinuation<Value, Error>] = []
    func value() async throws -> Value {
        if let result { return try result.get() }
        return try await withCheckedThrowingContinuation { waiters.append($0) }
    }
    func resolve(_ value: Value) { finish(.success(value)) }
    func reject(_ error: Error) { finish(.failure(error)) }
    private func finish(_ result: Result<Value, Error>) {
        guard self.result == nil else { return }
        self.result = result
        let current = waiters
        waiters.removeAll()
        for waiter in current { waiter.resume(with: result) }
    }
    func task() -> Task<Value, Error> { Task.immediate { @MainActor in try await self.value() } }
}

final class ChangeCount: Sendable {
    private let storage = Mutex(0)
    var value: Int { storage.withLock { $0 } }
    func increment() { storage.withLock { $0 += 1 } }
}

@MainActor
func connect<Value>(
    _ store: Store?, _ signal: Signal<Value>, keepLast: Bool = false,
    equals: @escaping (Value, Value) -> Bool = defaultEquality
) -> ReadObservation<Value> {
    let observation = ReadObservation<Value>()
    observation.connect(
        ReadSource(store: store, signal: signal), keepLast: keepLast, equals: equals,
        onCleanupError: { Issue.record("Unexpected cleanup error: \($0)") })
    return observation
}

@MainActor
func connect<Value: Sendable, Failure: Error>(
    _ store: Store?, task signal: Signal<Task<Value, Failure>>,
    keepLast: Bool = false,
    equals: @escaping (Value, Value) -> Bool = defaultEquality
) -> ReadObservation<Value> {
    let observation = ReadObservation<Value>()
    observation.connect(
        ReadSource(store: store, task: signal), keepLast: keepLast, equals: equals,
        onCleanupError: { Issue.record("Unexpected cleanup error: \($0)") })
    return observation
}

@MainActor
func track(_ read: () -> Void) -> ChangeCount {
    let count = ChangeCount()
    withObservationTracking(read, onChange: { count.increment() })
    return count
}
