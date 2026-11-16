import Foundation

/// Content-free observations from the relay, independent of routing policy.
struct RelayModelStatusResponse: Decodable, Sendable {
    let generatedAt: Date
    let models: [RelayModelStatus]

    enum CodingKeys: String, CodingKey {
        case generatedAt = "generated_at"
        case models
    }

    init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        generatedAt = try Self.date(values.decode(String.self, forKey: .generatedAt))
        var entries = try values.nestedUnkeyedContainer(forKey: .models)
        var models: [RelayModelStatus] = []
        while !entries.isAtEnd {
            let entry = try entries.superDecoder()
            if let model = try? RelayModelStatus(from: entry) { models.append(model) }
        }
        self.models = models
    }

    static func date(_ value: String) throws -> Date {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = fractional.date(from: value) ?? ISO8601DateFormatter().date(from: value)
        else {
            throw DecodingError.dataCorrupted(.init(
                codingPath: [],
                debugDescription: "Invalid observation timestamp"
            ))
        }
        return date
    }
}

/// Separate evidence from real requests and synthetic probes.
struct RelayModelStatus: Decodable, Sendable {
    let id: String
    let traffic: RelayObservationSummary?
    let probes: RelayObservationSummary?

    enum CodingKeys: String, CodingKey { case id, traffic, probes }

    init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id)
        traffic = try? values.decode(RelayObservationSummary.self, forKey: .traffic)
        probes = try? values.decode(RelayObservationSummary.self, forKey: .probes)
    }
}

/// Measurement counts and observation-based freshness.
struct RelayObservationSummary: Decodable, Sendable {
    let sampledAt: Date
    let expiresAt: Date
    let successCount: Int
    let failureCount: Int
    let ttftSampleCount: Int
    let throughputSampleCount: Int
    let ttftSampledAt: Date?
    let tpsSampledAt: Date?
    let ttft: Double?
    let tps: Double?

    enum CodingKeys: String, CodingKey {
        case sampledAt = "sampled_at", expiresAt = "expires_at"
        case successCount = "success_count", failureCount = "failure_count"
        case ttftSampleCount = "ttft_sample_count", throughputSampleCount = "throughput_sample_count"
        case ttft = "ttft_p50_ms", tps = "tps_p50"
        case ttftSampledAt = "ttft_sampled_at", tpsSampledAt = "tps_sampled_at"
    }

    init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        sampledAt = try RelayModelStatusResponse.date(values.decode(
            String.self,
            forKey: .sampledAt
        ))
        expiresAt = try RelayModelStatusResponse.date(values.decode(
            String.self,
            forKey: .expiresAt
        ))
        successCount = max(0, (try? values.decode(Int.self, forKey: .successCount)) ?? 0)
        failureCount = max(0, (try? values.decode(Int.self, forKey: .failureCount)) ?? 0)
        ttftSampleCount = max(0, (try? values.decode(Int.self, forKey: .ttftSampleCount)) ?? 0)
        throughputSampleCount = max(
            0,
            (try? values.decode(Int.self, forKey: .throughputSampleCount)) ?? 0
        )
        ttftSampledAt = try? RelayModelStatusResponse.date(values.decode(
            String.self,
            forKey: .ttftSampledAt
        ))
        tpsSampledAt = try? RelayModelStatusResponse.date(values.decode(
            String.self,
            forKey: .tpsSampledAt
        ))
        let ttft = try? values.decode(Double.self, forKey: .ttft)
        self.ttft = ttft.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil }
        let tps = try? values.decode(Double.self, forKey: .tps)
        self.tps = tps.flatMap { $0.isFinite && $0 > 0 ? $0 : nil }
    }
}

/// A response anchored to device time without extending server freshness.
struct RelayModelStatusSnapshot: Sendable {
    let response: RelayModelStatusResponse
    let receivedAt: Date

    func deviceDate(_ serverDate: Date) -> Date {
        receivedAt.addingTimeInterval(serverDate.timeIntervalSince(response.generatedAt))
    }
}
