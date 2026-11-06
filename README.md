# CCState for Swift

A Swift-native port of [CCState](https://github.com/e7h4n/ccstate): independent stores, lazy computed values, dynamic dependencies, and commands with synchronous write batching. No package dependencies.

Repository: `swift-ccstate`. Library products and imports: `CCState` and the optional `CCStateSwiftUI` adapter.

**Experimental.** The core and SwiftUI adapter are based on CCState **6.1.0**, commit [`86f95f2`](https://github.com/e7h4n/ccstate/commit/86f95f2841c15474f08fcfc8e040c078dd2ab093). Application migration and performance acceptance remain separate work. This package does not claim source compatibility with TypeScript or support for React, Vue, Solid, Svelte, or Babel.

## Requirements

- Swift 6.2 or later, using Swift 6 language mode.
- iOS 26, macOS 26, tvOS 26, or watchOS 26 or later.
- Graph reads, writes, subscriptions, and evaluation callbacks run on `MainActor`. Asynchronous I/O can suspend normally; move CPU-intensive work to an appropriate executor.

Swift 6.2 provides `Task.immediate`, which preserves the synchronous prefix of an async computation or command before its first actual suspension. The same requirement also permits isolated destruction of weak-key cache entries.

## Installation

The API is experimental and has no stable release tag yet. Pin an audited revision:

```swift
.package(url: "https://github.com/lancy/swift-ccstate.git", revision: "<commit>")
```

Add the `CCState` library product to your target. SwiftUI targets also add `CCStateSwiftUI`; the core has no SwiftUI dependency.

## Basic use

```swift
import CCState

@MainActor
func example() throws {
    let store = Store()
    let count = State(0)
    let doubled = Computed { try $0(count) * 2 }
    let increment = Command<Void, Void> { context in
        try context.set(count, update: { $0 + 1 })
    }

    print(try store.get(doubled)) // 0
    let subscription = try store.watch(doubled) {
        print(try store.get(doubled))
    }
    try store.set(increment) // prints 2
    try subscription.cancel()
}
```

The lowercase `state`, `computed`, `command`, and `createStore` factories are also available. Swift command arguments use a single typed input; use a tuple or struct for several arguments.

- `get` evaluates a computed lazily and caches its result until its actual dependencies change.
- `watch` establishes the initial dependencies without calling the listener initially. Read the initial value explicitly.
- Each synchronous command batches its internal writes. Explicit intermediate reads remain fresh; later writes through an escaped or post-suspension context flush individually.
- `watch` returns an explicit, idempotent `Subscription`. Call `cancel()` at the owning lifecycle boundary. Cancellation releases captured signals and listeners even if the cancelled handle is retained.
- Reuse a `Listener` instance when the same callback watches several roots and must be deduplicated across them.
- Keep the owning Store alive while using its graph. A retained computed getter reports `StoreError.storeReleased` after owner destruction; function-valued computed caches do not keep their own Store alive.
- Errors from reads are cached separately from successful optional values. Notification continues through all listeners, then throws `ListenerErrors` if callbacks failed.

## Shared asynchronous values

```swift
@MainActor
func sharedRequest() async throws {
    let store = Store()
    let reload = State(0)
    let message = computedTask { get, options in
        _ = try get(reload)
        let signal = options.signal
        await Task.yield()
        try signal.checkCancellation()
        return "Hello"
    }

    let first = try store.get(message)
    let second = try store.get(message)
    assert(first == second) // One cached Task, shared by both consumers.
    print(try await first.value)
    print(try await second.value)
}
```

Tasks are ordinary cached values. The store neither wraps their results nor automatically cancels them. `computedTask` starts work with `Task.immediate`; direct `Computed<Task<..., ...>>` also works when returning an existing task or collecting dependencies synchronously before creating it.

Each evaluation has a stable, lazily created `options.signal`. Reevaluation cancels the previous signal, including when the new branch throws or never asks for a signal. An obsolete continuation cannot attach dependencies to the current evaluation. Unsubscribing a listener does not cancel an evaluation's signal. Use `onCancel` to forward evaluation cancellation to an operation that supports it, or check it explicitly after suspension. An independent task owner can also use native task cancellation. Do not let one transient consumer cancel work shared by unrelated consumers.

`asyncCommand` starts its body synchronously and returns a `Task`. Its synchronous prefix batches writes; each later context write flushes independently. Cancellation and error observation remain with the caller.

## SwiftUI

Use `StoreProvider` to supply an explicitly owned Store. Typed property wrappers subscribe to signals and expose stable writers. Keep signal definitions outside `body` so multiple views read the same cached resource.

```swift
import CCState
import CCStateSwiftUI
import SwiftUI

@MainActor
enum CounterSignals {
    static let count = CCState.State(0)
    static let increment = Command<Void, Void> { context in
        try context.set(count, update: { $0 + 1 })
    }
}

@MainActor
struct CounterView: View {
    @LoadableValue(CounterSignals.count) private var count
    @CommandSetter(CounterSignals.increment) private var increment
    @SwiftUI.State private var failure: String?

    var body: some View {
        VStack {
            switch count {
            case .loading: ProgressView()
            case .hasData(let value): Text("Count: \(value)")
            case .hasError(let error): Text(error.localizedDescription)
            }
            Button("Increment") {
                do { try increment() }
                catch { failure = error.localizedDescription }
            }
            if let failure { Text(failure) }
        }
    }
}

@MainActor
struct CounterRoot: View {
    @SwiftUI.State private var store = Store()

    var body: some View {
        StoreProvider(store) { CounterView() }
    }
}
```

For shared asynchronous resources use `@LoadableValue(task:)` or `@ResolvedValue(task:keepLast:)`. The adapter observes the Store's original Task; removing a view releases its subscription and ignores late results without cancelling shared work. Read the [SwiftUI guide](Documentation/SwiftUI.md) for all wrappers, equality, error handling, and lifetime rules.

## Compatibility and verification

The [compatibility inventory](Compatibility/README.md) accounts for all **211 upstream core-package tests**: 205 behavioral ports, two stronger compile-time constraints, three explicit native Task adaptations, and one JavaScript bundling-only test. The original upstream package tests are run unchanged as a separate reference check. Passing the original TypeScript suite alone does not verify this Swift implementation.

The Swift compatibility matrix has 210 entries, with additional native lifetime tests. Two negative compiler fixtures verify that computed values cannot be written and commands cannot be observed. The Promise adaptations do **not** claim to reproduce Node's process-level `unhandledRejection` events. Swift values use `Equatable`, reference values use identity, and JavaScript `null`/`undefined` become typed Swift optionals. See the compatibility notes before assuming identical runtime behavior.

The SwiftUI adapter has native counterparts for all **68 pinned `ccstate-react` tests**, plus native hosting, projection, cleanup, and ownership tests. CI runs the unchanged upstream core and React tests, verifies both inventories, tests Debug and Release, type-checks the public SwiftUI API, and builds for iOS Simulator. React DOM, StrictMode, and profiler commit counts are translated into native observation, view output, and ARC checks; passing this suite does not establish faster application startup or scrolling.

```sh
swift test -Xswiftc -warnings-as-errors
bash Scripts/check-negative-compilation.sh
python3 Scripts/check-compatibility.py
python3 Scripts/check-swiftui-compatibility.py
swift build --configuration release -Xswiftc -warnings-as-errors
```

Optimized tests that include graph-work counters use `swift test --configuration release -Xswiftc -DCCSTATE_TESTING`. Counters are absent from normal Release builds.

## Attribution

The core algorithm and behavioral tests are adapted from [e7h4n/ccstate](https://github.com/e7h4n/ccstate), MIT licensed. CCState credits [Jotai](https://github.com/pmndrs/jotai) for inspiration, source snippets, and test cases. Original notices are retained in [LICENSE](LICENSE) and [LICENSES/Jotai.txt](LICENSES/Jotai.txt).
