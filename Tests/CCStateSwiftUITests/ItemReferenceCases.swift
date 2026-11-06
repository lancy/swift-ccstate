#if canImport(AppKit)
    import CCState
    import SwiftUI
    import Testing

    @testable import CCStateSwiftUI

    private struct Item: Equatable {
        var text: String
        var checked: Bool
    }

    @MainActor
    private struct ItemRow: View {
        @LoadableValue private var value: Loadable<Item>
        let probe: ViewProbe<String>
        init(_ item: Signal<Item>, probe: ViewProbe<String>) {
            _value = LoadableValue(item)
            self.probe = probe
        }
        var body: some View {
            let text = value.data.map { "\($0.text) checked: \($0.checked ? "yes" : "no")" } ?? "loading"
            probe.record(text)
            return Text(text)
        }
    }

    @MainActor
    private struct ItemList: View {
        @LoadableValue private var items: Loadable<[CCState.State<Item>]>
        let probes: [ViewProbe<String>]
        init(_ items: Signal<[CCState.State<Item>]>, probes: [ViewProbe<String>]) {
            _items = LoadableValue(items)
            self.probes = probes
        }
        var body: some View {
            VStack {
                ForEach(items.data ?? [], id: \.id) { item in
                    ItemRow(item, probe: probes[Int(item.initialValue.text.dropFirst(4))! - 1])
                }
            }
        }
    }

    @MainActor
    func runItemsReference(_ test: ReactReferenceCase) async throws {
        let store = Store()
        let items = CCState.State<[CCState.State<Item>]>([])
        let filter = CCState.State(false)
        let filtered = computed { get in
            let all = try get(items)
            if try get(filter) { return try all.filter { try get($0).checked } }
            return all
        }
        let target: Signal<[CCState.State<Item>]> = test.id == "items.01" ? items : filtered
        let probes = (0..<3).map { _ in ViewProbe<String>() }
        let host = ViewHost { StoreProvider(store) { ItemList(target, probes: probes) } }
        defer { host.close() }
        let writer = StateWriter(store: store, signal: items)
        if test.id == "items.02" {
            try store.set(filter, true)
            host.layout()
        }
        let first = CCState.State(Item(text: "item1", checked: false))
        try writer.update { $0 + [first] }
        host.layout()
        if test.id == "items.02" {
            // Filtering still observes the item's checked value; no row is rendered.
            #expect(probes[0].latest == nil)
            try store.set(filter, false)
            host.layout()
            #expect(await probes[0].next { $0 == "item1 checked: no" } == "item1 checked: no")
            return
        }
        #expect(await probes[0].next { $0 == "item1 checked: no" } == "item1 checked: no")
        let second = CCState.State(Item(text: "item2", checked: false))
        try writer.update { $0 + [second] }
        host.layout()
        #expect(await probes[1].next { $0 == "item2 checked: no" } == "item2 checked: no")
        try StateWriter(store: store, signal: second).update { Item(text: $0.text, checked: !$0.checked) }
        host.layout()
        #expect(await probes[1].next { $0 == "item2 checked: yes" } == "item2 checked: yes")
        try writer.update { $0.filter { $0 !== first } }
        host.layout()
        #expect(!store.isMounted(first))
        #expect(store.isMounted(second))
        let third = CCState.State(Item(text: "item3", checked: false))
        try writer.update { $0 + [third] }
        host.layout()
        #expect(await probes[2].next { $0 == "item3 checked: no" } == "item3 checked: no")
        #expect(probes[1].latest == "item2 checked: yes")
    }
#endif
