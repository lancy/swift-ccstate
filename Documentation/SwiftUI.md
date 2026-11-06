# Using CCState with SwiftUI

Add both `CCState` and `CCStateSwiftUI` products to your app target. The adapter is optional and introduces no third-party dependencies. Its Store access and UI observation run on `MainActor`.

## Provider and ownership

Create a Store at the application or session boundary and pass it to `StoreProvider(store) { ... }`. The provider injects the supplied instance through the environment; it never creates another cache. Nested providers can supply a different Store. The equivalent direct environment API is `.environment(\.ccstateStore, store)`.

Keep State, Computed, and Command definitions stable, outside `body`. Put derived values and request creation in the graph, and semantic actions in commands. Multiple views observing the same computed in the same Store share its cached result or Task. The adapter does not introduce a second request cache or a view model per resource.

SwiftUI's stored view state owns each subscription. Replacing the provider or signal detaches the old subscription and reads the new target after subscribing. Releasing view storage detaches it too. A view temporarily hidden or retained by navigation may keep its storage and subscription alive.

## Reading

| Wrapper | Result | React reference |
| --- | --- | --- |
| `@LoadableValue(signal)` | `Loadable<Value>` | Synchronous `useGet`, with explicit error values. |
| `@LoadableValue(task: signal)` | `Loadable<Value>` | `useLoadable`. |
| `@LoadableValue(task: signal, keepLast: true)` | Previous phase during refresh. | `useLastLoadable`. |
| `@ResolvedValue(signal)` or `@ResolvedValue(task: signal)` | `Value?`; `$property` exposes the full `Loadable<Value>`. | `useResolved`. |
| `@ResolvedValue(task: signal, keepLast: true)` | Previous data during refresh. | `useLastResolved`. |
| `@LoadableStatus(task: signal)` | `LoadableState` without payload invalidations. | `useLoadableState`. |

`Loadable` has `.loading`, `.hasData(Value)`, and `.hasError(any Error)` cases. Its `.state`, `.data`, and `.error` accessors are useful for simple projections; switch over the cases when success can itself contain `nil`.

```swift
@ResolvedValue(task: ProfileSignals.profile, keepLast: true) private var profile
@LoadableStatus(task: ProfileSignals.profile) private var profileStatus

// In body:
// Text(profile?.displayName ?? "Loading…")
// if let error = $profile.error { Text(error.localizedDescription) }
```

The signal above must have type `Signal<Task<Profile, Failure>>` for a `Sendable` Profile and an Error-conforming Failure. `computedTask` produces this form. Omitting `task:` instead observes the Task itself as an ordinary value.

`keepLast` retains the entire previous phase during the next pending request. This includes a previous error; a new error always replaces previous data. It does not manufacture success after a failure. An ordinary resolved projection returns `nil` while loading or failed; read `$property` when the UI needs that distinction.

Synchronous reads and retained async data accept `equals:`. Defaults match the core: value equality for Equatable values and identity for reference values. Equal retained results keep the old snapshot. `LoadableStatus` only invalidates for phase transitions; `ResolvedValue` only invalidates for data changes unless its projected phase is also read.

For runtime targets, initialize the wrapper's backing storage in your View initializer. Spell the generic argument when the wrapped type alone cannot infer it:

```swift
@LoadableStatus<Profile> private var status: LoadableState

init(profile: Signal<Task<Profile, any Error>>) {
    _status = LoadableStatus(task: profile)
}
```

## Writing

| Wrapper | Handle | Behavior |
| --- | --- | --- |
| `@SignalSetter(state)` | `StateWriter<Value>` | `try writer(value)` or `try writer.update { ... }`. |
| `@CommandSetter(command)` | `CommandWriter<Value, Input>` | `try writer(input)` returns the original command result. Omit input for Void commands. |
| `@LoadableSetter(command)` or `@LoadableSetter(task: command)` | `LoadableAction<Value, Input, Return>` | Calls the command and exposes local `.phase`. |
| `@LoadableSetter(state)` | `LoadableAction<Void, Input, Void>` | Writes a value and records successful completion. |

Writers are stable reference objects while the Store and target are unchanged. They require no read subscription. An escaped plain writer still targets its original Store and signal after its view changes target. Prefer commands when an action updates several signals, so the core batches those writes.

Loadable setters correspond to upstream's experimental `useLoadableSet`. Their phase is `.idle`, `.loading`, `.hasData(Value)`, or `.hasError(any Error)`. Synchronous invocation failures throw to the caller; asynchronous failures become the phase's error. Calling the handle returns the command's original value or Task without wrapping it:

```swift
@LoadableSetter(task: ProfileSignals.save) private var save

// From an action that handles synchronous errors:
// let originalTask = try save(input)
// The view can read save.phase; a caller can also await originalTask.value.
```

A later invocation invalidates publication from earlier work. Target changes and view-storage disposal also stop the old handle's local observation; a replacement handle begins at `.idle`. They do not cancel the command's Task or undo its writes. Cancellation of business work belongs to its explicit owner.

## Errors and cancellation

A missing provider becomes `StoreObservationError.missingStore`: reads expose `.hasError`, and writers throw. SwiftUI has no React error boundary for throwing from `body`, so reads always have an explicit result.

Unexpected subscription cleanup failures are reported through the provider's optional `onCleanupError:` callback, or privately logged with OSLog by default. Regular resource and command errors remain in their respective result or throwing API.

Each asynchronous read waits for the shared Task and checks subscription identity before publishing. Changing target, invoking again, or releasing storage cancels only this UI waiter. The underlying Task remains available to other consumers. Use the core evaluation cancellation signal or the original Task owner's cancellation path for request cancellation; a disappearing row must not cancel another screen's shared request.

See the [compatibility notes](../Compatibility/README.md#swiftui-adapter) for the pinned test inventory and explicit differences from React rendering and JavaScript scheduling.
