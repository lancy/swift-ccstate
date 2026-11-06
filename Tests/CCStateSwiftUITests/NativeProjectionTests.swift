#if canImport(AppKit)
    import CCState
    import SwiftUI
    import Testing

    @testable import CCStateSwiftUI

    @MainActor
    private struct AsyncValueView: View {
        @LoadableValue private var value: Loadable<Int>
        let probe: ViewProbe<String>
        init(_ signal: Signal<Task<Int, Error>>, probe: ViewProbe<String>) {
            _value = LoadableValue(task: signal)
            self.probe = probe
        }
        var body: some View {
            let text = value.data.map(String.init) ?? String(describing: value.state)
            probe.record(text)
            return Text(text)
        }
    }

    @MainActor
    private struct AsyncResolvedView: View {
        @ResolvedValue private var value: Int?
        let probe: ViewProbe<String>
        let showStatus: Bool
        init(_ signal: Signal<Task<Int, Error>>, keepLast: Bool, showStatus: Bool = false, probe: ViewProbe<String>) {
            _value = ResolvedValue(task: signal, keepLast: keepLast)
            self.probe = probe
            self.showStatus = showStatus
        }
        var body: some View {
            let text = value.map(String.init) ?? (showStatus ? String(describing: $value.state) : "missing")
            probe.record(text)
            return Text(text)
        }
    }

    @MainActor
    private struct StatusView: View {
        @LoadableStatus<Int> private var state: LoadableState
        let probe: ViewProbe<LoadableState>
        init(_ signal: Signal<Int>, probe: ViewProbe<LoadableState>) {
            _state = LoadableStatus(signal)
            self.probe = probe
        }
        var body: some View {
            probe.record(state)
            return Text(String(describing: state))
        }
    }

    @MainActor
    private struct OperationView: View {
        @LoadableSetter private var save: LoadableAction<Int, Void, Task<Int, Error>>
        let actions: ViewProbe<LoadableAction<Int, Void, Task<Int, Error>>>
        let phases: ViewProbe<OperationState>
        init(
            _ command: Command<Task<Int, Error>, Void>, actions: ViewProbe<LoadableAction<Int, Void, Task<Int, Error>>>,
            phases: ViewProbe<OperationState>
        ) {
            _save = LoadableSetter(task: command)
            self.actions = actions
            self.phases = phases
        }
        var body: some View {
            actions.record(save)
            phases.record(save.phase.state)
            return Text(String(describing: save.phase.state))
        }
    }

    @Suite(.serialized, .timeLimit(.minutes(1)))
    @MainActor
    struct NativeProjectionTests {
        @Test func resolvedWrapperKeepsDataDuringRefreshAndExposesErrors() async throws {
            let store = Store()
            let first = Deferred<Int>()
            let signal = CCState.State(first.task())
            let probe = ViewProbe<String>()
            let host = ViewHost {
                StoreProvider(store) { AsyncResolvedView(signal, keepLast: true, showStatus: true, probe: probe) }
            }
            defer { host.close() }
            #expect(await probe.next { $0 == "loading" } == "loading")
            first.resolve(1)
            #expect(await probe.next { $0 == "1" } == "1")
            let next = Deferred<Int>()
            try store.set(signal, next.task())
            host.layout()
            #expect(probe.latest == "1")
            next.reject(TestFailure("offline"))
            #expect(await probe.next { $0 == "hasError" } == "hasError")
        }

        @Test func statusWrapperDoesNotRenderForPayloadOnlyChanges() async throws {
            let store = Store()
            let signal = CCState.State(1)
            let probe = ViewProbe<LoadableState>()
            let host = ViewHost { StoreProvider(store) { StatusView(signal, probe: probe) } }
            defer { host.close() }
            #expect(await probe.next { $0 == .hasData } == .hasData)
            let renders = probe.renders
            try store.set(signal, 2)
            host.layout()
            #expect(probe.renders == renders)
        }

        @Test func providerReplacementIgnoresLateRejection() async throws {
            let first = Deferred<Int>()
            let second = Deferred<Int>()
            let signal = CCState.State(first.task())
            let a = Store()
            let b = Store()
            let probe = ViewProbe<String>()
            try b.set(signal, second.task())
            let host = ViewHost { StoreProvider(a) { AsyncValueView(signal, probe: probe) } }
            defer { host.close() }
            #expect(await probe.next { $0 == "loading" } == "loading")
            host.replace { StoreProvider(b) { AsyncValueView(signal, probe: probe) } }
            #expect(!a.isMounted(signal) && b.isMounted(signal))
            second.resolve(2)
            #expect(await probe.next { $0 == "2" } == "2")
            let renders = probe.renders
            let original = try a.get(signal)
            first.reject(TestFailure("obsolete"))
            await #expect(throws: TestFailure.self) { try await original.value }
            host.layout()
            #expect(probe.latest == "2" && probe.renders == renders)
        }

        @Test func loadableSetterRendersAndReleasesOnlyItsObservation() async throws {
            let store = Store()
            let gate = Deferred<Int>()
            let raw = gate.task()
            let command = Command<Task<Int, Error>, Void> { _ in raw }
            let actions = ViewProbe<LoadableAction<Int, Void, Task<Int, Error>>>()
            let phases = ViewProbe<OperationState>()
            let host = ViewHost { StoreProvider(store) { OperationView(command, actions: actions, phases: phases) } }
            #expect(await phases.next { $0 == .idle } == .idle)
            let action = try #require(actions.latest)
            let returned = try action()
            #expect(returned == raw)
            host.layout()
            #expect(await phases.next { $0 == .loading } == .loading)
            #expect(actions.latest === action)
            let waiter = action.pending
            host.close()
            #expect(waiter?.isCancelled == true)
            #expect(!raw.isCancelled)
            gate.resolve(42)
            await waiter?.value
            #expect(try await returned.value == 42)
            #expect(action.phase.state == .loading)
        }

        @Test func resolvedDataOnlyProjectionSkipsLoadingAndErrorInvalidations() async throws {
            let store = Store()
            let first = Deferred<Int>()
            let signal = CCState.State(first.task())
            let probe = ViewProbe<String>()
            let host = ViewHost { StoreProvider(store) { AsyncResolvedView(signal, keepLast: false, probe: probe) } }
            defer { host.close() }
            #expect(await probe.next { $0 == "missing" } == "missing")
            let renders = probe.renders
            first.reject(TestFailure())
            await #expect(throws: TestFailure.self) { try await store.get(signal).value }
            host.layout()
            #expect(probe.renders == renders && probe.latest == "missing")
        }
    }
#endif
