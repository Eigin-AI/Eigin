@testable import Eigin
import Foundation
import Testing

@Suite("OpenFoodFactsClient", .serialized)
struct OpenFoodFactsClientTests {
    // MARK: - Helpers

    private struct FakeDeviceInfo: DeviceInfoService {
        var name: String = "Eigin"
        var version: String = "1.0"
        var build: String = "42"
        var system: String = "26.0"

        func freeDiskSpaceBytes() -> Int64? {
            nil
        }

        func physicalMemoryBytes() -> UInt64 {
            0
        }

        func deviceIdentifier() -> String {
            "iPhone0,0"
        }

        func systemVersion() -> String {
            system
        }

        func appBuildVersion() -> String {
            build
        }

        func appName() -> String {
            name
        }

        func appVersion() -> String {
            version
        }
    }

    private func makeHitsJSON(hits: [[String: Any]]) -> Data {
        try! JSONSerialization.data(withJSONObject: ["hits": hits])
    }

    /// Builds the exact URL the client will generate for search, so stubbing is reliable.
    private func expectedSearchURL(
        query: String,
        limit: Int = 5,
        languageCode: String = "en"
    ) -> String {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "search.openfoodfacts.org"
        components.path = "/search"
        components.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "page_size", value: String(limit)),
            URLQueryItem(name: "fields", value: "code,product_name,brands,nutriments"),
            URLQueryItem(name: "langs", value: languageCode),
        ]
        return components.url!.absoluteString
    }

    /// Builds the exact URL the client will generate for barcode lookup, so stubbing is reliable.
    private func expectedBarcodeURL(
        barcode: String,
        languageCode: String = "en"
    ) -> String {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "search.openfoodfacts.org"
        components.path = "/search"
        components.queryItems = [
            URLQueryItem(name: "q", value: "code:\"\(barcode)\""),
            URLQueryItem(name: "page_size", value: "1"),
            URLQueryItem(name: "fields", value: "code,product_name,brands,nutriments"),
            URLQueryItem(name: "langs", value: languageCode),
        ]
        return components.url!.absoluteString
    }

    // MARK: - Search: headers & query params

    @Test func searchSendsDescriptiveUserAgent() async {
        let session = FakeURLProtocol.fakeSession()
        let url = expectedSearchURL(query: "banana")
        FakeURLProtocol.stubResponse(
            for: url,
            data: makeHitsJSON(hits: []),
            statusCode: 200
        )

        let client = OpenFoodFactsClient(
            urlSession: session,
            deviceInfo: FakeDeviceInfo(name: "Eigin", version: "1.2", build: "99", system: "26.1")
        )
        _ = await client.search(query: "banana")
    }

    @Test func searchIncludesLangs() async {
        let session = FakeURLProtocol.fakeSession()
        let url = expectedSearchURL(query: "oats", limit: 3, languageCode: "nl")
        FakeURLProtocol.stubResponse(
            for: url,
            data: makeHitsJSON(hits: []),
            statusCode: 200
        )

        let client = OpenFoodFactsClient(
            urlSession: session,
            deviceInfo: FakeDeviceInfo(),
            languageCode: "nl"
        )
        _ = await client.search(query: "oats", limit: 3)
    }

    // MARK: - Search: response parsing

    @Test func searchReturnsProducts() async throws {
        let session = FakeURLProtocol.fakeSession()
        let url = expectedSearchURL(query: "oats", limit: 2)
        FakeURLProtocol.stubResponse(
            for: url,
            data: makeHitsJSON(hits: [
                [
                    "code": "123",
                    "product_name": "Rolled Oats",
                    "brands": ["Bob's", "Bob's Red Mill"],
                    "nutriments": [
                        "energy-kcal_100g": 379,
                        "energy-kcal_serving": 152,
                        "proteins_100g": 13.5,
                        "fat_100g": 6.9,
                        "carbohydrates_100g": 67.7,
                    ],
                ],
            ]),
            statusCode: 200
        )

        let client = OpenFoodFactsClient(urlSession: session, deviceInfo: FakeDeviceInfo())
        let result = await client.search(query: "oats", limit: 2)

        let products = try #require(try? result.get())
        #expect(products.count == 1)
        #expect(products[0].barcode == "123")
        #expect(products[0].name == "Rolled Oats")
        #expect(products[0].brands == ["Bob's", "Bob's Red Mill"])
        #expect(products[0].caloriesPer100g == 379)
        #expect(products[0].caloriesPerServing == 152)
        #expect(products[0].proteinPer100g == 13.5)
        #expect(products[0].fatPer100g == 6.9)
        #expect(products[0].carbsPer100g == 67.7)
    }

    @Test func searchEmptyResultsReturnsEmptyArray() async throws {
        let session = FakeURLProtocol.fakeSession()
        let url = expectedSearchURL(query: "xyznonexistent")
        FakeURLProtocol.stubResponse(
            for: url,
            data: makeHitsJSON(hits: []),
            statusCode: 200
        )

        let client = OpenFoodFactsClient(urlSession: session, deviceInfo: FakeDeviceInfo())
        let result = await client.search(query: "xyznonexistent")

        let products = try #require(try? result.get())
        #expect(products.isEmpty)
    }

    @Test func searchBadStatusReturnsFailure() async {
        let session = FakeURLProtocol.fakeSession()
        let url = expectedSearchURL(query: "oats")
        FakeURLProtocol.stubResponse(for: url, data: Data(), statusCode: 503)

        let client = OpenFoodFactsClient(urlSession: session, deviceInfo: FakeDeviceInfo())
        let result = await client.search(query: "oats")

        #expect(result.isFailure)
        if case .failure(let error) = result {
            #expect(error is OpenFoodFactsError)
        }
    }

    @Test func searchMalformedJSONReturnsFailure() async {
        let session = FakeURLProtocol.fakeSession()
        let url = expectedSearchURL(query: "oats")
        FakeURLProtocol.stubResponse(for: url, data: Data("not json".utf8), statusCode: 200)

        let client = OpenFoodFactsClient(urlSession: session, deviceInfo: FakeDeviceInfo())
        let result = await client.search(query: "oats")

        #expect(result.isFailure)
    }

    // MARK: - getProduct: headers & query params

    @Test func getProductUsesBarcodeFilter() async {
        let session = FakeURLProtocol.fakeSession()
        let url = expectedBarcodeURL(barcode: "123456", languageCode: "fr")
        FakeURLProtocol.stubResponse(
            for: url,
            data: makeHitsJSON(hits: [
                [
                    "code": "123456",
                    "product_name": "Croissant",
                    "brands": ["Local"],
                    "nutriments": [:],
                ],
            ]),
            statusCode: 200
        )

        let client = OpenFoodFactsClient(
            urlSession: session,
            deviceInfo: FakeDeviceInfo(),
            languageCode: "fr"
        )
        _ = await client.getProduct(barcode: "123456")
    }

    // MARK: - getProduct: response parsing

    @Test func getProductReturnsProduct() async throws {
        let session = FakeURLProtocol.fakeSession()
        let url = expectedBarcodeURL(barcode: "5060292302201")
        FakeURLProtocol.stubResponse(
            for: url,
            data: makeHitsJSON(hits: [
                [
                    "code": "5060292302201",
                    "product_name": "Dark Chocolate 85%",
                    "brands": ["Lindt"],
                    "nutriments": [
                        "energy-kcal_100g": 600,
                        "energy-kcal_serving": 150,
                        "proteins_100g": 10.0,
                        "fat_100g": 46.0,
                        "carbohydrates_100g": 19.0,
                    ],
                ],
            ]),
            statusCode: 200
        )

        let client = OpenFoodFactsClient(urlSession: session, deviceInfo: FakeDeviceInfo())
        let result = await client.getProduct(barcode: "5060292302201")

        let product = try #require(try? result.get())
        #expect(product.barcode == "5060292302201")
        #expect(product.name == "Dark Chocolate 85%")
        #expect(product.brands == ["Lindt"])
        #expect(product.caloriesPer100g == 600)
        #expect(product.caloriesPerServing == 150)
        #expect(product.proteinPer100g == 10.0)
        #expect(product.fatPer100g == 46.0)
        #expect(product.carbsPer100g == 19.0)
    }

    @Test func getProductMissingNameReturnsFailure() async {
        let session = FakeURLProtocol.fakeSession()
        let url = expectedBarcodeURL(barcode: "000")
        FakeURLProtocol.stubResponse(
            for: url,
            data: makeHitsJSON(hits: [
                [
                    "code": "000",
                    "product_name": "",
                    "nutriments": [:],
                ],
            ]),
            statusCode: 200
        )

        let client = OpenFoodFactsClient(urlSession: session, deviceInfo: FakeDeviceInfo())
        let result = await client.getProduct(barcode: "000")

        #expect(result.isFailure)
    }

    @Test func getProductEmptyHitsReturnsFailure() async {
        let session = FakeURLProtocol.fakeSession()
        let url = expectedBarcodeURL(barcode: "000")
        FakeURLProtocol.stubResponse(
            for: url,
            data: makeHitsJSON(hits: []),
            statusCode: 200
        )

        let client = OpenFoodFactsClient(urlSession: session, deviceInfo: FakeDeviceInfo())
        let result = await client.getProduct(barcode: "000")

        #expect(result.isFailure)
    }

    @Test func getProductBadStatusReturnsFailure() async {
        let session = FakeURLProtocol.fakeSession()
        let url = expectedBarcodeURL(barcode: "000")
        FakeURLProtocol.stubResponse(for: url, data: Data(), statusCode: 404)

        let client = OpenFoodFactsClient(urlSession: session, deviceInfo: FakeDeviceInfo())
        let result = await client.getProduct(barcode: "000")

        #expect(result.isFailure)
    }

    @Test func getProductMalformedJSONReturnsFailure() async {
        let session = FakeURLProtocol.fakeSession()
        let url = expectedBarcodeURL(barcode: "000")
        FakeURLProtocol.stubResponse(for: url, data: Data("not json".utf8), statusCode: 200)

        let client = OpenFoodFactsClient(urlSession: session, deviceInfo: FakeDeviceInfo())
        let result = await client.getProduct(barcode: "000")

        #expect(result.isFailure)
    }
}

private extension Result {
    var isFailure: Bool {
        if case .failure = self { return true }
        return false
    }
}
