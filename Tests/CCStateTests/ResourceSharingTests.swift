import Testing

@testable import CCState

@MainActor
private final class ControlledClient {
    struct Request {
        let identity: String
        let resource: Int
        let revision: Int
        let gate: Gate<String>
    }
    var requests: [Request] = []
    var pending: [Request] = []

    func load(identity: String, resource: Int, revision: Int) async throws -> String {
        let request = Request(identity: identity, resource: resource, revision: revision, gate: Gate())
        requests.append(request)
        pending.append(request)
        return try await request.gate.wait()
    }

    func finish(identity: String, failingResource: Int? = nil) {
        let selected = pending.filter { $0.identity == identity }
        pending.removeAll { $0.identity == identity }
        for request in selected {
            if request.resource == failingResource {
                request.gate.reject(TestError("offline"))
            } else {
                request.gate.resolve("\(identity)/\(request.resource)/\(request.revision)")
            }
        }
    }
}

@MainActor
private struct ResourceFixture {
    let store = Store()
    let identity: State<String>
    let revisions: [State<Int>]
    let client: ControlledClient
    let combined: Computed<Task<[String], Error>>

    init() {
        let identity = State("A")
        let revisions = (0..<4).map { _ in State(0) }
        let client = ControlledClient()
        let resources = (0..<4).map { resource in
            computedTask { get, _ in
                try await client.load(identity: get(identity), resource: resource, revision: get(revisions[resource]))
            }
        }
        self.identity = identity
        self.revisions = revisions
        self.client = client
        combined = computedTask { get, _ in
            let tasks = try resources.map { try get($0) }
            var result: [String] = []
            for task in tasks { result.append(try await task.value) }
            return result
        }
    }
}

@Suite
@MainActor
struct ResourceSharingTests {
    @Test func severalConsumersShareOneRequestPerResource() async throws {
        let fixture = ResourceFixture()
        let first = try fixture.store.get(fixture.combined)
        let second = try fixture.store.get(fixture.combined)
        let third = try fixture.store.get(fixture.combined)
        #expect(first == second && second == third)
        #expect(fixture.client.requests.count == 4)
        fixture.client.finish(identity: "A")
        #expect(try await first.value == ["A/0/0", "A/1/0", "A/2/0", "A/3/0"])
        #expect(try await second.value == third.value)
        #expect(fixture.client.requests.count == 4)
    }

    @Test func invalidatingPreferenceReusesOtherResources() async throws {
        let fixture = ResourceFixture()
        let first = try fixture.store.get(fixture.combined)
        fixture.client.finish(identity: "A")
        _ = try await first.value
        try fixture.store.set(fixture.revisions[0], 1)
        let second = try fixture.store.get(fixture.combined)
        #expect(first != second)
        #expect(fixture.client.requests.count == 5)
        #expect(fixture.client.pending.map(\.resource) == [0])
        fixture.client.finish(identity: "A")
        #expect(try await second.value == ["A/0/1", "A/1/0", "A/2/0", "A/3/0"])
    }

    @Test func obsoleteIdentityFinishingLastCannotReplaceCurrentTask() async throws {
        let fixture = ResourceFixture()
        let stop = try fixture.store.watch(fixture.combined) {}
        let old = try fixture.store.get(fixture.combined)
        try fixture.store.set(fixture.identity, "B")
        let current = try fixture.store.get(fixture.combined)
        #expect(fixture.client.requests.count == 8)
        fixture.client.finish(identity: "B")
        #expect(try await current.value.allSatisfy { $0.hasPrefix("B/") })
        fixture.client.finish(identity: "A")
        #expect(try await old.value.allSatisfy { $0.hasPrefix("A/") })
        #expect(try fixture.store.get(fixture.combined) == current)
        #expect(try await fixture.store.get(fixture.combined).value.allSatisfy { $0.hasPrefix("B/") })
        try stop.cancel()
    }

    @Test func explicitRetryRecoversFailedResourceWithoutReloadingSuccessfulOnes() async throws {
        let fixture = ResourceFixture()
        let first = try fixture.store.get(fixture.combined)
        fixture.client.finish(identity: "A", failingResource: 0)
        await #expect(throws: TestError.self) { try await first.value }
        #expect(try fixture.store.get(fixture.combined) == first)
        #expect(fixture.client.requests.count == 4)
        try fixture.store.set(fixture.revisions[0], 1)
        let second = try fixture.store.get(fixture.combined)
        #expect(fixture.client.requests.count == 5)
        fixture.client.finish(identity: "A")
        #expect(try await second.value == ["A/0/1", "A/1/0", "A/2/0", "A/3/0"])
    }
}
