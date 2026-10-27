# Editing the roadmap

Edit `data.ts`. No HTML changes are needed.

## Sections

- `active`: work in progress, in display order.
- `planned`: future work, in display order. No dates are required.
- `launched`: release groups, newest first. A month label is optional.

Move an item between `active`, `planned`, and a release group's `items` to change
its status. Keep its `id` unchanged so direct links keep working.
Every item ID must be unique across the page.

## Add an item

```ts
{
  id: "a-stable-item-id",
  copy: {
    en: {
      title: "Feature name",
      description: "One sentence about what it does for people.",
    },
    da: {
      title: "Funktionens navn",
      description: "En sætning om, hvad den gør for folk.",
    },
  },
}
```

Descriptions are optional. Danish item copy is optional. If it is missing, the
Danish page shows the English copy and marks that item as English for assistive
technology.

## Add a release

Insert a group at the start of `launched`, with a stable `id` and an `items` array.
Add a localized `period` only when a release month is known. An item can include
a version label and an optional link:

```ts
version: {
  label: "1.2",
  href: "https://code.eigin.ai/dev/eigin/-/releases/1.2",
},
```

Omit `href` to show a version as plain text. Dates and versions are display data;
the site does not invent or infer them.
An empty section shows its localized empty-state message.

The release workflow reviews this file and `data.ts` when preparing a release.
Only move an item to Launched when its availability is confirmed. Preparing a
release or tag does not establish that an App Store version is available.

## Description sources

- SDK: [GitLab issue #145](https://code.eigin.ai/dev/eigin/-/issues/145), the cross-platform Rust SDK migration plan.
- Web and Teams: the homepage copy in `../home/en.ts`.
- iOS: the [public homepage](https://www.eigin.ai), including model choice and on-device memory.
- Current item descriptions, including end-to-end encrypted agent sync and private Relay connectivity: supplied by the project owner during website review.

The current descriptions use the owner's reviewed wording. The references above provide background. Roadmap status does not imply that a
planned capability is already available.

## Page and navigation text

- `en.ts` and `da.ts`: page introduction, section labels, and notices.
- `../site/en.ts` and `../site/da.ts`: shared navigation and footer text.

## Check locally

From the repository root:

```sh
just run web site
just test website
```

Review `/en/roadmap/` and `/da/roadmap/`. Changes appear through the dev server;
production changes require a new static build.
