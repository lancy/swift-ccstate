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

React, Vue, Solid, Svelte, and Babel packages target their own runtimes and are outside this Swift **core** port. A native UI adapter requires its own observation, ownership, stale-settlement, and view-lifecycle acceptance before application migration. Core-test coverage does not establish smooth scrolling or faster startup.

## Reproduce the upstream baseline

Clone the reference repository, check out the pinned commit, then:

```sh
pnpm install --frozen-lockfile --ignore-scripts
pnpm -F ccstate build
```

Create a Vitest workspace JSON containing the absolute path to `packages/ccstate`, then run the original core package tests with that workspace:

```sh
pnpm exec vitest run --workspace /absolute/path/ccstate.workspace.json \
  --maxWorkers=4 --minWorkers=1 --reporter=json --outputFile=/absolute/path/upstream-report.json
```

From this Swift repository:

```sh
python3 Scripts/check-compatibility.py --upstream-report /absolute/path/upstream-report.json
```

`Scripts/import-test-inventory.py` regenerates the inventory from a successful pinned upstream report. Review any upstream-version change and its test adaptations together; do not regenerate the baseline to hide a failed Swift assertion.
