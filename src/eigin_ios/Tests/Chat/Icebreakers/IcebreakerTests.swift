@testable import Eigin
import Foundation
import Testing

@Suite("Icebreakers", .serialized)
struct IcebreakerTests {
    private func group(
        _ id: String,
        featured: Bool = false,
        order: Int = 0
    ) -> IcebreakerGroup {
        IcebreakerGroup(
            id: id,
            label: LocalizedText(en: id, da: id),
            featured: featured,
            order: order,
            icebreakers: [
                IcebreakerPrompt(
                    id: "\(id)_1",
                    title: LocalizedText(en: "t", da: "t"),
                    prompt: LocalizedText(en: "p", da: "p")
                ),
            ]
        )
    }

    // MARK: - Selection

    @Test("Featured groups come first")
    func featuredFirst() {
        let ordered = IcebreakerSelection.groups(from: [
            group("b", order: 10),
            group("a", featured: true, order: 99),
        ])
        #expect(ordered.map(\.id) == ["a", "b"])
    }

    @Test("Non-featured groups sort by ascending order, then id")
    func ordersByOrderThenID() {
        let ordered = IcebreakerSelection.groups(from: [
            group("z", order: 30),
            group("m", order: 10),
            group("n", order: 10),
        ])
        #expect(ordered.map(\.id) == ["m", "n", "z"])
    }

    @Test("Group count is capped by the limit")
    func capsGroupCount() {
        let all = (0 ..< 10).map { group("g\($0)", order: $0) }
        let ordered = IcebreakerSelection.groups(from: all, limit: 3)
        #expect(ordered.count == 3)
        #expect(ordered.map(\.id) == ["g0", "g1", "g2"])
    }

    // MARK: - Localization

    @Test("LocalizedText resolves to the current app language")
    func resolvesToCurrentLanguage() {
        let previous = UserDefaults.standard.string(forKey: StorageKey.appLanguage)
        defer { UserDefaults.standard.set(previous, forKey: StorageKey.appLanguage) }

        let text = LocalizedText(en: "Get organized", da: "Bliv organiseret")

        UserDefaults.standard.set(AppLanguage.english.rawValue, forKey: StorageKey.appLanguage)
        #expect(text.resolved == "Get organized")

        UserDefaults.standard.set(AppLanguage.danish.rawValue, forKey: StorageKey.appLanguage)
        #expect(text.resolved == "Bliv organiseret")
    }
}
