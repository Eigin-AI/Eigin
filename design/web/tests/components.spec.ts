import { expect, test } from "@playwright/test";

/* Components behaviour, as rendered in the gallery. */

test("long user messages collapse to four line boxes and expand fully", async ({ page }) => {
  await page.goto("/#/components/chat");
  const bubble = page.locator("button.bubble.long").first();
  const body = bubble.locator(".body");
  await expect(bubble).toHaveAttribute("aria-expanded", "false");

  const checkCollapsed = async () => {
    const dimensions = await body.evaluate((element) => {
      const style = getComputedStyle(element);
      return {
        height: element.getBoundingClientRect().height,
        lineHeight: parseFloat(style.lineHeight),
        mask: style.maskImage,
      };
    });
    expect(dimensions.height).toBeCloseTo(4 * dimensions.lineHeight, 0);
    expect(dimensions.mask).toContain(`${dimensions.lineHeight}px`);
  };
  await checkCollapsed();
  // The preview and fade follow a changed typography token without JS measurements.
  await body.evaluate((element) => {
    element.style.lineHeight = "30px";
  });
  await page.waitForTimeout(500);
  await checkCollapsed();

  await bubble.click();
  await expect(bubble).toHaveAttribute("aria-expanded", "true");
  await expect
    .poll(() => body.evaluate((element) => Math.abs(element.clientHeight - element.scrollHeight)))
    .toBeLessThanOrEqual(1);
  await expect(body).toHaveCSS("mask-image", "none");
  await bubble.click();
  await expect(bubble).toHaveAttribute("aria-expanded", "false");
  await page.waitForTimeout(500);
  await checkCollapsed();
});

test("a user message never clips the text it wraps", async ({ page }) => {
  await page.goto("/#/components/chat");
  const bubble = page.locator(".bubble").first();
  await expect(bubble).toBeVisible();

  // Ascenders and descenders must sit inside the box the bubble clips to.
  const clipped = await bubble.locator(".body").evaluate((el) => ({
    scroll: el.scrollHeight,
    client: el.clientHeight,
  }));
  expect(clipped.scroll).toBeLessThanOrEqual(clipped.client);
});

test("tool groups line up with the brand messages around them", async ({ page }) => {
  await page.goto("/#/screens/chat");

  // Swift pads the feed's tool group with the same breakpoint.inner as a message.
  const inset = (selector: string) =>
    page
      .locator(selector)
      .first()
      .evaluate((el) => getComputedStyle(el).paddingLeft);

  expect(await inset(".tool-group")).toBe(await inset(".brand-message"));
});

test("options cards dim their siblings before the run leaves", async ({ page }) => {
  await page.goto("/#/components/cards");

  // Stretch the two phases out: WebKit can cross the real 150ms window
  // between animation frames, making the ordering unobservable.
  await page.addStyleTag({ content: ":root { --motion-fast: 800ms; --motion-normal: 400ms; }" });

  const carousel = page.locator(".carousel");
  const slots = carousel.locator(".slot");
  // Three choices plus the way out.
  await expect(slots).toHaveCount(4);
  await expect(slots.nth(3)).toContainText("Something else");

  await page.getByRole("button", { name: /Start small/ }).click();

  // The chosen card holds while the others fall back — nothing vanishes at once.
  await expect
    .poll(async () => slots.nth(1).evaluate((el) => Number(getComputedStyle(el).opacity)))
    .toBeLessThan(0.5);
  expect(await slots.nth(0).evaluate((el) => Number(getComputedStyle(el).opacity))).toBeGreaterThan(
    0.9,
  );

  // Only then does the whole run go.
  await expect
    .poll(async () => carousel.evaluate((el) => Number(getComputedStyle(el).opacity)))
    .toBeLessThan(0.1);
  await expect(page.getByRole("button", { name: /^Picked: Start small/ })).toBeVisible();
});

test("the way out can be withheld", async ({ page }) => {
  await page.goto("/#/components/cards");

  await page.getByRole("radio", { name: "withheld", exact: true }).click();
  await expect(page.locator(".carousel .slot")).toHaveCount(3);
  await expect(page.locator(".carousel")).not.toContainText("Something else");
});

