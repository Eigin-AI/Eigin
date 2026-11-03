# MingCute icons (third party)

These are **not** Eigin design assets. They are vendored from the MingCute
icon set to fill gaps the Eigin library does not cover.

- Source: https://github.com/Richard9394/MingCute
- Browse: https://icon-sets.iconify.design/mingcute/
- Author: MingCute Design
- Licence: Apache-2.0 (see `LICENSE` in this folder)
- Grid: 24x24, `fill` and `line` variants

## Why these exist

The Eigin icon library (`../brand`, `../functional`, `../illustration`) has no
lock, shield, key, chart or globe. `brand/security` is an abstract blob cluster
that reads as "dots" at card size, not as "secure". Rather than invent brand
assets, we borrow from a permissively licensed set that sits close to the Eigin
drawing style.

MingCute's `chat-1-fill` is nearly identical to Eigin's own `brand/chat_fill`,
which is what gave us confidence the two families mix without looking broken.

## Which variant to use

- `-fill` matches the weight of the Eigin **brand** icons (solid, soft, rounded).
  This is the default choice for card icons.
- `-line` matches the Eigin **functional** icons (outline strokes).

Do not mix `-fill` and `-line` within a single slide.

## Precedence rule

Prefer an Eigin icon when one exists and actually reads. Reach for MingCute only
when the Eigin library has no icon for the concept. Keep the
`illustration/` marks (bird, wave, snake...) as the decorative layer; they are a
different, organic family and are not interchangeable with either icon set.

`illustration/bird.svg` is reserved for Eigin itself.

## Adding another icon

This directory preserves legacy deck URLs. Add new shared icons to the design system instead:

1. Select an SVG from https://icon-sets.iconify.design/mingcute/.
2. Save the approved SVG under `design/assets/icons/functional/` with a descriptive name.
3. Retain the MingCute attribution in `LICENSES/vendored-assets.md` and its Apache-2.0 licence.
4. Run `just generate web`, then build and test the website.
5. Review and deploy. The generated website/slide registry and `/present/guide/icons/` catalogue update together.

Only add icons that are actually needed. Existing URLs in this folder remain supported.
