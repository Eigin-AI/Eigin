## [0.14.0] - 2026-06-12

### Features

- Button component system (UI Kit v0.3)
- Chat input bar component (UI Kit v0.3)
- In-app feedback sheet
- Rebalance model preference list to prioritise reliable Western models
- Replace Scaleway/OVHcloud with Berget and Infercom
- Agent option cards
- Friendlier error cards and detail sheet
- Request notification permission and hint when initiative is reactive
- Apple Maps integration for agent spatial awareness
- Rework food skill into broader health skill
- Permanent intents with tasks, events, and schedules
- Word-level stream throttling for chat

### Bug Fixes

- Onboarding polish, error handling, and background download notifications
- Revert FluidAudio TTS to last known working state
- Add startup audio buffering and align TTS thread priorities
- Constrain get_reminders with default ±28 day window and fix include_completed+date range bug (#41)
- Rename knowledge tool "fields" → "data" and improve error feedback (#43)
- Local model in provider list shows status instead of generic text
- Enable file-based logging by default
- Auto-trigger local model compilation on app foreground (#56)
- Drop download notifications and update onboarding copy
- Eliminate layout pop when streaming text swaps to committed message
- Revert model auto compile as it was causing stability issues
- Ensure app icons don't have transparency channel
- Typo in OAuth callback URL
- Improved local model management
- Eliminate dictation-driven re-render cascade in ChatFeed
- Gate local model on device RAM, consolidate device info service
- Local model badge shows 'not downloaded' when it is
- Prewarm local model on new builds
- Seed user and agent actor knowledge entries on onboarding completion
- Update model catalog (#72)
- Migrate food database client to Search-a-licious API (#76)
- Food log query ignoring date parameter
- Don't show an error card when the user cancels a run
- Surface insufficient-resources error for local model instead of crashing

### Styling

- Design tokens for UI kit v0.3
- Text input component (UI Kit v0.3)
- Bottom sheet component (UI Kit v0.3)
- Generated iconography, navigation header, brand avatar
- Decrease size of message font
- Replace native TabView with custom navigation bar
- Replace toolbar with design-system header, fix line spacing
- OpenType font feature support
- Chat input bar with sheet-based interactions
- Integrate design component messages into chat feed
- Hide deep views and refresh provider flows
- Improve look and feel of asset download sheet
- Update color tokens
- Generate app icon from SVG with light/dark/tinted variants
- Refine onboarding copy to clarify local model as starting point
- Update mdbook style
- Update Eigin logo
- Update docs branding
- Implement AppCard and AppVisualCard UI components
## [0.13.0] - 2026-05-12

### Features

- Migrate Eigin Relay to Scaleway
- Design token system

### Bug Fixes

- Deal with preparation state for dictation
- Show dictation stream view also when preparing
- Anticipate odd MCP configs
- Some translations had "new" status making them fall back to key name
- Incorrect format specifier for space chat count localization
- Empty replies in live call now direct back to listening phase

### Refactor

- Absorb one-off scripts into a tools CLI

### Styling

- Collapse long user messages in chat feed
- Prevent text from floating around when expanding a chat message