test("a content group divides every member, not just its rows", async ({ page }) => {
  await page.goto("/#/screens/settings");

  // The general group mixes a picker with a row, as iOS settings does.
  const general = page.locator(".eigin-rows").first();
  const members = general.locator("> *");
  await expect(members).toHaveCount(2);

  const hairline = (index: number) =>
    members.nth(index).evaluate((el) => {
      const before = getComputedStyle(el, "::before");
      return { height: before.height, left: before.left };
    });

  // Nothing above the first member, a hairline above the second.
  expect((await hairline(0)).height).not.toBe("1px");
  expect(await hairline(1)).toEqual({ height: "1px", left: "24px" });
});

test("a pressed card fades rather than washing over", async ({ page }) => {
  await page.goto("/#/components/cards");
  await page.getByText("tappable", { exact: true }).nth(1).click();

  const card = page.locator(".visual").first();
  await expect(card).toHaveClass(/tappable/);
  await card.scrollIntoViewIfNeeded();

  const box = (await card.boundingBox())!;
  await page.mouse.move(box.x + box.width / 2, box.y + box.height / 2);
  await page.mouse.down();

  // Swift's `.buttonStyle(.plain)` fades the card; a dark wash cooled it.
  // The fade is a transition, so let it land rather than reading the first frame.
  await expect
    .poll(() => card.evaluate((el) => Number(getComputedStyle(el).opacity)))
    .toBeLessThan(1);

  await page.mouse.up();
});

test("a control does not select its own label", async ({ page }) => {
  await page.goto("/#/components/cards");
  await page.getByText("tappable", { exact: true }).nth(1).click();

  const card = page.locator(".visual").first();
  await expect(card).toHaveClass(/tappable/);

  const selectable = await card.evaluate((el) => {
    const style = getComputedStyle(el);
    // WebKit honours the prefixed property and leaves the standard one at "text".
    return style.webkitUserSelect || style.userSelect;
  });
  expect(selectable).toBe("none");
});

test("the sidebar only draws groups with navigable entries", async ({ page }) => {
  await page.goto("/#/screens/chat");

  const sidebar = page.getByRole("navigation");
  await expect(sidebar.getByRole("button", { name: /^Chats/ })).toHaveAttribute(
    "aria-expanded",
    "true",
  );
  await expect(sidebar.getByRole("radio", { name: "Chat", exact: true })).toHaveAttribute(
    "aria-checked",
    "true",
  );

  const groups = sidebar.locator(".disclosure");
  expect(await groups.count()).toBeGreaterThan(0);
  for (const group of await groups.all()) {
    await expect(group.getByRole("radio", { includeHidden: true })).not.toHaveCount(0);
  }
});

test("the segmented indicator sits on the selected segment, whatever its width", async ({
  page,
}) => {
  await page.goto("/#/components/assets");

  // Eight labels of very different lengths, so equal-share maths would drift.
  // Measured after layout settles, so poll rather than read the first frame.
  const drift = () =>
    page.evaluate(() => {
      // The page's own picker, not the scheme toggle in the sidebar.
      const track = document.querySelector(".doc .track")!;
      const indicator = track.querySelector(".indicator")!.getBoundingClientRect();
      const selected = track.querySelector("[aria-checked='true']")!.getBoundingClientRect();
      return Math.max(
        Math.abs(indicator.left - selected.left),
        Math.abs(indicator.width - selected.width),
      );
    });

  await expect.poll(drift).toBeLessThan(2);
});

test("an asset row shows the transfer as numbers, not a spinner", async ({ page }) => {
  await page.goto("/#/components/assets");

  const row = page.locator(".asset").first();
  await expect(row.locator(".meta")).toHaveText("62% · 42 s left");

  // The arc is drawn to the same fraction the text claims.
  const drawn = await row.locator(".arc").evaluate((el: SVGCircleElement) => {
    const total = Number(el.getAttribute("stroke-dasharray")!.split(" ")[0]);
    return 1 - Number(el.getAttribute("stroke-dashoffset")) / total;
  });
  expect(drawn).toBeCloseTo(0.62, 2);
});

