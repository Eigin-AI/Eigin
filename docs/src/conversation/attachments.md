# Attachments

A user message can carry attachments alongside its text. Eigin processes and stores them on the device, then sends them inline with the message to the provider. Today there is one kind, images, with room for more.

## Storage

Attachment bytes live locally under `Application Support/ChatAttachments/` and are never uploaded on their own: they travel inline as base64 in each request. Deleting a chat removes its attachments.

## Images

Images are the one attachment kind today. When the active model supports vision, the user can attach a photo, taken with the camera or picked from the library. Each image is normalised on save: scaled to a maximum dimension of 1024 px, re-encoded as JPEG at 85% quality, and the original discarded.

## Eviction from context

Attachments are heavy, so they aren't re-sent every turn. Images stay live for the most recent **2 image-bearing turns**; older ones are replaced with an `[image omitted]` placeholder, so the model still knows one was shown. On a model without vision, image content is stripped entirely.

## Model support

| Model | Images |
|---|---|
| Cloud (OpenAI-compatible) | `image_url` part with base64 data URL |
| Cloud (Anthropic) | `image` block with base64 source |
| Local (Gemma, Apple on-device) | Not yet, tracked in [#127](https://code.eigin.ai/dev/eigin/-/issues/127) |
