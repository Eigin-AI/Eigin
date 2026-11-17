# Write a news post

Posts appear on `/en/news/` and `/da/news/`, newest first. Each has a permanent URL and is included in RSS and the sitemap when the website is released.

1. Create `posts/<slug>/en.svx` and `posts/<slug>/da.svx`. Both translations are required. Keep published slugs unchanged.
2. Add a title, plain-text description, and quoted publication date:

```markdown
---
title: "Introducing Eigin"
description: "A short summary for RSS and search engines."
date: "2026-11-17"
---

Write the article here.

## A section

Continue with ordinary Markdown.
```

`.svx` is Markdown with optional Svelte components. The page supplies the title and date; start body headings at level two. Dates use UTC. Invalid or missing metadata fails the build.

Images, HTML video, and imported Svelte components can live alongside the post. Give images alt text and videos captions. Keep the article readable without JavaScript.

- Preview: `just run web site`, then open `http://localhost:5174/en/news/`.
- Check: `just test website`.
- Publish: follow the [website release guide](../../../../../../docs/src/runbooks/website-deployment.md).

Share `/news/<slug>/` to let the visitor’s browser language choose Danish or English.