test("a sheet caps long content below the safe area and hugs filtered content", async ({
  page,
}) => {
  await page.goto("/#/screens/add-integration");

  const sheet = page.getByRole("dialog");
  await expect(sheet).toBeVisible();
  await page.evaluate(() => document.fonts.ready);
  await expect
    .poll(() => sheet.evaluate((el) => new DOMMatrix(getComputedStyle(el).transform).m42))
    .toBe(0);

  const room = await sheet.evaluate((el) => {
    const screen = el.closest(".device-screen")!;
    const frame = screen.getBoundingClientRect();
    const box = el.getBoundingClientRect();
    const style = getComputedStyle(screen);
    const scale = frame.height / screen.clientHeight;
    const safeTop = parseFloat(style.getPropertyValue("--eigin-safe-area-top"));
    const gap = parseFloat(style.getPropertyValue("--spacing-n32"));
    return {
      clearance: (box.top - frame.top) / scale,
      height: box.height / scale,
      physicalHeight: box.height,
      cap: screen.clientHeight - safeTop - gap,
      safeTop,
      gap,
    };
  });

  // The full catalogue reaches the cap and scrolls inside the sheet.
  expect(room.clearance).toBeCloseTo(room.safeTop + room.gap, 0);
  expect(room.height).toBeCloseTo(room.cap, 0);
  const scroll = sheet.locator(".scroll");
  await expect
    .poll(() => scroll.evaluate((el) => el.scrollHeight - el.clientHeight))
    .toBeGreaterThan(0);

  // Filtering to one result restores content-hugging without clipping rows.
  await sheet.getByPlaceholder("Search integrations").fill("Google");
  await expect(
    sheet.getByRole("button", { name: "Google Gmail, Calendar and Contacts" }),
  ).toBeVisible();
  await expect
    .poll(() => sheet.evaluate((el) => el.getBoundingClientRect().height))
    .toBeLessThan(room.physicalHeight);
  await expect
    .poll(() => scroll.evaluate((el) => el.scrollHeight - el.clientHeight))
    .toBeLessThanOrEqual(1);
  const address = await sheet.getByRole("button", { name: "Connect by address" }).boundingBox();
  const body = await scroll.boundingBox();
  expect(address!.y + address!.height).toBeLessThanOrEqual(body!.y + body!.height + 1);
});

test("a typography class decides the family, and nothing overrides it", async ({ page }) => {
  await page.goto("/#/screens/agent");

  // A button carries the UA's own font, so a reset handing it `inherit` beat
  // the class and dropped the agent's name into the serif body face.
  const family = await page.evaluate(() => {
    const name = document.querySelector(".device-screen .name")!;
    const probe = document.createElement("span");
    probe.className = "t-titleM";
    document.body.appendChild(probe);
    const expected = getComputedStyle(probe).fontFamily;
    probe.remove();
    return { actual: getComputedStyle(name).fontFamily, expected };
  });

  expect(family.actual).toBe(family.expected);
});

test.describe("compaction", () => {
  test("unfolds the summary instead of snapping it open", async ({ page }) => {
    await page.goto("/#/components/chat");
    const divider = page.locator(".compaction").last();
    const fold = divider.locator(".summary-fold");
    await expect(divider).toBeVisible();
    // Closed: folded flat, so it takes no room in the feed.
    expect(await fold.evaluate((el) => el.getBoundingClientRect().height)).toBe(0);

    await divider.getByRole("button").click();

    // Sample mid-flight: the fold must travel, not jump to its full height.
    const heights: number[] = [];
    for (let i = 0; i < 10; i++) {
      heights.push(await fold.evaluate((el) => el.getBoundingClientRect().height));
      await page.waitForTimeout(25);
    }

    const settled = Math.max(...heights);
    expect(settled).toBeGreaterThan(20);
    const partway = heights.filter((h) => h > 0 && h < settled - 1);
    expect(partway.length).toBeGreaterThan(1);
  });
});

