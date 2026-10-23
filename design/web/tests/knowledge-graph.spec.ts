import { expect, test } from "@playwright/test";

async function openGraph(page: import("@playwright/test").Page) {
  await page.goto("/#/screens/knowledge");
  await expect(
    page.getByRole("button", { name: "View details for You", exact: true }),
  ).toBeEnabled();
}

test("arrival starts with loading and resolves to the user with six neighbors", async ({
  page,
}) => {
  await page.goto("/#/screens/knowledge");
  await expect(page.getByRole("heading", { name: "Loading graph" })).toBeVisible();
  await expect(page.locator(".graph-node.focused")).toHaveAccessibleName("View details for You");
  await expect(page.locator(".graph-node:not(.focused)")).toHaveCount(6);
  await expect(page.locator(".pagination")).toContainText("1–6 of 10 connections");
});

test("pagination keeps the center fixed and returning home resets the page", async ({ page }) => {
  await openGraph(page);
  const center = page.locator(".graph-node.focused");
  const position = () =>
    center.evaluate((el) => {
      const rect = el.getBoundingClientRect();
      const canvas = el.closest(".graph-canvas")!.getBoundingClientRect();
      return { x: rect.x - canvas.x, y: rect.y - canvas.y };
    });
  const before = await position();
  await page.getByRole("button", { name: "Next relationships", exact: true }).click();
  await expect(page.locator(".pagination")).toContainText("7–10 of 10 connections");
  expect(await position()).toEqual(before);
  await page.getByRole("button", { name: "Explore Books", exact: true }).click();
  await expect(center).toHaveAccessibleName("View details for Books");
  await expect(page.locator(".graph-node:not(.focused)")).toHaveCount(1);
  await page.getByRole("button", { name: "Back to you", exact: true }).click();
  await expect(page.locator(".pagination")).toContainText("1–6 of 10 connections");
});

test("selecting a neighbor recenters it and center details match the entity", async ({ page }) => {
  await openGraph(page);
  await page.getByRole("button", { name: "Explore Summer trip", exact: true }).click();
  await expect(page.locator(".graph-node.focused")).toHaveAccessibleName(
    "View details for Summer trip",
  );
  await page.getByRole("button", { name: "View details for Summer trip", exact: true }).click();
  await expect(page.getByRole("dialog")).toContainText("Summer trip");
  await expect(page.getByRole("dialog")).not.toContainText("Relates to");
  await page.getByRole("dialog").getByRole("button", { name: "Oslo", exact: true }).click();
  await expect(page.locator(".graph-node.focused")).toHaveAccessibleName("View details for Oslo");
});

test("all nodes fit and remain separate in small portrait and landscape frames", async ({
  page,
}) => {
  await openGraph(page);
  await page.getByRole("radio", { name: "iPhone SE", exact: true }).click();
  for (const orientation of ["Portrait", "Landscape"]) {
    await page.getByRole("radio", { name: orientation, exact: true }).click();
    await expect(page.locator(".graph-node:not(.focused)")).toHaveCount(
      orientation === "Portrait" ? 6 : 4,
    );
    // Measure after the staggered arrival and layout phases settle.
    await expect(page.locator(".graph-node.focused")).toBeEnabled();
    await page.waitForTimeout(300);
    const layout = await page.locator(".graph-canvas").evaluate((canvas) => {
      const area = canvas.getBoundingClientRect();
      const nodes = [...canvas.querySelectorAll(".graph-node")].map((node) =>
        node.getBoundingClientRect(),
      );
      const inside = nodes.every(
        (node) =>
          node.left >= area.left - 1 &&
          node.right <= area.right + 1 &&
          node.top >= area.top - 1 &&
          node.bottom <= area.bottom + 1,
      );
      const overlaps = nodes.some((a, i) =>
        nodes
          .slice(i + 1)
          .some(
            (b) => a.left < b.right && a.right > b.left && a.top < b.bottom && a.bottom > b.top,
          ),
      );
      return { inside, overlaps };
    });
    expect(layout).toEqual({ inside: true, overlaps: false });
  }
});

