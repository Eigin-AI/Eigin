@testable import Eigin
import Foundation
import SwiftData
import Testing

@Suite("Maps Tools", .serialized)
struct MapsToolTests {
    // MARK: - Helpers

    @MainActor
    private func makeAgent() throws -> (Agent, ModelContainer) {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Schema(SchemaV1.models, version: SchemaV1.versionIdentifier),
            configurations: config
        )
        let agent = Agent(name: "TestAgent", providerID: UUID(), model: "test-model")
        container.mainContext.insert(agent)
        return (agent, container)
    }

    private func makeCall(name: String, arguments: String) -> ToolCall {
        ToolCall(
            id: "call_\(name)",
            type: "function",
            function: .init(name: name, arguments: arguments)
        )
    }

    private func samplePlace() -> Place {
        Place(
            name: "Bioparc Fuengirola",
            address: "Calle Camilo José Cela, Fuengirola",
            latitude: 36.5418,
            longitude: -4.6228,
            category: "Zoo"
        )
    }

    // MARK: - SearchPlacesTool

    @Test @MainActor func searchPlacesReturnsResults() async throws {
        let (agent, _container) = try makeAgent()
        _ = _container
        let maps = FakeMapsService()
        maps.searchResults = [samplePlace()]

        let tool = SearchPlacesTool(maps: maps)
        let call = makeCall(name: "search_places", arguments: """
        {"query":"zoo"}
        """)
        let result = await tool.execute(call, agent: agent)

        #expect(!result.isError)
        #expect(result.content.contains("Bioparc Fuengirola"))
        #expect(result.content.contains("Zoo"))
        #expect(result.content.contains("\"count\":1"))
        #expect(maps.searchCalls.count == 1)
        #expect(maps.searchCalls.first?.query == "zoo")
        #expect(maps.searchCalls.first?.near == nil)
    }

    @Test @MainActor func searchPlacesBiasesNearCoordinate() async throws {
        let (agent, _container) = try makeAgent()
        _ = _container
        let maps = FakeMapsService()
        maps.searchResults = [samplePlace()]

        let tool = SearchPlacesTool(maps: maps)
        let call = makeCall(name: "search_places", arguments: """
        {"query":"pharmacy","latitude":36.72,"longitude":-4.42}
        """)
        let result = await tool.execute(call, agent: agent)

        #expect(!result.isError)
        let near = maps.searchCalls.first?.near
        #expect(near?.latitude == 36.72)
        #expect(near?.longitude == -4.42)
    }

    @Test @MainActor func searchPlacesMissingQuery() async throws {
        let (agent, _container) = try makeAgent()
        _ = _container

        let tool = SearchPlacesTool(maps: FakeMapsService())
        let call = makeCall(name: "search_places", arguments: "{}")
        let result = await tool.execute(call, agent: agent)

        #expect(result.isError)
        #expect(result.content.contains("query"))
    }

    @Test @MainActor func searchPlacesError() async throws {
        let (agent, _container) = try makeAgent()
        _ = _container
        let maps = FakeMapsService()
        maps.searchError = MapsError.noRoute

        let tool = SearchPlacesTool(maps: maps)
        let call = makeCall(name: "search_places", arguments: """
        {"query":"zoo"}
        """)
        let result = await tool.execute(call, agent: agent)

        #expect(result.isError)
    }

    // MARK: - GetDirectionsTool

    @Test @MainActor func getDirectionsReturnsEstimate() async throws {
        let (agent, _container) = try makeAgent()
        _ = _container
        let maps = FakeMapsService()
        maps.route = Route(travelTime: 1080, distance: 12000, summary: "A-7")

        let tool = GetDirectionsTool(maps: maps)
        let call = makeCall(name: "get_directions", arguments: """
        {"origin_latitude":36.72,"origin_longitude":-4.42,"destination_latitude":36.54,"destination_longitude":-4.62}
        """)
        let result = await tool.execute(call, agent: agent)

        #expect(!result.isError)
        #expect(result.content.contains("A-7"))
        #expect(maps.directionsCalls.count == 1)
        // Mode defaults to drive when not specified.
        #expect(maps.directionsCalls.first?.mode == .drive)
        #expect(result.content.contains("drive"))
    }

    @Test @MainActor func getDirectionsRespectsMode() async throws {
        let (agent, _container) = try makeAgent()
        _ = _container
        let maps = FakeMapsService()
        maps.route = Route(travelTime: 600, distance: 800, summary: nil)

        let tool = GetDirectionsTool(maps: maps)
        let call = makeCall(name: "get_directions", arguments: """
        {"origin_latitude":36.72,"origin_longitude":-4.42,"destination_latitude":36.73,"destination_longitude":-4.41,"mode":"walk"}
        """)
        let result = await tool.execute(call, agent: agent)

        #expect(!result.isError)
        #expect(maps.directionsCalls.first?.mode == .walk)
    }

    @Test @MainActor func getDirectionsMissingCoordinates() async throws {
        let (agent, _container) = try makeAgent()
        _ = _container

        let tool = GetDirectionsTool(maps: FakeMapsService())
        let call = makeCall(name: "get_directions", arguments: """
        {"origin_latitude":36.72,"origin_longitude":-4.42}
        """)
        let result = await tool.execute(call, agent: agent)

        #expect(result.isError)
        #expect(result.content.contains("coordinates"))
    }

    @Test @MainActor func getDirectionsTransitUnavailableWarns() async throws {
        let (agent, _container) = try makeAgent()
        _ = _container
        let maps = FakeMapsService()
        maps.directionsError = MapsError.transitUnavailable

        let tool = GetDirectionsTool(maps: maps)
        let call = makeCall(name: "get_directions", arguments: """
        {"origin_latitude":36.72,"origin_longitude":-4.42,"destination_latitude":36.54,"destination_longitude":-4.62,"mode":"transit"}
        """)
        let result = await tool.execute(call, agent: agent)

        // Sparse transit data is a warning, not a hard error.
        #expect(!result.isError)
        #expect(result.content.contains("warnings"))
        #expect(result.content.contains("Transit"))
    }
}
