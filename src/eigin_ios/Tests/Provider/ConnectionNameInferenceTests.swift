@testable import Eigin
import Testing

/// The domain-inferred name offered on the connected step: a guess worth
/// confirming, never asked for up front.
@MainActor
struct ConnectionNameInferenceTests {
    /// The infer helpers live on view types, which carry main-actor isolation.
    @Test func schemeSubdomainAndPathAreStripped() {
        #expect(
            ProviderConnectSheetContent.suggestedName(from: "https://api.infercom.eu/v1")
                == "Infercom"
        )
        #expect(ConnectIntegrationSheet
            .suggestedName(from: "https://www.mcp.linear.app") == "Linear")
    }

    @Test func plainHostCapitalises() {
        #expect(ProviderConnectSheetContent.suggestedName(from: "https://groq.com") == "Groq")
    }

    @Test func bareHostWorks() {
        #expect(ConnectIntegrationSheet
            .suggestedName(from: "homeassistant.local:8123") == "Homeassistant")
    }

    @Test func twoLabelHostTakesTheFirst() {
        // Nonsense host, but the rule is the same: two labels, first is the
        // brand.
        #expect(ConnectIntegrationSheet.suggestedName(from: "https://www.api") == "Www")
    }

    @Test func rootLabelIsTheBrand() {
        #expect(ConnectIntegrationSheet.suggestedName(from: "https://code.eigin.ai") == "Eigin")
        #expect(ConnectIntegrationSheet.suggestedName(from: "mcp.linear.app/sse") == "Linear")
        #expect(ProviderConnectSheetContent
            .suggestedName(from: "https://api.eurouter.ai/api/v1") == "Eurouter")
    }

    @Test func schemelessAddressInfersHTTPS() {
        // What the connect flow probes must be what gets saved (#249):
        // a scheme-less input breaks URL validation once stored.
        #expect(
            ConnectIntegrationSheet.normalizedAddress("cloud.comfy.org/mcp")
                == "https://cloud.comfy.org/mcp"
        )
        #expect(
            ConnectIntegrationSheet.normalizedAddress(" http://127.0.0.1:9000/mcp ")
                == "http://127.0.0.1:9000/mcp"
        )
    }
}
