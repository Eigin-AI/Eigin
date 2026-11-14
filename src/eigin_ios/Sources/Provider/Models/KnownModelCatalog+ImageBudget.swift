import Foundation

extension KnownModelCatalog {
    /// Conservative image allowance for normalized attachments; provider tokenization remains
    /// approximate.
    static func imageInputBudget(width: Int?, height: Int?, model: String?) -> Int {
        let width = max(1, width ?? 1024)
        let height = max(1, height ?? 1024)
        let entry = model.flatMap(lookup)
        if entry?.pattern == "gpt-4o-mini" {
            let tiles = saturatedProduct((width - 1) / 512 + 1, (height - 1) / 512 + 1)
            return saturatedSum(2833, saturatedProduct(5667, max(4, tiles)))
        }
        let patches = saturatedProduct((width - 1) / 32 + 1, (height - 1) / 32 + 1)
        let patchBudget = saturatedSum(256, saturatedProduct(3, patches))
        // Unknown adapters receive the larger allowance used by high-cost image encodings.
        return entry == nil ? max(32768, patchBudget) : patchBudget
    }

    private static func saturatedProduct(_ lhs: Int, _ rhs: Int) -> Int {
        let (value, overflow) = lhs.multipliedReportingOverflow(by: rhs)
        return overflow ? Int.max : value
    }

    private static func saturatedSum(_ lhs: Int, _ rhs: Int) -> Int {
        let (value, overflow) = lhs.addingReportingOverflow(rhs)
        return overflow ? Int.max : value
    }
}
