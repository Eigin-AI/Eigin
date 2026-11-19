<script lang="ts">
  import { CheckboxButton } from "@eigin/ui";
  import Preview from "./Preview.svelte";
  import { marked, Renderer, type Token, type Tokens } from "marked";
  import sanitizeHtml from "sanitize-html";
  let { text = "", nodes }: { text?: string; nodes?: Token[] } = $props();
  const taskId = $props.id();
  const renderer = new Renderer();
  renderer.html = () => "";
  const tokens = $derived(nodes ?? marked.lexer(text));
  const html = (token: Token) =>
    sanitizeHtml(marked.parser([token], { renderer }), {
      allowedTags: [
        "p",
        "h1",
        "h2",
        "h3",
        "h4",
        "ul",
        "ol",
        "li",
        "blockquote",
        "pre",
        "code",
        "strong",
        "em",
        "a",
        "hr",
        "br",
        "table",
        "thead",
        "tbody",
        "tr",
        "th",
        "td",
      ],
      allowedAttributes: {
        a: ["href", "title"],
      },
      allowedSchemes: ["https", "http", "mailto"],
      allowProtocolRelative: false,
    });
</script>

<div class="prose">
  {#each tokens as token, blockIndex}
    {#if token.type === "blockquote"}
      <blockquote><Preview nodes={token.tokens} /></blockquote>
    {:else if token.type === "list"}
      <svelte:element
        this={token.ordered ? "ol" : "ul"}
        start={token.ordered ? token.start : undefined}
        class:markdown-tasks={token.items.some(
          (item: Tokens.ListItem) => item.task,
        )}
      >
        {#each token.items as item, index}
          <li>
            {#if item.task}
              {@const body = item.tokens.filter(
                (node: Token) => node.type !== "checkbox",
              )}
              <div class="markdown-task">
                <span
                  class="task-marker"
                  role="checkbox"
                  aria-checked={!!item.checked}
                  aria-disabled="true"
                  aria-labelledby={`${taskId}-${blockIndex}-${index}`}
                  tabindex="-1"
                >
                  <span aria-hidden="true"
                    ><CheckboxButton
                      label=""
                      isChecked={!!item.checked}
                      disabled
                      size="small"
                      variant="outline"
                    /></span
                  >
                </span>
                <div id={`${taskId}-${blockIndex}-${index}`}>
                  <Preview nodes={body} />
                </div>
              </div>
            {:else}<Preview nodes={item.tokens} />{/if}
          </li>
        {/each}
      </svelte:element>
    {:else}{@html html(token)}{/if}
  {/each}
</div>

<style>
  .markdown-tasks {
    padding: 0;
    list-style: none;
  }
  .markdown-task {
    display: grid;
    grid-template-columns: max-content minmax(0, 1fr);
    align-items: start;
    gap: var(--spacing-n12);
  }
  .task-marker {
    display: grid;
    place-items: center;
    block-size: 1lh;
  }
  .task-marker > span {
    display: flex;
  }
  .task-marker :global(.eigin-btn) {
    padding: 0;
    height: auto;
    min-height: 0;
    border: 0;
    background: transparent;
  }
</style>
