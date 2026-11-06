import CCState
import Testing

@testable import CCStateSwiftUI

@MainActor
func runOperationReference(_ test: ReactReferenceCase) async throws {
    let store = Store()
    switch test.id {
    case "loadable-set.01", "loadable-set.02", "loadable-set.08":
        let deferred = Deferred<String>()
        let original = deferred.task()
        let command = Command<Task<String, Error>, Void> { _ in original }
        let operation = LoadableAction<String, Void, Task<String, Error>>(
            invoke: { try store.set(command) }, resolve: { task in .task { try await task.value } })
        #expect(operation.phase.state == .idle)
        let returned = try operation()
        #expect(returned == original)
        #expect(operation.phase.state == .loading)
        if test.id == "loadable-set.02" { deferred.reject(TestFailure("rejected")) } else { deferred.resolve("foo") }
        await operation.pending?.value
        if test.id == "loadable-set.02" {
            #expect(operation.phase.state == .hasError)
            #expect((operation.phase.error as? TestFailure)?.message == "rejected")
        } else {
            #expect(operation.phase.data == "foo" && operation.phase.state == .hasData)
        }
    case "loadable-set.03":
        let command = Command<String, Void> { _ in "sync result" }
        let operation = LoadableAction<String, Void, String>(
            invoke: { try store.set(command) }, resolve: { .value($0) })
        #expect(operation.phase.state == .idle)
        #expect(try operation() == "sync result")
        #expect(operation.phase.data == "sync result")
    case "loadable-set.04":
        let source = CCState.State(0)
        let operation = LoadableAction<Void, Int, Void>(invoke: { try store.set(source, $0) }, resolve: { .value($0) })
        try operation(42)
        #expect(try store.get(source) == 42)
        #expect(operation.phase.state == .hasData)
    case "loadable-set.05", "loadable-set.06":
        let first = CCState.State("A0")
        let second = CCState.State("B0")
        let a = Command<Void, String> { try $0.set(first, $1) }
        let b = Command<Void, String> { try $0.set(second, $1) }
        let holder = ActionStorage<LoadableAction<Void, String, Void>>(dispose: { $0.disconnect() })
        func make(_ target: CCState.State<String>) -> LoadableAction<Void, String, Void> {
            LoadableAction(
                invoke: { value in
                    if test.id == "loadable-set.05" {
                        try store.set(target, value)
                    } else {
                        try store.set(target === first ? a : b, value)
                    }
                }, resolve: { .value($0) })
        }
        _ = holder.get(store: store, signal: test.id == "loadable-set.05" ? first : a) { make(first) }
        let current = holder.get(store: store, signal: test.id == "loadable-set.05" ? second : b) { make(second) }
        try current("updated")
        #expect(try store.get(first) == "A0" && store.get(second) == "updated")
        #expect(current.phase.state == .hasData)
    case "loadable-set.07":
        let gates = [Deferred<String>(), Deferred<String>()]
        var index = 0
        let command = Command<Task<String, Error>, Void> { _ in
            defer { index += 1 }
            return gates[index].task()
        }
        let operation = LoadableAction<String, Void, Task<String, Error>>(
            invoke: { try store.set(command) }, resolve: { task in .task { try await task.value } })
        let first = try operation()
        let obsolete = operation.pending
        let second = try operation()
        #expect(!first.isCancelled && !second.isCancelled)
        gates[1].resolve("second")
        await operation.pending?.value
        #expect(operation.phase.data == "second")
        gates[0].resolve("first")
        await obsolete?.value
        #expect(operation.phase.data == "second")
        #expect(try await first.value == "first")
    default: Issue.record("Missing operation reference \(test.id)")
    }
}
