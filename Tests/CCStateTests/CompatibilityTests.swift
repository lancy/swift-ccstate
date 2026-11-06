import Foundation
import Testing

@testable import CCState

internal struct UpstreamCase: Sendable, CustomTestStringConvertible {
    let id: String
    let name: String
    let file: String
    var testDescription: String { "\(id): \(name)" }
}

@MainActor
internal final class TestError: Error {
    nonisolated let message: String
    nonisolated init(_ message: String = "test") { self.message = message }
}

@MainActor
internal final class Box<Value> {
    var value: Value
    init(_ value: Value) { self.value = value }
}

@MainActor
internal final class Gate<Value: Sendable> {
    private var result: Result<Value, Error>?
    private var waiters: [CheckedContinuation<Value, Error>] = []
    func wait() async throws -> Value {
        if let result { return try result.get() }
        return try await withCheckedThrowingContinuation { waiters.append($0) }
    }
    func resolve(_ value: Value) { finish(.success(value)) }
    func reject(_ error: Error) { finish(.failure(error)) }
    private func finish(_ result: Result<Value, Error>) {
        guard self.result == nil else { return }
        self.result = result
        let pending = waiters
        waiters.removeAll()
        for waiter in pending { waiter.resume(with: result) }
    }
}

@Suite(.serialized)
@MainActor
struct CompatibilityTests {
    @Test("Pinned upstream behavior", arguments: upstreamCases)
    func upstream(_ test: UpstreamCase) async throws {
        switch test.id.components(separatedBy: ".")[0] {
        case "basic", "distinct", "empty-state", "effect", "cache", "result":
            try await runValues(test)
        case "batch-command", "watch-listener-prototype", "external":
            try await runWrites(test)
        case "abort", "dependencies", "promise":
            try await runAsync(test)
        case "memory", "dynamic-dependency-memory":
            try await runMemory(test)
        case "store", "ccstate", "glitch", "propagation":
            try await runGraphs(test)
        case "interceptor", "debug", "trace", "console-interceptor":
            try runDebug(test)
        default: Issue.record("Missing upstream case: \(test.id)")
        }
    }
}
