@testable import Eigin
import Foundation
import Testing

@Suite("Weather attribution caching")
struct WeatherAttributionServiceTests {
    private func cacheURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("attribution.json")
    }

    private func fixture() -> WeatherSourceAttribution {
        // A complete one-pixel PNG stands in for the two provider marks.
        let png =
            Data(
                base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jRZkAAAAASUVORK5CYII="
            )!
        return WeatherSourceAttribution(
            legalURL: URL(string: "https://example.com/legal")!,
            legalText: "Weather provider legal attribution", lightMark: png, darkMark: png
        )
    }

    @Test func persistsCompleteAttributionAndUsesItOffline() async throws {
        let url = cacheURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let fixture = fixture()
        let online = AppleWeatherAttributionService(cacheURL: url, fetch: { fixture })
        #expect(try await online.load().legalText == fixture.legalText)
        let offline = AppleWeatherAttributionService(
            cacheURL: url,
            fetch: { throw URLError(.notConnectedToInternet) }
        )
        let cached = try await offline.load()
        #expect(cached.legalURL == fixture.legalURL)
        #expect(cached.lightMark == fixture.lightMark)
    }

    @Test func concurrentOfflineLoadsShareCachedFallback() async throws {
        let fixture = fixture()
        let url = cacheURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        _ = try await AppleWeatherAttributionService(cacheURL: url, fetch: { fixture }).load()
        let offline = AppleWeatherAttributionService(cacheURL: url, fetch: {
            try await Task.sleep(for: .milliseconds(20))
            throw URLError(.notConnectedToInternet)
        })
        async let first = offline.load()
        async let second = offline.load()
        let results = try await [first, second]
        #expect(results.allSatisfy { $0.legalText == fixture.legalText })
    }

    @Test func failureCanBeRetried() async throws {
        actor Boundary {
            var attempts = 0
            func fetch(_ result: WeatherSourceAttribution) throws -> WeatherSourceAttribution {
                attempts += 1
                if attempts == 1 { throw URLError(.notConnectedToInternet) }
                return result
            }
        }
        let boundary = Boundary()
        let fixture = fixture()
        let url = cacheURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let service = AppleWeatherAttributionService(
            cacheURL: url,
            fetch: { try await boundary.fetch(fixture) }
        )
        await #expect(throws: URLError.self) { try await service.load() }
        #expect(try await service.load().legalText == fixture.legalText)
    }

    @Test func watchReplyReplacesMarkerWithLegalText() async throws {
        let fixture = fixture()
        let url = cacheURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let service = AppleWeatherAttributionService(cacheURL: url, fetch: { fixture })
        let reply = try await WatchReplyFormatter.format(
            "Rain today.\n\n```eigin\n{\"type\":\"attribution\",\"source\":\"apple-weather\"}\n```",
            attributionService: service
        )
        #expect(reply.contains("Rain today."))
        #expect(reply.contains(fixture.legalText))
        #expect(!reply.contains("```eigin"))
    }

    @Test func watchPreservesUnrelatedMarkdown() async throws {
        let fixture = fixture()
        let url = cacheURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let service = AppleWeatherAttributionService(cacheURL: url, fetch: { fixture })
        let prefix = "# Weather\n[![Map](https://example.com/map.png)](https://example.com)\n```swift\nlet x = 1\n```\n"
        let marker = "```eigin\n{\"type\":\"attribution\",\"source\":\"apple-weather\"}\n```"
        let result = try await WatchReplyFormatter.format(
            prefix + marker,
            attributionService: service
        )
        #expect(result.hasPrefix(prefix))
        #expect(result.contains(fixture.legalText))
    }
}
