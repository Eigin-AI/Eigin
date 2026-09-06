# App Store screenshots

Screenshots for the Apple App Store are generated and prepared with fastlane.
One command rebuilds all six:

```
just release ios staging screenshots
```

They land in `src/eigin_ios/fastlane/screenshots/en-US/`, sized for the
6.9-inch iPhone (1320 × 2868), in listing order. The PNGs are not committed.
Upload with `just release ios production sync-screenshots`.

## How a scene is staged

`EiginDev` accepts `--screenshot-scenario <name>` at launch. The installer
swaps in an in-memory store, registers fakes for network and permission
services, and presents the scene. Everything lives in
`Sources/App/Debug/Screenshots/`, which the App Store target never compiles.

## Scenes are view-only

A chat scene is a list of `ChatItem` values. `ScreenshotCanvas` renders them
with the same row views the real feed uses, top-aligned like a fresh send.
`asks-first` presents the real permission sheet over the canvas; `connections`
renders the real `ConnectionsView` over fake providers.

## Writing scene copy

Store screenshots are read in about a second, so each one is a single turn
that stands on its own:

- The user's message is first under the header, and carries its own context.
- The reply follows from that message. Anything the assistant knows beyond it
  reads as memory ("You mentioned...").
- The last visible line is the one worth quoting.
- Short user messages, plain replies, no em dashes, fictional names.

One hard limit: the `care` scene ends on option cards, so the text above them
fits in about three lines. Line wrapping decides — check the capture.

## Adding a scene

1. Create `Screenshot<Name>Scene.swift` in `Sources/App/Debug/Screenshots/`:

   ```swift
   /// One self-contained turn: user message, then reply.
   enum ScreenshotDeliverScene {
       static let chatTitle = "Delivery"

       static var items: [ChatItem] {
           [
               .message(id: "user", role: "user", content: "Where's my parcel?"),
               .message(id: "reply", role: "assistant", content: "Out for delivery."),
           ]
       }
   }
   ```

   Tool rows use `toolCall` from `ScreenshotFixtures`; attachments go on the
   user message. For anything past a plain chat (option cards, permission
   sheet, non-chat scenes) copy the closest existing scene instead of
   inventing a new pattern.

2. Add the case to `ScreenshotScene` in `Sources/App/ScreenshotMode.swift`.
3. Route it in `ScreenshotSceneRoot`.
4. Add a test to `EiginUITests/ScreenshotsUITests.swift`. Its `index:` sets
   both the filename and the App Store listing order, so renumber the others
   to keep the sequence contiguous.
5. New files need `just generate` for xcodegen to pick them up. Then run the
   lane and eyeball the output — the copy rules above are what to check for.
