<script lang="ts">
  import {
    Button,
    ChatBrandMessage,
    ChatFeed,
    ChatUserMessage,
    ThinkingIndicator,
    ToolGroup,
    CompactionDivider,
    OptionsGroup,
    StreamThrottler,
    ChasingProgress,
    driveFrames,
  } from "@lib";
  import type { OptionChoice, ToolCall } from "@lib";
  import DeviceFrame from "@gallery/frames/DeviceFrame.svelte";
  import OptionSelector from "@gallery/catalog/OptionSelector.svelte";
  import { onDestroy } from "svelte";

  const dayOptions: OptionChoice[] = [
    {
      label: "Deep work",
      description: "Three hours, no interruptions",
      symbol: "illustration/mountain",
    },
    { label: "Catch up", description: "Clear the backlog first", symbol: "illustration/tree" },
    {
      label: "Get outside",
      description: "Walk before the weather turns",
      symbol: "illustration/bird",
    },
  ];

  let optionsRun = $state(0);
  let optionPicked = $state<string | null>(null);

  const singleTool: ToolCall[] = [{ id: "1", name: "Read note", status: "completed" }];

  const runningGroup: ToolCall[] = [
    { id: "1", name: "Read note", status: "completed" },
    { id: "2", name: "Search places", status: "executing" },
  ];

  const settledGroup: ToolCall[] = [
    { id: "1", name: "Read note", status: "completed" },
    { id: "2", name: "Search places", status: "completed" },
  ];

  const mixedGroup: ToolCall[] = [
    { id: "1", name: "Read note", status: "completed" },
    { id: "2", name: "Edit note", status: "completed" },
    { id: "3", name: "Send message", status: "awaitingPermission" },
    { id: "4", name: "Get directions", status: "error" },
  ];

  /* A live clock so the copy ladder can be watched climbing its rungs. */
  let started = $state(performance.now() / 1000);
  let stalled = $state(false);
  const restart = () => (started = performance.now() / 1000);

  /* How assistant text appears: a fed stream, revealed by the throttler. */
  const reply =
    "Yes — your calendar is clear after four. I've held the slot and drafted a note " +
    "to Mira so she knows the room is free. Say the word and I'll send it.";

  let revealed = $state("");
  let revealPhase = $state("idle");
  let modelSpeed = $state("steady");
  let stopReveal: (() => void) | undefined;
  let feedTimer: ReturnType<typeof setTimeout> | undefined;

  function playReveal() {
    stopReveal?.();
    clearTimeout(feedTimer);

    const throttler = new StreamThrottler();
    throttler.start();
    revealed = "";
    revealPhase = throttler.phase;

    // Chunks land at the model's pace; the throttler decides how they surface.
    const chunks = reply.match(/\S+\s*/g) ?? [];
    const perChunk = modelSpeed === "burst" ? 8 : 55;
    let next = 0;
    const feed = () => {
      if (next >= chunks.length) {
        throttler.finish();
        return;
      }
      // A bursty model delivers several tokens at once.
      const size = modelSpeed === "burst" ? 6 : 1;
      throttler.feed(chunks.slice(next, next + size).join(""));
      next += size;
      feedTimer = setTimeout(feed, perChunk);
    };
    feed();

    stopReveal = driveFrames(
      (t) => {
        throttler.tick(t);
        revealed = throttler.displayedText;
        revealPhase = throttler.phase;
      },
      () => throttler.phase !== "done",
    );
  }

  /* Compaction: a chased progress value behind the divider. */
  let compaction = $state<number | undefined>(undefined);
  let compactionSummary = $state<string | undefined>(undefined);
  let stopCompaction: (() => void) | undefined;
  let compactionTimer: ReturnType<typeof setTimeout> | undefined;

  const summaryText =
    "You planned a trip to Lisbon in May, chose a hotel in Alfama, and asked me to " +
    "keep an eye on flight prices from Copenhagen.";

  function playCompaction() {
    stopCompaction?.();
    clearTimeout(compactionTimer);

    const chaser = new ChasingProgress();
    compactionSummary = undefined;
    compaction = 0;

    // The real loop reports in jumps: started, streaming, done.
    chaser.setTarget(0.25);
    compactionTimer = setTimeout(() => chaser.setTarget(0.75), 900);
    setTimeout(() => chaser.setTarget(1), 2000);

    stopCompaction = driveFrames(
      (t) => {
        chaser.tick(t);
        compaction = chaser.value;
        if (chaser.isFinished) {
          compaction = undefined;
          compactionSummary = summaryText;
        }
      },
      () => !chaser.isFinished,
    );
  }

  onDestroy(() => {
    stopReveal?.();
    stopCompaction?.();
    clearTimeout(feedTimer);
    clearTimeout(compactionTimer);
  });

  const short = "Hello!";
  const long =
    "I'm trying to work out how the collapse behaviour should feel on the web. " +
    "Messages past two hundred characters start collapsed at a hundred and ten " +
    "points, with a soft fade at the bottom edge, and expand when you tap them. " +
    "This paragraph is deliberately long enough to trip that threshold.";
</script>

