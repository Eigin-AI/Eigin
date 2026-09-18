import Foundation

extension URL {
    /// Whether fetching this source discloses the user's IP to a remote host:
    /// http(s) networks, as opposed to data URIs and files, which are local.
    var isRemoteHTTP: Bool {
        scheme?.lowercased() == "http" || scheme?.lowercased() == "https"
    }

    /// The host reduced to its root domain for display: `images.unsplash.com`
    /// shows as `unsplash.com`. Falls back to the whole host where it can't be
    /// reduced — single-label hosts, IP literals — and empty where there is no host.
    ///
    /// This is the root-label rule the integration and provider connect sheets
    /// use for naming, without a public-suffix list: a few well-known two-part
    /// country suffixes keep one more label, the rest are a good enough guess.
    func rootDisplayDomain() -> String {
        guard let full = host(percentEncoded: false), !full.isEmpty else { return "" }
        // IPv6 hosts carry colons; leave them whole.
        guard !full.contains(":") else { return full }
        var labels = full.split(separator: ".").map(String.init)
        // A leading www is never the point of a host, whatever the suffix shape.
        if labels.count > 2, labels[0].lowercased() == "www" {
            labels.removeFirst()
        }
        // Two labels are already the root; one is a bare host. All-numeric
        // labels are an IPv4 literal, which isn't a domain to shorten.
        guard labels.count > 2,
              !(labels.count == 4 && labels.allSatisfy { $0.allSatisfy(\.isNumber) })
        else { return labels.joined(separator: ".") }
        let lastTwo = labels.suffix(2).joined(separator: ".")
        if twoPartSuffixes.contains(lastTwo.lowercased()) {
            return labels.suffix(3).joined(separator: ".")
        }
        return lastTwo
    }

    private var twoPartSuffixes: Set<String> {
        [
            "co.uk",
            "org.uk",
            "ac.uk",
            "gov.uk",
            "com.au",
            "net.au",
            "org.au",
            "co.jp",
            "or.jp",
            "ne.jp",
            "co.nz",
            "com.br",
            "com.mx",
            "com.cn",
            "co.in",
            "co.za",
            "com.sg",
            "com.tr",
        ]
    }
}
