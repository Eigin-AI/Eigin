<script lang="ts">
  import { CodeBlock, Markdown } from "@lib";
  import DeviceFrame from "@gallery/frames/DeviceFrame.svelte";

  const swift = `// A long comment that runs past the card edge to demonstrate horizontal scrolling.
struct Sightseeing: Activity {
    let name = "Sightseeing"

    func perform(with sloth: inout Sloth) -> Speed {
        sloth.energyLevel -= 10
        return sloth.energyLevel > 0 ? .slow : .stopped
    }
}`;

  const json = `{ "model": "claude-opus-5", "temperature": 0.7, "stream": true }`;

  const table = `Here's how the models compare on this workload:

| Model | Speed | Cost | Notes |
| --- | :-: | --: | --- |
| Opus | Slow | $$$ | Best on long reasoning chains |
| Sonnet | Fast | $$ | The sensible default |
| Haiku | Fastest | $ | Short, cheap turns |

Sonnet is the sensible default.`;

  const document = `# Display heading

## Section heading

### Third level

Prose renders in the chat message style, with **bold**, *italic*, \`inline code\`
and [links](https://eigin.ai) resolving against it.

- A bulleted list item
- Another one, long enough to wrap onto a second line so the leading can be read
- A third

1. Ordered lists carry the same styling
2. With muted markers

> A block quote sits behind a border in the muted text colour.

\`\`\`typescript
export function greet(name: string): string {
  return \`Hello, \${name}\`;
}
\`\`\`

Display math renders through KaTeX:

$$\\int_0^\\infty e^{-x^2}\\,dx = \\frac{\\sqrt{\\pi}}{2}$$

---

Closing paragraph after a thematic break.`;
</script>

<div class="doc">
  <h2 class="t-titleM">Markdown</h2>
  <p class="lede t-description">
    Everything a reply can contain. Headings step down the title scale, the top two in caps. Prose,
    lists and quotes take the chat message style; blocks sit 16px apart.
  </p>
  <div class="canvas" data-demo="markdown">
    <DeviceFrame height="content" colorScheme="inherit">
      <div class="stack">
        <Markdown text={document} />
      </div>
    </DeviceFrame>
  </div>

  <h2 class="t-titleM">Table</h2>
  <p class="lede t-description">
    The same card as code, with a firmer rule under the header and lighter ones between cells.
    Columns are capped: a long cell wraps, and a wide table scrolls sideways.
  </p>
  <div class="canvas" data-demo="table">
    <DeviceFrame height="content" colorScheme="inherit">
      <div class="stack">
        <Markdown text={table} />
      </div>
    </DeviceFrame>
  </div>

  <h2 class="t-titleM">Code Block</h2>
  <p class="lede t-description">
    A card on the elevated surface. Long lines scroll rather than wrap, so code keeps its shape.
    Colours come from the code palette. The last card is still arriving — code stays uncoloured
    until the block closes.
  </p>
  <div class="canvas" data-demo="code">
    <DeviceFrame height="content" colorScheme="inherit">
      <div class="stack">
        <CodeBlock code={swift} language="swift" />
        <CodeBlock code={json} language="json" />
        <CodeBlock code={swift} language="swift" streaming />
      </div>
    </DeviceFrame>
  </div>
</div>

<style>
  .lede {
    max-width: 62ch;
    color: var(--color-text-standard-muted);
  }

  /* Stands in for a phone column, like the chat catalog. */

  .stack {
    display: flex;
    flex-direction: column;
    gap: var(--spacing-n16);
    padding: 0 var(--sizing-chat-px-large-mobile);
  }
</style>