<div class="doc">
  <h2 class="t-titleM">User Message</h2>
  <p class="lede t-description">
    Right-aligned, in a bubble. Over 200 characters it starts collapsed under a fade and opens on
    tap.
  </p>
  <div class="canvas">
    <DeviceFrame height="content" colorScheme="inherit">
      <ChatFeed>
        <ChatUserMessage text={short} />
        <ChatUserMessage text={long} />
      </ChatFeed>
    </DeviceFrame>
  </div>

  <h2 class="t-titleM">Brand Message</h2>
  <p class="lede t-description">
    Left-aligned with no bubble — content sits directly on the background.
  </p>
  <div class="canvas">
    <DeviceFrame height="content" colorScheme="inherit">
      <ChatFeed>
        <ChatBrandMessage>
          <p class="t-chatMessage">Hello, how can I help?</p>
        </ChatBrandMessage>
        <ChatBrandMessage>
          <p class="t-chatMessage">
            This is a much longer assistant reply that shows how content flows across multiple lines
            in the brand message layout without any background bubble.
          </p>
        </ChatBrandMessage>
      </ChatFeed>
    </DeviceFrame>
  </div>

  <h2 class="t-titleM">Throttling</h2>
  <p class="lede t-description">
    Revealed at a steady pace whether the model trickles or bursts, and only on whole words, so a
    half-typed one never reflows the line.
  </p>
  <div class="controls">
    <OptionSelector options={["steady", "burst"]} bind:value={modelSpeed} />
    <Button label="Play reply" variant="secondary" size="extraSmall" onclick={playReveal} />
  </div>
  <div class="canvas">
    <DeviceFrame height="content" colorScheme="inherit">
      <ChatFeed>
        <ChatBrandMessage>
          <p class="t-chatMessage reveal" data-phase={revealPhase}>
            {revealed || "\u00a0"}
          </p>
        </ChatBrandMessage>
      </ChatFeed>
    </DeviceFrame>
  </div>

  <h2 class="t-titleM">Thinking Indicator</h2>
  <p class="lede t-description">
    The blob, plus copy that speaks up as the wait drags on — 4.5s, 11s, 18s, 29s, 44s. Waiting on
    the user parks the clock; the shape keeps moving.
  </p>
  <div class="controls">
    <Button label="Restart clock" variant="secondary" size="extraSmall" onclick={restart} />
    <Button
      label={stalled ? "Resume" : "Stall on user"}
      variant="secondary"
      size="extraSmall"
      onclick={() => (stalled = !stalled)}
    />
  </div>
  <div class="canvas">
    <DeviceFrame height="content" colorScheme="inherit">
      <ChatFeed>
        <ChatBrandMessage>
          <ThinkingIndicator shownAt={started} clockStart={stalled ? null : started} {stalled} />
        </ChatBrandMessage>
      </ChatFeed>
    </DeviceFrame>
  </div>

  <h2 class="t-titleM">Tools</h2>
  <p class="lede t-description">
    One tool sits inline. Groups collapse to the latest plus a count. Running breathes, waiting on
    permission takes the accent, failed turns red.
  </p>
  <div class="canvas">
    <DeviceFrame height="content" colorScheme="inherit">
      <ChatFeed>
        <ToolGroup tools={singleTool} />
        <ToolGroup tools={runningGroup} />
        <ToolGroup tools={mixedGroup} />
      </ChatFeed>
    </DeviceFrame>
  </div>

  <h2 class="t-titleM">Options</h2>
  <p class="lede t-description">
    A question put as cards. The question keeps the message inset; the cards run past the screen
    edge, so there is always another.
  </p>

  <div class="controls">
    <Button
      label={optionPicked ? `Picked: ${optionPicked}` : "Reset"}
      variant="secondary"
      size="extraSmall"
      onclick={() => {
        optionPicked = null;
        optionsRun += 1;
      }}
    />
  </div>

  <div class="canvas">
    <DeviceFrame height="content" colorScheme="inherit">
      {#key optionsRun}
        <OptionsGroup
          question="How should we spend the morning?"
          options={dayOptions}
          onSelect={(label) => (optionPicked = label)}
        />
      {/key}
    </DeviceFrame>
  </div>

  <h2 class="t-titleM">Compaction</h2>
  <p class="lede t-description">
    The seam where a conversation was summarised. The line fills at a capped speed, so it always
    travels rather than jumping, then settles into a rule you can open.
  </p>
  <div class="controls">
    <Button label="Run compaction" variant="secondary" size="extraSmall" onclick={playCompaction} />
  </div>
  <div class="canvas">
    <DeviceFrame height="content" colorScheme="inherit">
      <ChatFeed>
        <ChatUserMessage text="Let's pick up where we left off." />
        <CompactionDivider progress={compaction} summary={compactionSummary} />
        <ChatBrandMessage>
          <p class="t-chatMessage">Of course — Lisbon in May. Shall I check those fares now?</p>
        </ChatBrandMessage>
      </ChatFeed>
    </DeviceFrame>
  </div>

  <h2 class="t-titleM">Conversation</h2>
  <div class="canvas">
    <DeviceFrame height="content" colorScheme="inherit">
      <ChatFeed>
        <ChatUserMessage text="Where did we get to on the trip?" />
        <CompactionDivider summary={summaryText} />
        <ChatUserMessage text="Can you summarise the design tokens?" />
        <ToolGroup tools={settledGroup} />
        <ChatBrandMessage>
          <p class="t-chatMessage">
            They cover colour, typography, spacing, radius, stroke weight, sizing, grid and motion.
            Every platform reads the same file.
          </p>
        </ChatBrandMessage>
        <ChatUserMessage text={long} />
        <ChatBrandMessage>
          <ThinkingIndicator shownAt={started} clockStart={started} />
        </ChatBrandMessage>
      </ChatFeed>
    </DeviceFrame>
  </div>
</div>

<style>
  .controls {
    display: flex;
    gap: var(--spacing-n8);
    margin-bottom: var(--spacing-n16);
  }

  .reveal {
    margin: 0;
    color: var(--color-text-standard-base);
    text-box: normal;
  }

  .lede {
    max-width: 62ch;
    color: var(--color-text-standard-muted);
  }

  /* Stands in for a phone column; deliberately not the gallery's global
     .stage class, which is a centering flex container. The dashed edge is
     gallery chrome — it makes the asymmetric grid gutters legible. */
</style>
