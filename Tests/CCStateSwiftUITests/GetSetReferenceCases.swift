#if canImport(AppKit)
    import CCState
    import SwiftUI
    import Testing

    @testable import CCStateSwiftUI

    @MainActor
    private struct PayloadView: View {
        @LoadableValue private var value: Loadable<Payload<Int>>
        let probe: ViewProbe<Int>
        init(_ signal: Signal<Payload<Int>>, probe: ViewProbe<Int>) {
            _value = LoadableValue(signal, equals: { $0.value == $1.value })
            self.probe = probe
        }
        var body: some View {
            let number = value.data?.value ?? -1
            probe.record(number)
            return Text(String(number))
        }
    }

    @MainActor
    private struct SumView: View {
        @LoadableValue private var first: Loadable<Int>
        @LoadableValue private var second: Loadable<Int>
        let probe: ViewProbe<Int>
        init(_ a: Signal<Int>, _ b: Signal<Int>, probe: ViewProbe<Int>) {
            _first = LoadableValue(a)
            _second = LoadableValue(b)
            self.probe = probe
        }
        var body: some View {
            let sum = (first.data ?? 0) + (second.data ?? 0)
            probe.record(sum)
            return Text(String(sum))
        }
    }

    @MainActor
    private final class CommandProbe<Return> {
        var writer: CommandWriter<Return, Void>?
        var press: (() throws -> Return)?
    }

    @MainActor
    private struct CommandCounter<Return>: View {
        @LoadableValue private var count: Loadable<Int>
        @CommandSetter private var invoke: CommandWriter<Return, Void>
        let probe: ViewProbe<Int>
        let action: CommandProbe<Return>
        init(_ count: Signal<Int>, command: Command<Return, Void>, probe: ViewProbe<Int>, action: CommandProbe<Return>)
        {
            _count = LoadableValue(count)
            _invoke = CommandSetter(command)
            self.probe = probe
            self.action = action
        }
        var body: some View {
            probe.record(count.data ?? -1)
            let writer = invoke
            action.writer = writer
            action.press = { try writer() }
            return Button(String(count.data ?? -1)) {
                do { _ = try writer() } catch { Issue.record("Unexpected action error: \(error)") }
            }
        }
    }

    @MainActor
    private struct StateWriterView: View {
        @SignalSetter private var set: StateWriter<String>
        @LoadableValue private var value: Loadable<String>
        let writers: ViewProbe<StateWriter<String>>
        init(_ signal: CCState.State<String>, writers: ViewProbe<StateWriter<String>>) {
            _set = SignalSetter(signal)
            _value = LoadableValue(signal)
            self.writers = writers
        }
        var body: some View {
            writers.record(set)
            return Text(value.data ?? "error")
        }
    }

    @MainActor
    private struct CommandWriterView: View {
        @CommandSetter private var invoke: CommandWriter<Void, String>
        let writers: ViewProbe<CommandWriter<Void, String>>
        init(_ command: Command<Void, String>, writers: ViewProbe<CommandWriter<Void, String>>) {
            _invoke = CommandSetter(command)
            self.writers = writers
        }
        var body: some View {
            writers.record(invoke)
            return Text("command")
        }
    }

    @MainActor
    private struct PhaseView: View {
        @LoadableValue private var value: Loadable<Int>
        let probe: ViewProbe<Loadable<Int>>
        init(_ signal: Signal<Int>, probe: ViewProbe<Loadable<Int>>) {
            _value = LoadableValue(signal)
            self.probe = probe
        }
        var body: some View {
            probe.record(value)
            return Text(String(describing: value.state))
        }
    }

    @MainActor
    func runGetSetReference(_ test: ReactReferenceCase) async throws {
        let store = Store()
        switch test.id {
        case "get-and-set.01", "get-and-set.02":
            let source = CCState.State(0)
            let probe = ViewProbe<String>()
            let target: Signal<Int> = test.id == "get-and-set.01" ? source : Computed { try $0(source) * 2 }
            let host = ViewHost { StoreProvider(store) { CounterView(target, probe: probe) } }
            defer { host.close() }
            #expect(await probe.next { $0 == "0" } == "0")
            try store.set(source, 1)
            host.layout()
            let expected = test.id == "get-and-set.01" ? "1" : "2"
            #expect(await probe.next { $0 == expected } == expected)
            let renders = probe.renders
            try store.set(source, 1)
            host.layout()
            #expect(probe.renders == renders)
        case "get-and-set.03":
            let source = CCState.State(Payload(1))
            let probe = ViewProbe<Int>()
            let host = ViewHost { StoreProvider(store) { PayloadView(source, probe: probe) } }
            defer { host.close() }
            #expect(await probe.next { $0 == 1 } == 1)
            let renders = probe.renders
            try store.set(source, Payload(1))
            host.layout()
            #expect(probe.renders == renders)
            try store.set(source, Payload(2))
            host.layout()
            #expect(await probe.next { $0 == 2 } == 2)
            #expect(probe.renders == renders + 1)
        case "get-and-set.04":
            let source = CCState.State(0)
            let probe = ViewProbe<Int>()
            let action = CommandProbe<Void>()
            let command = Command<Void, Void> { try $0.set(source, update: { $0 + 1 }) }
            let host = ViewHost {
                StoreProvider(store) { CommandCounter(source, command: command, probe: probe, action: action) }
            }
            defer { host.close() }
            #expect(await probe.next { $0 == 0 } == 0)
            try action.press!()
            host.layout()
            #expect(await probe.next { $0 == 1 } == 1)
            try action.press!()
            host.layout()
            #expect(await probe.next { $0 == 2 } == 2)
        case "get-and-set.05":
            let a = CCState.State(0)
            let b = CCState.State(0)
            let probe = ViewProbe<Int>()
            let host = ViewHost { StoreProvider(store) { SumView(a, b, probe: probe) } }
            defer { host.close() }
            #expect(await probe.next { $0 == 0 } == 0)
            let renders = probe.renders
            try store.set(a, 1)
            try store.set(b, 2)
            host.layout()
            #expect(await probe.next { $0 == 3 } == 3)
            #expect(probe.renders == renders + 1)
        case "get-and-set.06", "get-and-set.07":
            let a = CCState.State(0)
            let b = CCState.State(10)
            let probe = ViewProbe<String>()
            let first: Signal<Int> = test.id == "get-and-set.06" ? a : Computed { try $0(a) }
            let second: Signal<Int> = test.id == "get-and-set.06" ? b : Computed { try $0(b) }
            let host = ViewHost { StoreProvider(store) { CounterView(first, probe: probe) } }
            defer { host.close() }
            #expect(await probe.next { $0 == "0" } == "0")
            host.replace { StoreProvider(store) { CounterView(second, probe: probe) } }
            #expect(await probe.next { $0 == "10" } == "10")
            #expect(!store.isMounted(first) && store.isMounted(second))
            try store.set(a, 99)
            host.layout()
            #expect(probe.latest == "10")
            try store.set(b, 11)
            host.layout()
            #expect(await probe.next { $0 == "11" } == "11")
        case "get-and-set.08", "get-and-set.14":
            let first = CCState.State("A0")
            let second = CCState.State("B0")
            let writers = ViewProbe<StateWriter<String>>()
            let host = ViewHost { StoreProvider(store) { StateWriterView(first, writers: writers) } }
            defer { host.close() }
            let original = try #require(await writers.next { _ in true })
            if test.id == "get-and-set.14" {
                try store.set(first, "A1")
                host.layout()
                #expect(writers.latest === original)
                try original.update { $0 + "!" }
                #expect(try store.get(first) == "A1!")
            } else {
                host.replace { StoreProvider(store) { StateWriterView(second, writers: writers) } }
                let current = try #require(await writers.next { $0 !== original })
                try current("updated")
                #expect(try store.get(first) == "A0" && store.get(second) == "updated")
                try original("old target")
                #expect(try store.get(first) == "old target" && store.get(second) == "updated")
            }
        case "get-and-set.09":
            let first = CCState.State("A0")
            let second = CCState.State("B0")
            let a = Command<Void, String> { try $0.set(first, $1) }
            let b = Command<Void, String> { try $0.set(second, $1) }
            let writers = ViewProbe<CommandWriter<Void, String>>()
            let host = ViewHost { StoreProvider(store) { CommandWriterView(a, writers: writers) } }
            defer { host.close() }
            let original = try #require(await writers.next { _ in true })
            host.replace { StoreProvider(store) { CommandWriterView(b, writers: writers) } }
            let current = try #require(await writers.next { $0 !== original })
            try current("updated")
            #expect(try store.get(first) == "A0" && store.get(second) == "updated")
        case "get-and-set.10":
            let source = CCState.State(0)
            let gate = Deferred<Void>()
            let probe = ViewProbe<Int>()
            let command = asyncCommand { (context: CommandContext, _: Void) in
                try await gate.value()
                try context.set(source, update: { $0 + 1 })
            }
            let action = CommandProbe<Task<Void, Error>>()
            let host = ViewHost {
                StoreProvider(store) { CommandCounter(source, command: command, probe: probe, action: action) }
            }
            defer { host.close() }
            #expect(await probe.next { $0 == 0 } == 0)
            let pending = try action.press!()
            gate.resolve(())
            try await pending.value
            host.layout()
            #expect(await probe.next { $0 == 1 } == 1)
        case "get-and-set.11":
            let source = CCState.State(0)
            let gate = Deferred<Void>()
            let probe = ViewProbe<Int>()
            let action = CommandProbe<Void>()
            var owned: Task<Void, Error>?
            let command = Command<Void, Void> { context in
                owned = Task.immediate { @MainActor in
                    try await gate.value()
                    try context.set(source, update: { $0 + 1 })
                }
            }
            let host = ViewHost {
                StoreProvider(store) { CommandCounter(source, command: command, probe: probe, action: action) }
            }
            defer { host.close() }
            #expect(await probe.next { $0 == 0 } == 0)
            try action.press!()
            gate.resolve(())
            try await owned!.value
            host.layout()
            #expect(await probe.next { $0 == 1 } == 1)
        case "get-and-set.12":
            let source = CCState.State(0)
            let probe = ViewProbe<Loadable<Int>>()
            let host = ViewHost { PhaseView(source, probe: probe) }
            defer { host.close() }
            let failure = try #require(await probe.next { $0.state == .hasError })
            #expect(failure.error as? StoreObservationError == .missingStore)
        case "get-and-set.13":
            let source = CCState.State(0)
            let probe = ViewProbe<String>()
            let host = ViewHost { StoreProvider(store) { CounterView(source, probe: probe) } }
            #expect(await probe.next { $0 == "0" } == "0")
            #expect(store.isMounted(source))
            #expect(store.getReadDependents(source).children.isEmpty)
            host.close()
            #expect(!store.isMounted(source) && store.getReadDependents(source).children.isEmpty)
        default: Issue.record("Missing get/set reference \(test.id)")
        }
    }
#endif