test("isolated nodes still have details and a way home with reduced motion", async ({ page }) => {
  await page.emulateMedia({ reducedMotion: "reduce" });
  await openGraph(page);
  await page
    .locator(".device-picker")
    .getByRole("radio", { name: "isolated", exact: true })
    .click();
  await expect(page.locator(".pagination")).toContainText("No connections yet");
  await expect(page.locator(".graph-node")).toHaveCount(1);
  await page.getByRole("button", { name: "Back to you", exact: true }).click();
  await expect(page.locator(".graph-node.focused")).toHaveAccessibleName("View details for You");
});

test("three neighbors form an evenly spaced triangle around the focus", async ({ page }) => {
  await page.emulateMedia({ reducedMotion: "reduce" });
  await openGraph(page);
  await page.getByRole("button", { name: "Explore Cooking", exact: true }).click();
  await expect(page.locator(".graph-node:not(.focused)")).toHaveCount(3);
  const positions = await page.locator(".graph-canvas").evaluate((el) => {
    const nodes = [...el.querySelectorAll<HTMLElement>(".graph-node:not(.focused)")];
    return nodes.map((node) => ({
      x: node.offsetLeft / el.clientWidth,
      y: node.offsetTop / el.clientHeight,
    }));
  });
  expect(positions[0].x).toBeCloseTo(0.5, 2);
  expect(positions[0].y).toBeLessThan(0.2);
  expect(positions[1].x + positions[2].x).toBeCloseTo(1, 2);
  expect(positions[1].y).toBeCloseTo(positions[2].y, 2);
});

test("six neighbors form a rounded ring and four use the corners", async ({ page }) => {
  await page.emulateMedia({ reducedMotion: "reduce" });
  await openGraph(page);
  const positions = () =>
    page.locator(".graph-node:not(.focused)").evaluateAll((nodes) =>
      nodes.map((node) => ({
        x: (node as HTMLElement).offsetLeft,
        y: (node as HTMLElement).offsetTop,
      })),
    );
  const six = await positions();
  expect(six[0].y).toBe(six[2].y);
  expect(six[0].y).toBeGreaterThan(six[1].y);
  expect(six[3].y).toBe(six[5].y);
  expect(six[3].y).toBeLessThan(six[4].y);
  expect(six.slice(0, 3).map((node) => node.x)).toEqual(six.slice(3).map((node) => node.x));
  await page.getByRole("button", { name: "Explore Sofie", exact: true }).click();
  await expect(page.locator(".graph-node:not(.focused)")).toHaveCount(4);
  const four = await positions();
  expect(four[0].y).toBe(four[1].y);
  expect(four[2].y).toBe(four[3].y);
  expect(four[0].x).toBe(four[2].x);
  expect(four[1].x).toBe(four[3].x);
});

test("connections appear after node arrival and stay complete after navigation", async ({
  page,
}) => {
  await page.goto("/#/screens/knowledge");
  await expect(page.getByRole("heading", { name: "Loading graph" })).toBeVisible();
  await expect(page.locator(".edges line")).toHaveCount(0);
  await expect(page.locator(".graph-node.focused")).toBeEnabled();
  await expect(page.locator(".edges line")).toHaveCount(6);
  await page.getByRole("button", { name: "Explore Sofie", exact: true }).click();
  await expect(page.locator(".graph-node.focused")).toHaveAccessibleName("View details for Sofie");
  await expect(page.locator(".graph-node.focused")).toBeEnabled();
  await expect(page.locator(".edges line")).toHaveCount(4);
});

