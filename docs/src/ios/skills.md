# Skills on iOS

`Skill` is a plain value type: an ID, display name, instruction string, a `Set<ToolCapability>`, and an `alwaysActive` flag. `BundledSkill` is a namespace holding the eight built-in `Skill` instances as static properties.

`ActiveSkillEntry` is the SwiftData model that records which skills an agent has enabled. At turn time, the agent loop fetches the active entries, resolves them back to `Skill` values, and composes:

- **System prompt** — active skills' `instruction` strings concatenated in
- **Tool set** — union of all active skills' `requiredTools`, registered with the tool executor

Activating or deactivating a skill takes effect on the next turn because the system prompt is rebuilt fresh each time.

`BundledSkill.alwaysActive` skills (`knowledge`, `intents`, `awareness`, `web`) are seeded into every new agent's active set automatically.

## Critical files

- `src/eigin_ios/Sources/Agent/Skill/Models/Skill.swift` — the value type
- `src/eigin_ios/Sources/Agent/Skill/Models/BundledSkill.swift` — all eight built-in skills
- `src/eigin_ios/Sources/Agent/Skill/Models/ActiveSkillEntry.swift` — the SwiftData model
