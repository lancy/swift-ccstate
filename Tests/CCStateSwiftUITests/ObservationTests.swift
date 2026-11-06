import CCState
import Testing

@testable import CCStateSwiftUI

@Suite
@MainActor
struct ObservationTests {
    @Test func synchronousReadAndCleanup() throws {
        let store = Store()
        let signal = CCState.State(0)
        var observation: ReadObservation<Int>? = connect(store, signal)
        #expect(observation?.resolved == 0)
        #expect(store.isMounted(signal))
        try store.set(signal, 1)
        #expect(observation?.resolved == 1)
        weak let old = observation
        observation = nil
        #expect(old == nil)
        #expect(!store.isMounted(signal))
    }

    @Test func asynchronousReadDoesNotCancelSharedTask() async throws {
        let store = Store()
        let deferred = Deferred<Int>()
        let task = deferred.task()
        let signal = CCState.State(task)
        var first: ReadObservation<Int>? = connect(store, task: signal)
        let second = connect(store, task: signal)
        #expect(first?.state == .loading && second.state == .loading)
        first = nil
        #expect(!task.isCancelled)
        deferred.resolve(42)
        await second.pending?.value
        #expect(second.resolved == 42)
        second.disconnect()
        #expect(!store.isMounted(signal))
    }

    @Test func reportsCleanupFailures() throws {
        let store = Store()
        let source = CCState.State(0)
        let other = CCState.State(0)
        try store.watch(other) { throw TestFailure("listener") }
        let observation = ReadObservation<Int>()
        var errors: [any Error] = []
        observation.connect(ReadSource(store: store, signal: source), onCleanupError: { errors.append($0) })
        let action = Command<Void, Void> { context in
            try context.set(other, 1)
            observation.disconnect()
        }
        try store.set(action)
        #expect(errors.count == 1)
        #expect((errors.first as? ListenerErrors)?.errors.count == 1)
        #expect(!store.isMounted(source))
    }

    @Test func reconfiguringEqualityUsesLatestSettledValue() async throws {
        let store = Store()
        let first = Deferred<Payload<Int>>()
        let signal = CCState.State(first.task())
        let observation = connect(store, task: signal, keepLast: true, equals: { _, _ in true })
        first.resolve(Payload(1))
        await observation.pending?.value
        let second = Deferred<Payload<Int>>()
        try store.set(signal, second.task())
        second.resolve(Payload(2))
        await observation.pending?.value
        #expect(observation.resolved?.value == 1)
        observation.connect(
            ReadSource(store: store, task: signal), keepLast: true, equals: { $0.value == $1.value },
            onCleanupError: { Issue.record("\($0)") })
        #expect(observation.resolved?.value == 2)
    }

    @Test func pendingObserverDoesNotRetainViewPayloadAfterDisposal() async throws {
        let store = Store()
        let gate = Deferred<Int>()
        let signal = CCState.State(gate.task())
        var observation: ReadObservation<Int>? = connect(store, task: signal)
        weak let lease = observation
        let pending = observation?.pending
        observation = nil
        #expect(lease == nil && !store.isMounted(signal))
        #expect(pending?.isCancelled == true)
        gate.resolve(1)
        await pending?.value
    }

    @Test func reentrantCommandDoesNotOverwriteNewerOperation() throws {
        let store = Store()
        weak var current: LoadableAction<Int, Int, Int>?
        let command = Command<Int, Int> { _, input in
            if input == 1 { _ = try current?(2) }
            return input
        }
        let action = LoadableAction<Int, Int, Int>(
            invoke: { try store.set(command, $0) }, resolve: { .value($0) })
        current = action
        #expect(try action(1) == 1)
        #expect(action.phase.data == 2)
    }
}