test.describe("tool group", () => {
  test("renders single tools bare and groups collapsed", async ({ page }) => {
    await page.goto("/#/components/chat");
    const groups = page.locator(".tool-group");
    await expect(groups.first()).toBeVisible();

    // A lone tool carries no collapse chrome.
    await expect(groups.nth(0).locator(".chevron")).toHaveCount(0);
    await expect(groups.nth(1).locator(".chevron")).toHaveCount(1);

    // Collapsed groups show the most recent tool and a count.
    const summary = groups.nth(2).locator(".summary");
    await expect(summary).toContainText("Get directions failed");
    await expect(summary).toContainText("(4)");

    // Expanding must grow downwards only: the header keeps its size and its
    // position within the group. Measured relatively, since clicking scrolls.
    const header = () =>
      groups.nth(2).evaluate((group) => {
        const summaryBox = group.querySelector(".summary")!.getBoundingClientRect();
        return {
          height: summaryBox.height,
          offset: summaryBox.top - group.getBoundingClientRect().top,
        };
      });

    const before = await header();
    await summary.click();
    await expect(groups.nth(2).locator(".count-label")).toHaveText("4 tools used");
    await expect(groups.nth(2).locator(".rows .tool-row")).toHaveCount(4);
    const after = await header();
    expect(after.height).toBeCloseTo(before.height, 1);
    expect(after.offset).toBeCloseTo(before.offset, 1);
  });
});

test.describe("code and markdown", () => {
  test("highlights code from the palette and skips it while streaming", async ({ page }) => {
    await page.goto("/#/components/content");
    const blocks = page.locator('[data-demo="code"] .code-block');
    await expect(blocks.first()).toBeVisible();

    // Tokens are highlighted, and take their colour from the code palette.
    await expect(blocks.nth(0).locator("span[class^=hljs]").first()).toBeVisible();
    const keyword = await blocks
      .nth(0)
      .locator(".hljs-keyword")
      .first()
      .evaluate((el) => getComputedStyle(el).color);
    expect(keyword).toBe("rgb(74, 122, 82)");

    // Streaming code renders plain: re-tokenising every chunk is wasted work.
    await expect(blocks.nth(2).locator("span")).toHaveCount(0);
  });

  test("renders tables as cards with capped columns", async ({ page }) => {
    await page.goto("/#/components/content");
    const card = page.locator('[data-demo="table"] .table-card');
    await expect(card).toBeVisible();

    // The app's own table, not the browser's default.
    await expect(page.locator(".markdown table")).toHaveCount(0);
    await expect(card).toBeVisible();
    await expect(card.locator(".cell.header").first()).toHaveClass(/t-miniLabel/);

    // A long cell wraps at the column cap rather than stretching the table.
    const notes = card.locator(".cell", { hasText: "Best on long" }).first();
    const width = (await notes.boundingBox())?.width ?? 0;
    expect(width).toBeLessThanOrEqual(241);
  });

  test("renders markdown blocks with token typography", async ({ page }) => {
    await page.goto("/#/components/content");
    const markdown = page.locator('[data-demo="markdown"] .markdown');
    await expect(markdown).toBeVisible();

    for (const selector of ["h1", "h2", "blockquote", "hr", ".katex", ".code-block"]) {
      await expect(markdown.locator(selector).first()).toBeVisible();
    }

    // H1 and H2 uppercase through CSS, leaving the text itself intact.
    const h1 = markdown.locator("h1");
    await expect(h1).toHaveClass(/t-titleXl/);
    expect(await h1.evaluate((el) => getComputedStyle(el).textTransform)).toBe("uppercase");
    expect(await h1.textContent()).toBe("Display heading");
  });
});

