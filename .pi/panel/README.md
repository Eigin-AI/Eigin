# Virtual audience panel

Run `/eigin:panel` to list profiles. Use `/eigin:panel <neutral question>` to prepare a review,
or ask the assistant to call `review_panel` with explicit text and local files.

- Text files and PNG/JPEG/WebP/GIF images are supported. SVG is reviewed as text.
- Material files must resolve inside the workspace; symlinks to outside files are rejected.
- Material goes to the current session model provider. Each review starts fresh with no tools.
- Three reviewers run at a time; a separate call synthesizes their reactions.
- The synthesis gives quoted highlights, agreements, disagreements, potential actions, and real-user follow-ups.
- Private inputs and reports are saved under gitignored `.pi/panel/runs/`. Delete them manually when finished.

## Members

| ID           | Name    | Everyday life                                                                                   |
| ------------ | ------- | ----------------------------------------------------------------------------------------------- |
| techie       | Aisha   | 23, IT specialist in Herning; electronics hobbyist and aspiring AI specialist                   |
| nontechnical | Kirsten | 74, retired in Copenhagen; community gardener, volunteer, and local-history reader              |
| small-team   | Lene    | 55, office worker on Bornholm; small knowledge-work team, local associations, and coastal walks |
| manager      | Jonas   | 39, kitchen-team manager in Skanderborg; food, family, and a restaurant ambition                |
| student      | Emil    | 20, student in Odense; football, guitar, electronics, and software experiments                  |

Read the portraits in `personas/<id>.md`. Each tells a connected story about the person's
home, work, relationships, personality, interests, and experience with technology.
The model receives the portrait body. Frontmatter holds the stable ID, version,
short roster description, and source provenance; those fields stay out of its prompt.

## Source and authored development

Source: [syvai/danish-personas](https://huggingface.co/datasets/syvai/danish-personas),
by Dan Saattrup Smart, syv.ai. Revision: `f2384b12928a340cccf43e085780ad1a1e53451f`.
Original records are preserved in `sources/<record-id>.json`, retrieved through the
Hugging Face rows API with the dataset revision checked at selection time.

The source people are synthetic. Their demographics, relationships, occupations,
interests, and narrative temperament ground our portraits. Names, AI-use histories,
and additional everyday experiences are fictional development by Eigin.

| Portrait | Grounding and development                                                                                                                                                                                                                       |
| -------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Aisha    | Retains Herning, IT work, family in Pakistan, technical hobbies, and career ambitions. Source accounts conflict on upbringing; the portrait leaves birthplace and migration timing unspecified. AI experiments and working habits are authored. |
| Kirsten  | Retains Copenhagen, husband, retirement, gardening, volunteering, writing, and music. No former occupation is invented. The writing group, digital habits, family-assisted AI trial, and attitudes toward learning are authored.                |
| Lene     | Retains Bornholm, husband, small-business office work, local involvement, and hobbies. The six-person knowledge-work team, detailed coordination habits, and AI experience are authored.                                                        |
| Jonas    | Uses the kitchen-team leadership in the source narrative to interpret the ambiguous title `topchef`. Retains his wife, local food, gardening, hiking, and restaurant ambition. Management habits, software use, and AI trials are authored.     |
| Emil     | Retains Odense, student status, parents, sports, music, electronics, and software ambitions. No course or institution is invented. Study habits, limited budget, and AI-use experience are authored.                                            |

## Editing

- Develop the person from their source biography. Add plausible experiences without rewriting the archived record.
- Write a personal portrait rather than a product-evaluation checklist. Allow interests unrelated to Eigin.
- Keep fictional additions consistent; document substantial expansions in the table above.
- Avoid inferring skills or attitudes from demographic categories or personality scores.
- Keep IDs stable and increment `version` when changing a portrait.
- Saved runs preserve the exact profile text and prompt version; later edits leave those snapshots unchanged.

See `LICENSES/danish-personas/` for the source license, dataset card, and attribution.

## Verification

With Node 24 and Pi installed globally:

```sh
node --import ./.pi/extensions/eigin/tools/panel/test-loader.mjs \
  --experimental-strip-types --test \
  $(find .pi/extensions/eigin -name '*.test.ts' -print)
```

The loader resolves Pi's installed dependencies. Tests fake the provider boundary;
image decoding, Markdown profile loading, and filesystem operations are real.
Run `/reload` after changing the extension, then `/eigin:panel` to inspect the roster.
A complete five-member review makes six model calls, including synthesis.
