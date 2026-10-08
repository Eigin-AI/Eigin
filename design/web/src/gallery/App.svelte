<script lang="ts">
  import { onMount } from "svelte";
  import { ActionButton, EiginRoot, OptionPicker, SegmentedControl } from "@lib";
  import ScreenPlaceholder from "@gallery/screens/ScreenPlaceholder.svelte";
  import DeviceFrame from "@gallery/frames/DeviceFrame.svelte";
  import { devices } from "@gallery/frames/devices";
  import { catalogEntries } from "@gallery/catalog/index";
  import { screenEntries, screenSections } from "@gallery/screens/index";
  import { stageControls } from "@gallery/screens/stageControls.svelte";

  type Route =
    { kind: "home" } | { kind: "component"; id: string } | { kind: "screen"; id: string };

  function parseHash(): Route {
    const hash = location.hash.replace(/^#\/?/, "");
    const [kind, id] = hash.split("/");
    if (kind === "components" && id) return { kind: "component", id };
    if (kind === "screens" && id) return { kind: "screen", id };
    return { kind: "home" };
  }

  let route: Route = $state(parseHash());
  let colorScheme = $state<"light" | "dark" | "system">("system");

  let deviceId = $state(devices[0].id);
  let configurationId = $state(devices[0].configurations[0].id);

  const schemes = [
    { value: "light", label: "Light" },
    { value: "dark", label: "Dark" },
    { value: "system", label: "Auto" },
  ];

  /* One fold per group, and a group with nothing in it is not drawn — so the
     list grows by an entry in a registry, not by a branch in here. */
  const sections = [
    { title: "Fundamentals", href: "components", entries: catalogEntries, group: "fundamentals" },
    { title: "Components", href: "components", entries: catalogEntries, group: "components" },
    ...screenSections.map((section) => ({
      title: section.title,
      href: "screens",
      entries: screenEntries,
      group: section.id,
    })),
  ]
    .map(({ title, href, entries, group }) => ({
      title,
      options: entries
        .filter((entry) => entry.section === group)
        .map((entry) => ({ label: entry.title, value: `#/${href}/${entry.id}` })),
    }))
    .filter((section) => section.options.length > 0);

  const page = $derived.by(() => {
    const here = route;
    if (here.kind !== "component") return undefined;
    return catalogEntries.find((entry) => entry.id === here.id)?.component;
  });

  const entry = $derived.by(() => {
    const here = route;
    if (here.kind !== "screen") return undefined;
    return screenEntries.find((candidate) => candidate.id === here.id);
  });

  const screen = $derived(entry?.component);

  /* A screen belongs to one form factor — the watch companion is not a small
     iPhone — so the stage offers only the device that screen runs on. */
  const availableDevices = $derived(
    devices.filter((candidate) => candidate.id === (entry?.device ?? devices[0].id)),
  );
  const device = $derived(
    availableDevices.find((candidate) => candidate.id === deviceId) ?? availableDevices[0],
  );
  /* A device may not offer the configuration the last one did. */
  const configuration = $derived(
    device.configurations.find((candidate) => candidate.id === configurationId) ??
      device.configurations[0],
  );

  /* watchOS has no light mode, so the watch frame is always dark — a light
     watch screen would mislead every decision made against it. */
  const isWatch = $derived(configuration.shape === "watch");

  const deviceSegments = $derived(
    availableDevices.map((candidate) => ({ value: candidate.id, label: candidate.label })),
  );
  const configurationSegments = $derived(
    device.configurations.map((candidate) => ({ value: candidate.id, label: candidate.label })),
  );

  const controls = stageControls();

  /* A grid is a thing you hold against a real layout, so it is a switch on the
     stage rather than a diagram on its own page. */
  let grid = $state(false);

  const currentHref = $derived(
    route.kind === "component"
      ? `#/components/${route.id}`
      : route.kind === "screen"
        ? `#/screens/${route.id}`
        : "",
  );

  onMount(() => {
    const onHash = () => (route = parseHash());
    window.addEventListener("hashchange", onHash);
    return () => window.removeEventListener("hashchange", onHash);
  });
</script>

<EiginRoot {colorScheme}>
  <div class="gallery">
    <nav class="sidebar">
      <h1 class="t-titleS">Eigin design gallery</h1>

      <SegmentedControl
        segments={schemes}
        selection={colorScheme}
        onSelect={(next) => (colorScheme = next as typeof colorScheme)}
      />

      <!-- The sidebar is a set of pickers: each section folds out its pages,
           and the header names the one you are on. -->
      {#each sections as section, index (section.title)}
        <OptionPicker
          title={section.title}
          options={section.options}
          selection={currentHref}
          initiallyExpanded={section.options.some((option) => option.value === currentHref) ||
            (currentHref === "" && index === 0)}
          onSelect={(href) => (location.hash = href)}
        />
      {/each}
    </nav>

    <main class="content">
      {#if route.kind === "component"}
        {#if page}
          {@const Page = page}
          <Page />
        {/if}
      {:else if route.kind === "screen"}
        <div class="stage">
          <!-- The grid rides in the corner, out of the picker column. -->
          <div class="stage-tools">
            <ActionButton
              icon="functional/grid"
              variant={grid ? "spot" : "secondary"}
              size="medium"
              label={grid ? "Hide the grid" : "Show the grid"}
              onclick={() => (grid = !grid)}
            />
          </div>

          <div class="device-picker">
            <SegmentedControl
              segments={deviceSegments}
              selection={deviceId}
              onSelect={(next) => (deviceId = next)}
            />
            <SegmentedControl
              segments={configurationSegments}
              selection={configuration.id}
              onSelect={(next) => (configurationId = next)}
            />

            <!-- Whatever the screen itself wants to drive, kept off the phone. -->
            {#if controls.controls}
              {@render controls.controls()}
            {/if}
          </div>

          <DeviceFrame
            colorScheme={isWatch ? "dark" : colorScheme}
            width={configuration.width}
            height={configuration.height}
            safeAreaTop={configuration.safeAreaTop}
            safeAreaBottom={configuration.safeAreaBottom}
            safeAreaLeft={configuration.safeAreaLeft}
            safeAreaRight={configuration.safeAreaRight}
            shape={configuration.shape ?? "phone"}
            {grid}
          >
            {#if screen}
              {@const Screen = screen}
              <!-- Keyed, so pages sharing a component each start fresh. -->
              {#key entry?.id}
                <Screen {...entry?.props} />
              {/key}
            {:else}
              <ScreenPlaceholder id={route.id} />
            {/if}
          </DeviceFrame>

          <!-- What the screen is for, in a sentence or two. It sits under the
               phone rather than in the sidebar: you read it while looking at
               the thing it describes. -->
          {#if entry?.about}
            <p class="t-description stage-about">{entry.about}</p>
          {/if}
        </div>
      {:else}
        <div class="doc">
          <h2 class="t-titleM">Eigin design gallery</h2>
          <p class="lede t-description">
            Pick a component or a screen from the sidebar. Tokens come from
            <code>design/tokens.json</code> via <code>just generate</code>.
          </p>
        </div>
      {/if}
    </main>
  </div>
</EiginRoot>
