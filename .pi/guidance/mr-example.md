Closes #148

Permission prompts now show what a tool will do.

### Summary

Before, the permission sheet only said _"{agent} wants to use {tool}"_. While a user could decide if they agreed with a tool being used, they could not assess whether the tool was used _correctly_.

Tool permission sheets now show a plain-language action phrase and optionally important arguments, for review before approving.

This MR is scoped to disclosure UX only.

### Changes

- Optional `Tool.disclosure(for:)` contract, used with `PermissionRequest`.
- Sheet renders the action phrase; long ones go in a scrollable card.
- Disclosures added for web tools and all Tier 1/2 external and local-write tools.

### Related

- CASA compliance: blocks #142
- Single search provider: #178

### Notes

- Opaque-ID tools stay generic for now. More advanced label resolution is deferred to its own follow-up (#149).
- All action phrases are localized (en + da), with locale-aware dates and numbers.
- One hardcoded literal left: `cc:` in `email_send` (assuming this is a global convention).

### How to Test

1. Run `ToolDisclosureTests`.
2. In a chat, trigger a web search → sheet reads "(agent) wants to search the web for (query)".
3. Trigger an email send → subject + body in the scrollable card, buttons stay grouped, sheet doesn't clip.
4. Switch device language to Danish and re-check a prompt.
