Closes #148

Show what a tool will do before the user approves it. Permission sheets now display a plain-language action and important arguments, so users can judge the requested action.

### Changes

- Show action descriptions for web tools and tools that write local or external data.
- Keep long arguments scrollable so approval buttons stay visible.
- Localize descriptions in English and Danish, including dates and numbers.

### Notes

Tools with opaque IDs keep generic descriptions for now. Resolving those IDs to readable labels is tracked in #149.

### How to Test

1. Run `ToolDisclosureTests`.
2. Trigger a web search and check that the permission sheet names the query.
3. Trigger an email send and check that the subject and body scroll while approval buttons stay visible.
4. Switch the device language to Danish and check a prompt again.