test("recovery actions stay together below the graph and pagination only appears when needed", async ({
  page,
}) => {
  await page.emulateMedia({ reducedMotion: "reduce" });
  await openGraph(page);
  const controls = page.locator(".graph-controls");
  await expect(controls.getByRole("button", { name: "Back", exact: true })).toHaveCount(0);
  await expect(controls.getByRole("button", { name: "Back to you", exact: true })).toHaveCount(0);
  await page.getByRole("button", { name: "Explore Sofie", exact: true }).click();
  await expect(controls).toContainText("4 connections");
  await expect(
    controls.getByRole("button", { name: "Next relationships", exact: true }),
  ).toHaveCount(0);
  await expect(
    controls.getByRole("button", { name: "Previous relationships", exact: true }),
  ).toHaveCount(0);
  await expect(controls.getByRole("button", { name: "Back to you", exact: true })).toBeVisible();
  const graph = await page.locator(".graph-canvas").boundingBox();
  const bar = await controls.boundingBox();
  expect(bar!.y).toBeGreaterThanOrEqual(graph!.y + graph!.height - 1);
  await controls.getByRole("button", { name: "Back to you", exact: true }).click();
  await expect(controls).toContainText("1–6 of 10 connections");
  await expect(controls.getByRole("button", { name: "Back", exact: true })).toHaveCount(0);
});

test("graph bounds stay fixed as pagination and recovery buttons appear or disappear", async ({
  page,
}) => {
  await page.emulateMedia({ reducedMotion: "reduce" });
  await openGraph(page);
  await page.getByRole("radio", { name: "iPhone SE", exact: true }).click();
  for (const orientation of ["Portrait", "Landscape"]) {
    await page.getByRole("radio", { name: orientation, exact: true }).click();
    const canvas = page.locator(".graph-canvas");
    const measure = () =>
      canvas.evaluate((el) => {
        const rect = el.getBoundingClientRect();
        const screen = el.closest(".graph-screen")!.getBoundingClientRect();
        return {
          x: rect.x - screen.x,
          y: rect.y - screen.y,
          width: rect.width,
          height: rect.height,
        };
      });
    const bounds = await measure();
    await page.getByRole("button", { name: "Explore Sofie", exact: true }).click();
    await expect(page.locator(".pagination")).toHaveText("4 connections");
    expect(await measure()).toEqual(bounds);
    await page.getByRole("button", { name: "Back to you", exact: true }).click();
    await expect(page.locator(".graph-node.focused")).toHaveAccessibleName("View details for You");
    expect(await measure()).toEqual(bounds);
  }
});

test("the arrival connection stays on the first page without losing or duplicating connections", async ({
  page,
}) => {
  await page.emulateMedia({ reducedMotion: "reduce" });
  await openGraph(page);
  await page.getByRole("button", { name: "Next relationships", exact: true }).click();
  await page.getByRole("button", { name: "Explore Books", exact: true }).click();
  await page.getByRole("button", { name: "Explore You", exact: true }).click();
  await expect(page.locator(".pagination")).toContainText("1–6 of 10 connections");
  await expect(page.getByRole("button", { name: "Explore Books", exact: true })).toBeVisible();
  const names = () =>
    page
      .locator(".graph-node:not(.focused)")
      .evaluateAll((nodes) => nodes.map((node) => node.getAttribute("aria-label")));
  const firstPage = await names();
  await page.getByRole("button", { name: "Next relationships", exact: true }).click();
  const secondPage = await names();
  expect(firstPage.length + secondPage.length).toBe(10);
  expect(new Set([...firstPage, ...secondPage]).size).toBe(10);
  await page.getByRole("button", { name: "Back to you", exact: true }).click();
  await expect(page.getByRole("button", { name: "Explore Sofie", exact: true })).toBeVisible();
  await expect(page.getByRole("button", { name: "Explore Books", exact: true })).toHaveCount(0);
});

