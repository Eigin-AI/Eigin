# Image input

Users can attach images to chat messages when the active model supports vision. Images are processed locally, stored on device, and sent inline to the provider.

## Sending an image

Tap the **+** button in the chat input bar to open the action sheet. When the current model supports vision, two image actions appear:

- **Take a Photo** — opens the device camera for live capture.
- **Attach an Image** — opens the photo library picker.

After selecting an image, a thumbnail appears above the input bar. You can remove a staged image before sending by tapping **×** on the thumbnail. Send the message as normal; the image travels with the text in the same turn.

## Model gating

Image actions are shown only when the current model's `supportsVision` capability is true. If you switch to a model that does not support vision while an image is staged, a notice appears and the staged image is discarded. See [Context management](#context-management) for how images already sent in earlier turns are handled.

## Storage

Image bytes are stored locally in `Application Support/ChatAttachments/`. They are never uploaded to any server directly — they are sent inline as base64 in each API request. When a chat is deleted, its attachment files are also removed.

Images are normalised on save:
- Maximum dimension: **1024 px** (keeps images well within model detail needs while keeping request payloads small).
- Re-encoded as **JPEG** at 85% quality.
- Original pixel data beyond these limits is discarded; the original file is not stored.

## Context management

To keep context windows bounded and prevent costs from escalating, images are not re-sent on every turn. The pipeline keeps images live in the outgoing request for the most recent **2 image-bearing turns**. Older image turns are replaced with a `[image omitted]` placeholder so the model still has a record that an image was shown.

When the active model does not support vision, all image content is stripped from the outgoing request regardless of turn age, keeping the chat compatible with text-only models.

## Provider support

| Provider | Image format |
|---|---|
| OpenAI-compatible (OpenAI, OpenRouter, Gemini, …) | `image_url` content-part with base64 data URL |
| Anthropic | `image` content block with base64 source |
| Local (Gemma, Apple on-device) | Not supported (tracked in [#127](https://code.eigin.ai/dev/eigin/-/issues/127)) |
