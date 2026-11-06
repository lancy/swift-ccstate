// Generated from the pinned, unchanged ccstate-react test report.
let reactReferenceCases: [ReactReferenceCase] = [
    ReactReferenceCase(id: "get-and-set.01", name: "react using ccstate in react"),
    ReactReferenceCase(id: "get-and-set.02", name: "react computed should re-render"),
    ReactReferenceCase(
        id: "get-and-set.03", name: "react useGet skips commits when equalityFn considers a new value equal"),
    ReactReferenceCase(id: "get-and-set.04", name: "react user click counter should increment"),
    ReactReferenceCase(id: "get-and-set.05", name: "react two atom changes should re-render once"),
    ReactReferenceCase(
        id: "get-and-set.06", name: "react subscribes to a new atom when the useGet atom argument changes"),
    ReactReferenceCase(
        id: "get-and-set.07", name: "react subscribes to a new computed when the useGet atom argument changes"),
    ReactReferenceCase(
        id: "get-and-set.08", name: "react useSet writes to a new state when the signal argument changes"),
    ReactReferenceCase(
        id: "get-and-set.09", name: "react useSet invokes a new command when the signal argument changes"),
    ReactReferenceCase(id: "get-and-set.10", name: "react async callback will trigger rerender"),
    ReactReferenceCase(id: "get-and-set.11", name: "react floating promise trigger rerender"),
    ReactReferenceCase(id: "get-and-set.12", name: "react throw error if no store provide"),
    ReactReferenceCase(id: "get-and-set.13", name: "react will unmount when component cleanup"),
    ReactReferenceCase(id: "get-and-set.14", name: "useSet should be stable"),
    ReactReferenceCase(id: "items.01", name: "remove an item, then add another"),
    ReactReferenceCase(id: "items.02", name: "add an item with filtered list"),
    ReactReferenceCase(id: "loadable-set.01", name: "convert a async command to loadable"),
    ReactReferenceCase(id: "loadable-set.02", name: "async command reject turns into hasError"),
    ReactReferenceCase(id: "loadable-set.03", name: "sync command resolves immediately to hasData"),
    ReactReferenceCase(id: "loadable-set.04", name: "state atom setter transitions to hasData"),
    ReactReferenceCase(
        id: "loadable-set.05", name: "state atom setter writes to a new atom when the signal argument changes"),
    ReactReferenceCase(
        id: "loadable-set.06", name: "command setter invokes a new command when the signal argument changes"),
    ReactReferenceCase(id: "loadable-set.07", name: "second invoke cancels first pending promise"),
    ReactReferenceCase(id: "loadable-set.08", name: "invoke return value is identical to command return value"),
    ReactReferenceCase(id: "loadable.01", name: "convert promise to loadable"),
    ReactReferenceCase(id: "loadable.02", name: "useLoadableState only commits when the loadable state changes"),
    ReactReferenceCase(id: "loadable.03", name: "useLoadableState commits once for each async state transition"),
    ReactReferenceCase(id: "loadable.04", name: "reset promise atom will reset loadable"),
    ReactReferenceCase(id: "loadable.05", name: "switchMap"),
    ReactReferenceCase(id: "loadable.06", name: "loadable turns suspense into values"),
    ReactReferenceCase(id: "loadable.07", name: "loadable turns errors into values"),
    ReactReferenceCase(id: "loadable.08", name: "loadable turns primitive throws into values"),
    ReactReferenceCase(id: "loadable.09", name: "loadable goes back to loading after re-fetch"),
    ReactReferenceCase(id: "loadable.10", name: "loadable can recover from error"),
    ReactReferenceCase(
        id: "loadable.11", name: "loadable of a derived async atom does not trigger infinite loop (#1114)"),
    ReactReferenceCase(
        id: "loadable.12", name: "loadable of a derived async atom with error does not trigger infinite loop (#1330)"),
    ReactReferenceCase(
        id: "loadable.13",
        name: "does not repeatedly attempt to get the value of an unresolved promise atom wrapped in a loadable (#1481)"
    ),
    ReactReferenceCase(id: "loadable.14", name: "should handle async error"),
    ReactReferenceCase(id: "loadable.15", name: "use lastLoadable should not update when new promise pending"),
    ReactReferenceCase(
        id: "loadable.16", name: "useLastLoadable does not commit when a new promise resolves to the same primitive"),
    ReactReferenceCase(
        id: "loadable.17", name: "useLastLoadable skips commits when equalityFn considers resolved values equal"),
    ReactReferenceCase(id: "loadable.18", name: "use lastLoadable should keep error"),
    ReactReferenceCase(
        id: "loadable.19", name: "use lastLoadable will will not use old promise value if new promise is made"),
    ReactReferenceCase(
        id: "loadable.20", name: "use lastLoadable will will not use old promise error if new promise is made"),
    ReactReferenceCase(id: "loadable.21", name: "useLoadable accept sync computed"),
    ReactReferenceCase(id: "loadable.22", name: "useLoadable subscribes to a new atom when the atom argument changes"),
    ReactReferenceCase(
        id: "loadable.23", name: "useLoadable subscribes to a new computed when the atom argument changes"),
    ReactReferenceCase(
        id: "loadable.24", name: "useLastLoadable subscribes to a new atom when the atom argument changes"),
    ReactReferenceCase(
        id: "loadable.25", name: "useLastLoadable subscribes to a new computed when the atom argument changes"),
    ReactReferenceCase(id: "loadable.26", name: "works with AbortError should not throw abortError"),
    ReactReferenceCase(id: "loadable.27", name: "useLoadable should catch errors"),
    ReactReferenceCase(id: "memory.01", name: "should release memory after component unmount"),
    ReactReferenceCase(id: "memory.02", name: "should release memory for promise & loadable"),
    ReactReferenceCase(
        id: "readable-watch-migration.01",
        name: "does not miss a value written between render and subscription in either component"),
    ReactReferenceCase(
        id: "readable-watch-migration.02",
        name: "turns synchronous computed read errors into loadable errors and recovers"),
    ReactReferenceCase(
        id: "readable-watch-migration.03", name: "ignores a rejection from the old store after switching providers"),
    ReactReferenceCase(
        id: "readable-watch-migration.04",
        name: "does not process a late resolution after unmounting a last-loadable subscription"),
    ReactReferenceCase(
        id: "readable-watch-migration.05",
        name: "only accepts the current subscription when two targets share a Promise in StrictMode"),
    ReactReferenceCase(id: "resolved.01", name: "convert promise to awaited value"),
    ReactReferenceCase(id: "resolved.02", name: "loading state"),
    ReactReferenceCase(id: "resolved.03", name: "use lastLoadable should not update when new promise pending"),
    ReactReferenceCase(
        id: "resolved.04", name: "useLastResolved does not commit when a new promise resolves to the same primitive"),
    ReactReferenceCase(
        id: "resolved.05", name: "useLastResolved skips commits when equalityFn considers resolved values equal"),
    ReactReferenceCase(id: "resolved.06", name: "useResolved accept sync computed"),
    ReactReferenceCase(id: "resolved.07", name: "useResolved subscribes to a new atom when the atom argument changes"),
    ReactReferenceCase(
        id: "resolved.08", name: "useResolved subscribes to a new computed when the atom argument changes"),
    ReactReferenceCase(
        id: "resolved.09", name: "useLastResolved subscribes to a new atom when the atom argument changes"),
    ReactReferenceCase(
        id: "resolved.10", name: "useLastResolved subscribes to a new computed when the atom argument changes"),
]
