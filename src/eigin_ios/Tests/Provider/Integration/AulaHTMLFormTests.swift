@testable import Eigin
import Testing

/// Pins down the HTML shapes ``AulaFormWalker`` depends on being able to
/// parse: the SAML HTTP-POST binding form, the broker's confirmation-button
/// form, and the missing-`RelayState` case (community-reference issue #310).
@Suite("AulaHTMLParsing")
struct AulaHTMLFormTests {
    @Test func parsesSAMLAutoSubmitForm() {
        let html = """
        <html><body onload="document.forms[0].submit()">
        <form method="post" action="https://broker.unilogin.dk/auth/realms/broker/broker/nemlogin3/endpoint">
        <input type="hidden" name="SAMLResponse" value="abc123" />
        <input type="hidden" name="RelayState" value="relay1" />
        </form>
        </body></html>
        """

        let form = AulaHTMLParsing.samlForm(in: html)

        #expect(form?
            .action == "https://broker.unilogin.dk/auth/realms/broker/broker/nemlogin3/endpoint")
        #expect(form?.fields["SAMLResponse"] == "abc123")
        #expect(form?.fields["RelayState"] == "relay1")
    }

    @Test func tolerablesMissingRelayState() {
        let html = """
        <form action="/acs">
        <input type="hidden" name="SAMLResponse" value="abc123" />
        </form>
        """

        let form = AulaHTMLParsing.samlForm(in: html)

        #expect(form?.fields["SAMLResponse"] == "abc123")
        #expect(form?.fields["RelayState"] == nil)
    }

    @Test func returnsNilWhenNoSAMLResponsePresent() {
        let html = "<form action=\"/other\"><input type=\"hidden\" name=\"Other\" value=\"x\" /></form>"

        #expect(AulaHTMLParsing.samlForm(in: html) == nil)
    }

    @Test func detectsConfirmationForm() {
        let html = """
        <form action="/post-broker-login?session_code=abc&execution=1">
        <input type="hidden" name="selected-aktoer" value="KONTAKT" />
        <button id="confirmation-button">Continue</button>
        </form>
        """

        let form = AulaHTMLParsing.confirmationForm(in: html)

        #expect(form?.action == "/post-broker-login?session_code=abc&execution=1")
        #expect(form?.fields["selected-aktoer"] == "KONTAKT")
    }

    @Test func confirmationFormAbsentOnHappyPath() {
        let html = "<html><body>No confirmation here</body></html>"

        #expect(AulaHTMLParsing.confirmationForm(in: html) == nil)
    }

    @Test func decodesHTMLEntitiesInFieldValues() {
        let html = """
        <form action="/acs">
        <input type="hidden" name="SAMLResponse" value="a&amp;b&quot;c" />
        </form>
        """

        #expect(AulaHTMLParsing.samlForm(in: html)?.fields["SAMLResponse"] == "a&b\"c")
    }
}
