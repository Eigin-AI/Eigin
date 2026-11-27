import EiginSDK
import Testing

private let greetingCatalog = #"""
{
    "schema_version": 1,
    "templates": {
        "greeting": "Hello {{ name }}!{% if role %}\n{% include 'role' %}{% endif %}",
        "role": "Role: {{ role }}{% if note %}\nNote: {{ note }}{% endif %}"
    }
}
"""#

@Test func rendersCustomCatalogSectionsThroughBindings() throws {
    let catalog = try EiginSDK.PromptCatalog.fromJson(document: greetingCatalog)
    try catalog.validateUsages(usages: ["greeting": ["name", "role", "note"]])

    #expect(try catalog.render(
        name: "greeting", parameters: ["name": "Ada", "role": "engineer", "note": ""]
    ) == "Hello Ada!\nRole: engineer")
    #expect(try catalog.render(
        name: "greeting", parameters: ["name": "Lin", "role": "", "note": "hidden"]
    ) == "Hello Lin!")
    #expect(try catalog.render(
        name: "greeting", parameters: ["name": "Søren", "role": "writer", "note": "Welcome 🌍"]
    ) == "Hello Søren!\nRole: writer\nNote: Welcome 🌍")
}

@Test func catalogErrorsCrossBindings() throws {
    let catalog = try EiginSDK.PromptCatalog.fromJson(document: greetingCatalog)
    #expect(throws: EiginSDK.PromptCatalogError.self) {
        try catalog.render(name: "greeting", parameters: [:])
    }
    #expect(throws: EiginSDK.PromptCatalogError.self) {
        try catalog.validateUsages(usages: ["missing": [], "greeting": ["name"]])
    }
    #expect(throws: EiginSDK.PromptCatalogError.self) {
        try EiginSDK.PromptCatalog.fromJson(document: #"{"schema_version":2,"templates":{}}"#)
    }
}