test("wide canvases rotate small neighborhoods sideways without overlapping the center", async ({
  page,
}) => {
  await page.emulateMedia({ reducedMotion: "reduce" });
  await openGraph(page);
  await page.getByRole("radio", { name: "iPhone SE", exact: true }).click();
  await page.getByRole("radio", { name: "Landscape", exact: true }).click();
  for (const name of ["Books", "Learning Norwegian", "Cooking", "Sofie"]) {
    const neighbor = page.getByRole("button", { name: `Explore ${name}`, exact: true });
    while (!(await neighbor.count())) {
      await page.getByRole("button", { name: "Next relationships", exact: true }).click();
    }
    await neighbor.click();
    await expect(page.locator(".graph-node.focused")).toHaveAccessibleName(
      `View details for ${name}`,
    );
    const layout = await page.locator(".graph-canvas").evaluate((canvas) => {
      const area = canvas.getBoundingClientRect();
      const nodes = [...canvas.querySelectorAll<HTMLElement>(".graph-node")];
      const rects = nodes.map((node) => node.getBoundingClientRect());
      const first = nodes.find((node) => !node.classList.contains("focused"))!;
      return {
        wide: area.width > area.height,
        firstOnLeft: first.offsetLeft < area.width / 2,
        inside: rects.every(
          (rect) =>
            rect.left >= area.left - 1 &&
            rect.right <= area.right + 1 &&
            rect.top >= area.top - 1 &&
            rect.bottom <= area.bottom + 1,
        ),
        overlaps: rects.some((a, i) =>
          rects
            .slice(i + 1)
            .some(
              (b) => a.left < b.right && a.right > b.left && a.top < b.bottom && a.bottom > b.top,
            ),
        ),
      };
    });
    expect(layout).toEqual({ wide: true, firstOnLeft: true, inside: true, overlaps: false });
    await page.getByRole("button", { name: "Back to you", exact: true }).click();
  }
});

test("connection endpoints meet circle centers in portrait and landscape", async ({ page }) => {
  await page.emulateMedia({ reducedMotion: "reduce" });
  await openGraph(page);
  await page.getByRole("radio", { name: "iPhone SE", exact: true }).click();
  for (const orientation of ["Portrait", "Landscape"]) {
    await page.getByRole("radio", { name: orientation, exact: true }).click();
    await expect(page.locator(".edges line")).toHaveCount(orientation === "Portrait" ? 6 : 4);
    const error = await page.locator(".graph-canvas").evaluate((canvas) => {
      const svg = canvas.querySelector("svg.edges")!.getBoundingClientRect();
      const center = canvas.querySelector(".focused .circle")!.getBoundingClientRect();
      const circles = [...canvas.querySelectorAll(".graph-node:not(.focused) .circle")].map((el) =>
        el.getBoundingClientRect(),
      );
      const lines = [...canvas.querySelectorAll<SVGLineElement>(".edges line")];
      return Math.max(
        ...lines.flatMap((line, index) => {
          const target = circles[index];
          return [
            Math.abs(svg.x + line.x1.baseVal.value - (center.x + center.width / 2)),
            Math.abs(svg.y + line.y1.baseVal.value - (center.y + center.height / 2)),
            Math.abs(svg.x + line.x2.baseVal.value - (target.x + target.width / 2)),
            Math.abs(svg.y + line.y2.baseVal.value - (target.y + target.height / 2)),
          ];
        }),
      );
    });
    expect(error).toBeLessThan(1);
  }
});

test("full details show the selected entity and back preserves graph focus and pagination", async ({
  page,
}) => {
  await page.emulateMedia({ reducedMotion: "reduce" });
  await openGraph(page);
  await page.getByRole("button", { name: "Next relationships", exact: true }).click();
  await page.getByRole("button", { name: "View details for You", exact: true }).click();
  await page
    .getByRole("dialog")
    .getByRole("button", { name: "View full details", exact: true })
    .click();
  const detail = page.locator(".secondary-screen");
  await expect(detail).toContainText("Actor");
  await expect(detail).toContainText("ID");
  await expect(detail).toContainText("Relates to");
  await expect(detail).toContainText("Relationships");
  await detail.getByRole("button", { name: "Back", exact: true }).click();
  await expect(page.locator(".pagination")).toContainText("7–10 of 10 connections");
  await page.getByRole("button", { name: "Explore Books", exact: true }).click();
  await page.getByRole("button", { name: "View details for Books", exact: true }).click();
  await page
    .getByRole("dialog")
    .getByRole("button", { name: "View full details", exact: true })
    .click();
  await expect(detail).toContainText("Books");
  await expect(detail).toContainText("Thing");
  await detail.getByRole("button", { name: "Back", exact: true }).click();
  await expect(page.locator(".graph-node.focused")).toHaveAccessibleName("View details for Books");
  await expect(page.locator(".pagination")).toHaveText("1 connection");
});

