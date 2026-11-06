# Pinned CCState compatibility

Reference: [e7h4n/ccstate](https://github.com/e7h4n/ccstate), core package version **6.1.0**, commit **86f95f2841c15474f08fcfc8e040c078dd2ab093**. The baseline includes every test under `packages/ccstate`, including debug facilities and bundle annotations. It does not silently mix cases from another upstream revision.

[upstream-tests.json](upstream-tests.json) lists every expanded Vitest case with its original file, complete name, stable ID, and disposition. [UpstreamInventory.swift](../Tests/CCStateTests/UpstreamInventory.swift) supplies those IDs and names to the Swift Testing parameterized suite. A missing implementation records a failure. The inventory checker rejects missing, duplicated, or changed reference cases.

| Disposition | Cases | Validation |
| --- | ---: | --- |
| Behavioral ports | 205 | Swift counterparts retain the behavior and assertions, including lifecycle and graph-work bounds. |
| Compile-time enforcement | 2 | Swift rejects `set(computed, ...)` and `watch(command, ...)`; two negative fixtures and a positive control verify the API boundary. The matrix also exercises the permitted counterpart. |
| Native Task adaptations | 3 | Tasks preserve failures for callers to await. Swift has no Node `unhandledRejection` event, so these are explicitly adapted tests, not identical runtime behavior. |
| JavaScript toolchain only | 1 | ESM/CJS `@__NO_SIDE_EFFECTS__` annotations are tested in the unchanged upstream build. Swift library compilation and Release builds are validated separately. |
| **Total** | **211** | **210 Swift matrix entries plus one JS-only bundle test accounted for.** |

The three native Task cases are `promise.01`, `.02`, and `.03`. They deliberately await failures during cleanup and do not install a synthetic global rejection mechanism. The compile-time cases are `ccstate.03` and `watch-listener-prototype.05`.

## Swift translations

- State/computed values retain their Swift types. `Equatable` value types compare by value; reference types compare by identity. Use `equals:` for a different contract. Tests requiring JavaScript object identity use reference payloads. Swift closure identity has no automatic equivalence contract.
- Both JavaScript empty values use optional `nil`; Swift's type system prevents mixing a numeric state with arbitrary runtime types. Primitive JavaScript thrown values in the result tests use typed `Error` carriers so that successful `nil`, failures, and recovery are still tested independently.
- The `get` accessor remains live across suspension. Only the current evaluation can add dependencies. Tests explicitly gate continuations and finish old work last; they do not rely on sleeps or timing thresholds.
- JavaScript async synchronous prefixes use `Task.immediate`. Existing Tasks are returned unchanged. Swift cancellation is cooperative and opt-in; no Task wrapper or Promise implementation is inserted into the core.
- Swift `await` does not always suspend. Writes remain in the synchronous command batch until the first actual suspension, whereas JavaScript `await` always yields to a microtask. Continuation-order tests use explicit gates to establish that boundary deterministically; this port does not add artificial yields to every native await.
- Generator commands use a Swift iterator whose retained command context flushes later writes. Command arguments use a tuple or typed input rather than JavaScript variadic runtime casts.
- Console filtering, lifecycle, and interception are covered using an injectable native line emitter. JavaScript browser console grouping/formatting is not a native API contract.
- Weak-key storage uses signal destruction and weak reverse edges under ARC. Subscription cancellation is explicit; callers must break their own strong capture cycles. Computed getters hold the Store weakly and report `StoreError.storeReleased` after its destruction. Additional Swift-only tests verify store destruction, function-valued computed ownership, and repeated store creation.
- The random diamond test uses a fixed seed (`0xCC57A7E`) to exercise both dependency orders reproducibly. The same 100-layer graph and 99-evaluation assertion are retained.

## SwiftUI adapter

The optional `CCStateSwiftUI` product takes its UI contracts from the **68 tests** in the pinned `packages/react` package. [react-tests.json](react-tests.json) preserves every original file, complete case name, and stable ID. [ReactInventory.swift](../Tests/CCStateSwiftUITests/ReactInventory.swift) drives a parameterized native counterpart suite; an unimplemented case fails. The React inventory guard independently checks the unchanged upstream results and the complete native ID set.

| Reference suite | Cases | Native validation |
| --- | ---: | --- |
| Get and set | 14 | Hosted SwiftUI output, equality, batched invalidation, stable writers, target changes, and missing-provider diagnostics. |
| Item lists | 2 | Hosted `ForEach` identity, row writes, removal, insertion, and filtered derivation. |
| Loadable setters | 8 | Local operation state, errors, target changes, return identity, and stale completion suppression. |
| Loadable reads | 27 | Async transitions, error recovery, shared Tasks, retained snapshots, equality, and target changes. |
| Memory | 2 | Weak references verify ARC release after subscription disposal, including pending Tasks. |
| Read/watch migration | 5 | Read-after-subscribe initialization, synchronous errors, Store replacement, disposal, and shared-Task target races. |
| Resolved reads | 10 | Data projections, pending state, retained data, equality, and target changes. |
| **Total** | **68** | **Every reference case has a native counterpart.** |

Additional tests host `ResolvedValue`, `LoadableStatus`, and `LoadableSetter` in SwiftUI, and verify cleanup error reporting, equality reconfiguration, and pending-observer ownership. Host tests run on macOS through `NSHostingView`; iOS Simulator builds separately verify both library modules. This suite does not execute the application in the Simulator.

Native adaptations are explicit:

- SwiftUI `body` cannot throw into a React error boundary. Synchronous reads and missing providers become `Loadable.hasError`; writers throw to their caller.
- Signals retain static types. A read of a Task uses the `task:` initializer; arbitrary JavaScript primitive rejections use typed Swift errors.
- React DOM, StrictMode remounts, garbage collection, and profiler commits have no identical SwiftUI API. Tests check native view output, Observation invalidation, released subscriptions, ARC, and stale-result ownership instead. The same shared-Task race is exercised without claiming to run React StrictMode.
- `keepLast` retains the previous complete snapshot while another Task is pending, including a previous failure. A new failure replaces previous data. Ordinary resolved reads return `nil` for loading and errors; their projected value retains the full phase.
- Subscriptions belong to SwiftUI's stored view state. They end when that storage is released, which can be later than a temporary disappearance. Disposing a UI observer cancels its waiter and rejects late publication; it never cancels a Task shared through the Store.
- Stable writer objects are scoped to a Store and target. A replacement creates a new writer; escaped plain writers still address their original Store and target. Replaced loadable writers stop publishing local operation status.

Vue, Solid, Svelte, and Babel integrations remain outside this package. Application migration and measured startup/scrolling acceptance are separate from library test coverage.

## Reproduce the upstream baseline

Clone the reference repository, check out the pinned commit, then:

```sh
pnpm install --frozen-lockfile --ignore-scripts
pnpm -F ccstate build
```

Create a Vitest workspace JSON containing the absolute paths to `packages/ccstate` and `packages/react`, then run both original package suites with that workspace:

```sh
pnpm exec vitest run --workspace /absolute/path/ccstate.workspace.json \
  --maxWorkers=4 --minWorkers=1 --reporter=json --outputFile=/absolute/path/upstream-report.json
```

From this Swift repository:

```sh
python3 Scripts/check-compatibility.py --upstream-report /absolute/path/upstream-report.json
python3 Scripts/check-swiftui-compatibility.py --upstream-report /absolute/path/upstream-report.json
```

`bash Scripts/check-upstream.sh /absolute/path/ccstate /absolute/path/upstream-report.json` performs the pinned-revision check, dependency installation, build, and combined 279-case run. `Scripts/import-test-inventory.py` and `Scripts/import-react-inventory.py` regenerate the respective inventories from a successful pinned upstream report. Review any upstream-version change and its test adaptations together; do not regenerate the baseline to hide a failed Swift assertion.
