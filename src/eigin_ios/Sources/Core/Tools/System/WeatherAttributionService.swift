import Foundation
import UIKit
import WeatherKit

/// Trusted provider metadata and downloaded marks shared by attribution surfaces.
struct WeatherSourceAttribution: Codable, Sendable {
    let legalURL: URL
    let legalText: String
    let lightMark: Data
    let darkMark: Data
}

/// Loads attribution independently of a weather lookup, including from saved chats.
protocol WeatherAttributionServing: Sendable {
    func load() async throws -> WeatherSourceAttribution
}

/// Caches a complete attribution so offline history retains the mark and legal details.
actor AppleWeatherAttributionService: WeatherAttributionServing {
    typealias Fetch = @Sendable () async throws -> WeatherSourceAttribution

    private let fetch: Fetch
    private let cacheURL: URL
    private var cached: WeatherSourceAttribution?
    private var pending: Task<WeatherSourceAttribution, Error>?

    init(
        cacheURL: URL = AppleWeatherAttributionService.defaultCacheURL,
        fetch: @escaping Fetch = AppleWeatherAttributionService.fetchAttribution
    ) {
        self.cacheURL = cacheURL
        self.fetch = fetch
    }

    func load() async throws -> WeatherSourceAttribution {
        if let cached { return cached }
        if let pending { return try await pending.value }
        let fetch = fetch
        let cacheURL = cacheURL
        let task = Task { try await Self.fetchOrRestore(fetch: fetch, cacheURL: cacheURL) }
        pending = task
        defer { pending = nil }
        let attribution = try await task.value
        cached = attribution
        return attribution
    }

    private static func fetchOrRestore(
        fetch: Fetch,
        cacheURL: URL
    ) async throws -> WeatherSourceAttribution {
        do {
            let attribution = try await fetch()
            try? FileManager.default.createDirectory(
                at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            if let data = try? JSONEncoder().encode(attribution) {
                try? data.write(to: cacheURL, options: .atomic)
            }
            return attribution
        } catch {
            if let data = try? Data(contentsOf: cacheURL),
               let attribution = try? JSONDecoder().decode(
                   WeatherSourceAttribution.self,
                   from: data
               ),
               UIImage(data: attribution.lightMark) != nil,
               UIImage(data: attribution.darkMark) != nil,
               attribution.legalURL.scheme == "https"
            {
                return attribution
            }
            throw error
        }
    }

    private static var defaultCacheURL: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("weather-attribution/v1.json")
    }

    private static func fetchAttribution() async throws -> WeatherSourceAttribution {
        let metadata = try await WeatherKit.WeatherService.shared.attribution
        guard metadata.legalPageURL.scheme == "https" else { throw URLError(.badURL) }
        async let light = mark(at: metadata.combinedMarkLightURL)
        async let dark = mark(at: metadata.combinedMarkDarkURL)
        return try await WeatherSourceAttribution(
            legalURL: metadata.legalPageURL,
            legalText: metadata.legalAttributionText,
            lightMark: light,
            darkMark: dark
        )
    }

    private static func mark(at url: URL) async throws -> Data {
        guard url.scheme == "https" else { throw URLError(.badURL) }
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let response = response as? HTTPURLResponse,
              (200 ... 299).contains(response.statusCode), UIImage(data: data) != nil
        else { throw URLError(.cannotDecodeContentData) }
        return data
    }
}