test.describe("sheets", () => {
  test("presents bottom-anchored over the frame and dismisses cleanly", async ({ page }) => {
    await page.goto("/#/components/sheets");
    const frame = page.locator(".stage-frame");

    await frame.getByRole("button", { name: "How did you sleep?" }).click();
    const sheet = page.getByRole("dialog");
    await expect(sheet).toBeVisible();
    // Exact text: role-name matching is case-insensitive, so it would miss a
    // stray text-transform leaking in from the gallery's own styles.
    await expect(sheet.locator("h2")).toHaveText("How did you sleep?");

    // Bottom-anchored once the slide-up settles: the sheet's base sits on the
    // frame's base. Polled, since measuring mid-transition reads the transform.
    await expect
      .poll(async () => {
        const sheetBox = (await sheet.boundingBox())!;
        const frameBox = (await frame.boundingBox())!;
        return Math.round(sheetBox.y + sheetBox.height - (frameBox.y + frameBox.height));
      })
      .toBe(0);

    // Escape, backdrop and close button each dismiss; the dialog unmounts.
    await page.keyboard.press("Escape");
    await expect(page.getByRole("dialog")).toHaveCount(0);
  });

  test("never overshoots the top of its frame while entering", async ({ page }) => {
    await page.goto("/#/components/sheets");
    await page.locator(".stage-frame button").first().waitFor();

    // Sampled every frame: a shown non-modal <dialog> used to be mispositioned
    // mid-transition in WebKit, swooping above the frame before snapping back.
    const offsets = await page.evaluate(async () => {
      const button = [...document.querySelectorAll(".stage-frame button")].find((el) =>
        el.textContent?.trim().toLowerCase().startsWith("delete recording"),
      ) as HTMLButtonElement;
      const seen: number[] = [];
      const start = performance.now();
      button.click();
      return await new Promise<number[]>((resolve) => {
        const tick = () => {
          const sheet = document.querySelector(".sheet");
          const stage = document.querySelector(".stage-frame");
          if (sheet && stage) {
            seen.push(sheet.getBoundingClientRect().top - stage.getBoundingClientRect().top);
          }
          if (performance.now() - start < 450) requestAnimationFrame(tick);
          else resolve(seen);
        };
        requestAnimationFrame(tick);
      });
    });

    // Guard the guard: an empty sample would make the assertion vacuous.
    expect(offsets.length).toBeGreaterThan(10);
    expect(Math.min(...offsets)).toBeGreaterThanOrEqual(0);
  });

  test("animates away on dismiss instead of snapping", async ({ page }) => {
    await page.goto("/#/components/sheets");
    await page.locator(".stage-frame").getByRole("button", { name: "Delete recording" }).click();
    await expect(page.getByRole("dialog")).toBeVisible();
    await page.waitForTimeout(400);

    const exit = await page.evaluate(async () => {
      const travel: number[] = [];
      const start = performance.now();
      (document.querySelector(".backdrop") as HTMLElement).click();
      return await new Promise<{ travel: number[]; unmounted: number | null }>((resolve) => {
        let unmounted: number | null = null;
        const tick = () => {
          const sheet = document.querySelector(".sheet");
          const now = performance.now() - start;
          if (sheet) travel.push(new DOMMatrix(getComputedStyle(sheet).transform).m42);
          else if (unmounted === null) unmounted = now;
          if (now < 500) requestAnimationFrame(tick);
          else resolve({ travel, unmounted });
        };
        requestAnimationFrame(tick);
      });
    });

    // It slides down over several frames, rather than vanishing on the spot.
    expect(exit.travel.length).toBeGreaterThan(5);
    expect(Math.max(...exit.travel)).toBeGreaterThan(100);
    expect(exit.unmounted).toBeGreaterThan(150);
    await expect(page.getByRole("dialog")).toHaveCount(0);
  });

  test("confirmation sheet without a dismiss button closes from its actions", async ({ page }) => {
    await page.goto("/#/components/sheets");
    const frame = page.locator(".stage-frame");
    await frame.getByRole("button", { name: "Delete recording" }).click();
    const sheet = page.getByRole("dialog");
    await expect(sheet).toBeVisible();
    await expect(sheet.getByRole("button", { name: "Dismiss" })).toHaveCount(0);

    await sheet.getByRole("button", { name: "Cancel" }).click();
    await expect(page.getByRole("dialog")).toHaveCount(0);
  });
});

