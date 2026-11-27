import { initialize, PromptCatalog } from "../src";
import { defaultPromptParameters as parameters } from "./default-prompt-parameters";

export const promptTests = {
  async bundled() {
    await initialize();
    const catalog = PromptCatalog.defaultCatalog();
    catalog.validateUsages(new Map(Object.entries(parameters)));
    let checked = 0;
    for (const [name, required] of Object.entries(parameters)) {
      for (const empty of [true, false]) {
        const values = new Map(
          required.map((parameter) => [
            parameter,
            empty ? "" : `Sample ${parameter}`,
          ]),
        );
        if (typeof catalog.render(name, values) !== "string")
          throw new Error(`Render failed: ${name}`);
        checked++;
      }
    }
    return checked;
  },
  async custom() {
    await initialize();
    const catalog = PromptCatalog.fromJson(
      JSON.stringify({
        schema_version: 1,
        templates: {
          greeting:
            "Hello {{ name }}!{% if role %}\n{% include 'role' %}{% endif %}",
          role: "Role: {{ role }}{% if note %}\nNote: {{ note }}{% endif %}",
        },
      }),
    );
    catalog.validateUsages(new Map([["greeting", ["name", "role", "note"]]]));
    const rejects = (action: () => unknown) => {
      try {
        action();
        return false;
      } catch {
        return true;
      }
    };
    const render = (name: string, role: string, note: string) =>
      catalog.render(
        "greeting",
        new Map([
          ["name", name],
          ["role", role],
          ["note", note],
        ]),
      );
    return {
      withRole: render("Ada", "engineer", ""),
      withoutRole: render("Lin", "", "hidden"),
      withNote: render("Søren", "writer", "Welcome 🌍"),
      missing: rejects(() => catalog.render("greeting", new Map())),
      preflight: rejects(() =>
        catalog.validateUsages(new Map([["missing", []]])),
      ),
      independent: rejects(() =>
        PromptCatalog.defaultCatalog().render("greeting", new Map()),
      ),
    };
  },
};

window.promptTests = promptTests;
