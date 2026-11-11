@testable import Eigin
import Foundation
import Testing

@Suite("SDK license catalog")
struct SDKLicenseCatalogTests {
    private func withCatalog(
        dependencyLicenseIds: [Int] = [1],
        _ body: (URL) throws -> Void
    ) throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        let sdk: [String: Any] = [
            "name": "Eigin SDK", "version": "0.4.2", "license": "AGPL-3.0",
            "repository": "https://example.com/sdk", "ecosystem": "",
            "notice": "", "licenseIds": [0],
        ]
        let dependency: [String: Any] = [
            "name": "runtime", "version": "2.1", "license": "MIT",
            "repository": "https://example.com/runtime", "ecosystem": "Cargo",
            "notice": "Additional attribution", "licenseIds": dependencyLicenseIds,
        ]
        let data = try JSONSerialization.data(withJSONObject: [
            "sdk": sdk, "packages": [dependency],
            "licenseTexts": ["SDK license text", "Copyright runtime contributors\nMIT text"],
        ])
        try data.write(to: url)
        try body(url)
    }

    @Test func loadsNavigableEntriesWithTheirOwnLicenseTexts() throws {
        try withCatalog { url in
            let catalog = try SDKLicenseCatalog(contentsOf: url)
            #expect(catalog.sdk.version == "0.4.2")
            #expect(catalog.sdk.kind.rawValue == "AGPL-3.0")
            #expect(catalog.sdk.kind.texts == ["SDK license text"])
            let dependency = try #require(catalog.dependencies.first)
            #expect(dependency.name == "runtime")
            #expect(dependency.version == "2.1")
            #expect(dependency.notice == "Additional attribution")
            #expect(dependency.kind.texts == ["Copyright runtime contributors\nMIT text"])
            #expect(dependency.repository == URL(string: "https://example.com/runtime"))
        }
    }

    @Test(arguments: [[], [-1], [2]])
    func rejectsMissingOrInvalidLicenseReferences(ids: [Int]) throws {
        try withCatalog(dependencyLicenseIds: ids) { url in
            #expect(throws: CocoaError.self) {
                try SDKLicenseCatalog(contentsOf: url)
            }
        }
    }
}