test("graph summary uses a bounded sheet description without a type label", async ({ page }) => {
  await page.emulateMedia({ reducedMotion: "reduce" });
  await openGraph(page);
  await page.getByRole("radio", { name: "isolated", exact: true }).click();
  await page.locator(".graph-node.focused").click();
  const dialog = page.getByRole("dialog");
  await expect(dialog.locator(".header .description")).toContainText("A saved thought");
  await expect(dialog.locator(".t-miniLabel")).not.toContainText("Note");
  await expect(
    dialog.getByRole("button", { name: "View full details", exact: true }),
  ).toBeVisible();
  await expect(dialog).toContainText("Connections");
  await expect(dialog.locator(".content-preview")).toHaveCount(0);
});

test("knowledge list limits output previews to two lines without trimming full details", async ({
  page,
}) => {
  await page.goto("/#/screens/knowledge-list");
  const output = page.getByRole("button", { name: /^Oslo weekend itinerary/ });
  const preview = output.locator(".description");
  await expect(preview).toBeVisible();
  const metrics = await preview.evaluate((element) => ({
    visible: element.clientHeight,
    full: element.scrollHeight,
    lineHeight: parseFloat(getComputedStyle(element).lineHeight),
  }));
  expect(metrics.visible).toBeLessThanOrEqual(Math.ceil(metrics.lineHeight * 2));
  expect(metrics.full).toBeGreaterThan(metrics.visible);
  await output.click();
  await expect(page.locator(".secondary-screen")).toContainText("bring a light waterproof jacket");
});

test("graph labels fade away during movement and return once nodes settle", async ({ page }) => {
  await openGraph(page);
  await page.getByRole("button", { name: "Explore Summer trip", exact: true }).click();
  await expect(page.locator(".node-label.label-hidden").first()).toBeVisible();
  await expect(page.locator(".graph-node.focused")).toHaveAccessibleName(
    "View details for Summer trip",
  );
  await expect(page.locator(".node-label.label-hidden")).toHaveCount(0);
  const groupsGap = async () =>
    page
      .getByRole("dialog")
      .locator(".detail-content")
      .evaluate((element) => parseFloat(getComputedStyle(element).rowGap));
  await page.getByRole("button", { name: "View details for Summer trip", exact: true }).click();
  expect(await groupsGap()).toBe(40);
});

test("pagination preserves the stationary center label", async ({ page }) => {
  await openGraph(page);
  await page.getByRole("button", { name: "Next relationships", exact: true }).click();
  await expect(page.locator(".node-label.label-hidden").first()).toBeVisible();
  const center = page.locator(".graph-node.focused .node-label");
  await expect(center).toHaveText("You");
  await expect(center).not.toHaveClass(/label-hidden/);
  await expect(page.locator(".node-label.label-hidden")).toHaveCount(0);
  await expect(center).not.toHaveClass(/label-hidden/);
});

test("a 150px landscape canvas keeps all five node targets separate", async ({ page }) => {
  await openGraph(page);
  await page.getByRole("radio", { name: "iPhone SE", exact: true }).click();
  await page.getByRole("radio", { name: "Landscape", exact: true }).click();
  await page.addStyleTag({
    content: ".graph-canvas { flex: none !important; height: 150px !important; }",
  });
  await expect(page.locator(".graph-node:not(.focused)")).toHaveCount(4);
  await expect(page.locator(".graph-node.focused")).toBeEnabled();
  const layout = await page.locator(".graph-canvas").evaluate((canvas) => {
    const area = canvas.getBoundingClientRect();
    const nodes = [...canvas.querySelectorAll(".graph-node")].map((node) =>
      node.getBoundingClientRect(),
    );
    return {
      inside: nodes.every(
        (node) =>
          node.left >= area.left - 1 &&
          node.right <= area.right + 1 &&
          node.top >= area.top - 1 &&
          node.bottom <= area.bottom + 1,
      ),
      overlaps: nodes.some((a, i) =>
        nodes
          .slice(i + 1)
          .some(
            (b) => a.left < b.right && b.left < a.right && a.top < b.bottom && b.top < a.bottom,
          ),
      ),
    };
  });
  expect(layout.inside).toBe(true);
  expect(layout.overlaps).toBe(false);
});
