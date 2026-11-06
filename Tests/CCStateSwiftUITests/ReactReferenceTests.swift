import CCState
import Testing

@testable import CCStateSwiftUI

struct ReactReferenceCase: Sendable, CustomTestStringConvertible {
    let id: String
    let name: String
    var testDescription: String { "\(id): \(name)" }
}

#if canImport(AppKit)
    @Suite(.serialized, .timeLimit(.minutes(1)))
    @MainActor
    struct ReactReferenceTests {
        @Test("Pinned React behavior, adapted to SwiftUI", arguments: reactReferenceCases)
        func reference(_ test: ReactReferenceCase) async throws {
            switch test.id.split(separator: ".")[0] {
            case "get-and-set": try await runGetSetReference(test)
            case "items": try await runItemsReference(test)
            case "loadable": try await runLoadableReference(test)
            case "resolved": try await runResolvedReference(test)
            case "readable-watch-migration": try await runMigrationReference(test)
            case "loadable-set": try await runOperationReference(test)
            case "memory": try await runMemoryReference(test)
            default: Issue.record("Missing reference case \(test.id)")
            }
        }
    }
#endif