test.describe("rows and content groups", () => {
  test("only rows that do something are buttons", async ({ page }) => {
    await page.goto("/#/components/rows");
    const groups = page.locator(".eigin-rows");
    await expect(groups.first()).toBeVisible();

    // "Version" states a fact; the rest navigate.
    const about = groups.nth(3);
    const version = about.locator(".eigin-row", { hasText: "Version" });
    expect(await version.evaluate((el) => el.tagName)).toBe("DIV");
    expect(
      await about
        .locator(".eigin-row", { hasText: "Open source licences" })
        .evaluate((el) => el.tagName),
    ).toBe("BUTTON");
  });

  test("hairlines divide rows without touching the card edge", async ({ page }) => {
    await page.goto("/#/components/rows");
    const rows = page.locator(".eigin-rows").nth(1).locator(".eigin-row");
    await expect(rows).toHaveCount(3);

    const dividers = await rows.evaluateAll((elements) =>
      elements.map((el) => {
        const before = getComputedStyle(el, "::before");
        return { drawn: before.backgroundColor !== "rgba(0, 0, 0, 0)", left: before.left };
      }),
    );

    // The first row opens the card, so the rule belongs to the boundary below it.
    expect(dividers.map((d) => d.drawn)).toEqual([false, true, true]);
    expect(dividers[1].left).toBe("24px");
  });
});

test.describe("images", () => {
  test("every shape keeps the same height, and only the width moves", async ({ page }) => {
    await page.goto("/#/components/images");
    // landscape, panorama, square, portrait, in that order.
    const cards = page.locator(".canvas >> nth=1").locator(".plate");
    await expect(cards).toHaveCount(4);

    // Layout size, not the painted box: the card scales as it grows in, and it
    // is the room it takes that must not vary.
    const measure = () =>
      cards.evaluateAll((elements) =>
        elements.map((el) => ({
          width: (el as HTMLElement).offsetWidth,
          height: (el as HTMLElement).offsetHeight,
        })),
      );

    // Each card starts square and settles into its own shape, so poll until the
    // shapes have arrived — the height is the part that must never vary.
    await expect
      .poll(async () => {
        const boxes = await measure();
        return {
          heights: new Set(boxes.map((box) => box.height)).size,
          tallestIsNarrowest: boxes[3].width < boxes[0].width,
        };
      })
      .toEqual({ heights: 1, tallestIsNarrowest: true });
  });

  test("a broken image keeps its place rather than leaving a hole", async ({ page }) => {
    await page.goto("/#/components/images");
    const card = page.locator(".canvas").first().locator(".plate");
    const height = (locator: typeof card) =>
      locator.evaluate((el) => (el as HTMLElement).offsetHeight);
    const loaded = await height(card);

    await page.getByRole("radio", { name: "broken", exact: true }).click();
    await expect(card.getByText("This image didn't load")).toBeVisible();
    expect(await height(card)).toBe(loaded);
  });

  test("the placeholder is square, and the entrance never plays twice", async ({ page }) => {
    await page.goto("/#/components/images");
    const card = page.locator(".canvas").first().locator(".plate");
    await page.getByRole("radio", { name: "loading", exact: true }).click();

    // The width eases back to the placeholder shape, so settle before measuring.
    await expect
      .poll(async () =>
        card.evaluate((el) => ({
          width: (el as HTMLElement).offsetWidth,
          height: (el as HTMLElement).offsetHeight,
        })),
      )
      .toEqual({ width: 182, height: 182 });

    // Switching state is a crossfade in place: the card is the same element,
    // and the entrance it already played stays played.
    await page.getByRole("radio", { name: "broken", exact: true }).click();
    await expect(card.getByText("This image didn't load")).toBeVisible();
    await expect
      .poll(async () =>
        page
          .locator(".canvas")
          .first()
          .locator(".image-card")
          .evaluate((el) => el.getAnimations().map((animation) => animation.playState)),
      )
      .toEqual(["finished"]);
  });

  test("a linked image asks before it leaves, an unlinked one opens", async ({ page }) => {
    await page.goto("/#/components/images");

    await page.getByRole("button", { name: "Open full screen" }).click();
    const viewer = page.getByRole("dialog", { name: /valley/ });
    await expect(viewer).toBeVisible();
    await page.keyboard.press("Escape");
    await expect(viewer).toBeHidden();

    await page.getByRole("button", { name: "Follow a linked image" }).click();
    const warning = page.getByRole("dialog");
    await expect(warning).toContainText("en.wikipedia.org");
    await expect(warning.getByRole("button", { name: "Open link" })).toBeVisible();
  });
});
