#if canImport(AppKit)
    import AppKit
    import CCState
    import SwiftUI
    import Testing

    @testable import CCStateSwiftUI

    @MainActor
    final class ViewProbe<Value: Sendable> {
        private(set) var latest: Value?
        private(set) var renders = 0
        private let stream: AsyncStream<Value>
        private let continuation: AsyncStream<Value>.Continuation
        init() { (stream, continuation) = AsyncStream.makeStream() }
        func record(_ value: Value) {
            latest = value
            renders += 1
            continuation.yield(value)
        }
        func next(where predicate: (Value) -> Bool) async -> Value? {
            if let latest, predicate(latest) { return latest }
            for await value in stream { if predicate(value) { return value } }
            Issue.record("The view stream ended before the expected render")
            return nil
        }
        isolated deinit { continuation.finish() }
    }

    @MainActor
    final class ViewHost {
        private let window: NSWindow
        private let view: NSHostingView<AnyView>
        init<Content: View>(@ViewBuilder content: () -> Content) {
            _ = NSApplication.shared
            view = NSHostingView(rootView: AnyView(content()))
            window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 320, height: 200),
                styleMask: [.borderless], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = view
            layout()
        }
        func layout() {
            view.needsLayout = true
            view.layoutSubtreeIfNeeded()
        }
        func replace<Content: View>(@ViewBuilder content: () -> Content) {
            view.rootView = AnyView(content())
            layout()
        }
        func close() {
            replace { EmptyView() }
            window.contentView = nil
            window.close()
        }
    }

    @MainActor
    struct CounterView: View {
        @LoadableValue private var count: Loadable<Int>
        let probe: ViewProbe<String>
        init(_ count: Signal<Int>, probe: ViewProbe<String>) {
            _count = LoadableValue(count)
            self.probe = probe
        }
        var body: some View {
            let text = count.data.map(String.init) ?? String(describing: count.state)
            probe.record(text)
            return Text(text)
        }
    }

    @Suite(.serialized, .timeLimit(.minutes(1)))
    @MainActor
    struct SwiftUIHostTests {
        @Test func viewReadsInjectedStoreAndRefreshes() async throws {
            let store = Store()
            let signal = CCState.State(0)
            let probe = ViewProbe<String>()
            let host = ViewHost { StoreProvider(store) { CounterView(signal, probe: probe) } }
            defer { host.close() }
            #expect(await probe.next { $0 == "0" } == "0")
            #expect(store.isMounted(signal))
            try store.set(signal, 1)
            host.layout()
            #expect(await probe.next { $0 == "1" } == "1")
        }

        @Test func removingViewReleasesSubscription() async throws {
            let store = Store()
            let signal = CCState.State(0)
            let probe = ViewProbe<String>()
            let host = ViewHost { StoreProvider(store) { CounterView(signal, probe: probe) } }
            #expect(await probe.next { $0 == "0" } == "0")
            host.close()
            #expect(!store.isMounted(signal))
        }
    }
#endif
