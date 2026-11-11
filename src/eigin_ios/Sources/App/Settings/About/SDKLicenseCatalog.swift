import EiginSDK
import Foundation

/// Resolves bundled SDK package metadata and shared license texts for display.
struct SDKLicenseCatalog {
    let sdk: LicenseEntry
    let dependencies: [LicenseEntry]

    static let bundled: Result<SDKLicenseCatalog, Error> = Result {
        try SDKLicenseCatalog(contentsOf: EiginSDK.licenseCatalogURL)
    }

    init(contentsOf url: URL) throws {
        let document = try JSONDecoder().decode(Document.self, from: Data(contentsOf: url))
        sdk = try document.entry(for: document.sdk)
        dependencies = try document.packages.map { try document.entry(for: $0) }
    }

    private struct Package: Decodable {
        let name: String
        let version: String
        let license: String
        let repository: String
        let ecosystem: String
        let notice: String
        let licenseIds: [Int]
    }

    private struct Document: Decodable {
        let sdk: Package
        let packages: [Package]
        let licenseTexts: [String]

        func entry(for package: Package) throws -> LicenseEntry {
            guard !package.licenseIds.isEmpty else {
                throw CocoaError(.fileReadCorruptFile)
            }
            let texts = try package.licenseIds.map { index in
                guard licenseTexts.indices.contains(index), !licenseTexts[index].isEmpty else {
                    throw CocoaError(.fileReadCorruptFile)
                }
                return licenseTexts[index]
            }
            return LicenseEntry(
                name: package.name,
                repository: URL(string: package.repository),
                version: package.version,
                distribution: package.ecosystem.isEmpty ? nil : package.ecosystem,
                kind: .bundled(name: package.license, texts: texts),
                copyright: "",
                notice: package.notice.isEmpty ? nil : package.notice
            )
        }
    }
}
