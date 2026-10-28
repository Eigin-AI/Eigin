import { expect, test } from "@playwright/test";

test("team knowledge passes through shared context to another agent before the next exchange", async ({
  page,
}) => {
  await page.emulateMedia({ reducedMotion: "no-preference" });
  await page.goto("/en/");
  const diagram = page.locator(".team-diagram");
  await diagram.scrollIntoViewIfNeeded();
  await expect(diagram).toHaveAttribute("data-active", "true");
  const pulses = await diagram.evaluate(async (element) => {
    const pulses: { agent: number; path: string | null; length: string | null }[] = [];
    let previous = -1;
    const deadline = performance.now() + 7000;
    while (performance.now() < deadline && pulses.length < 4) {
      const paths = Array.from(element.querySelectorAll(".flow"));
      const current = paths.findIndex((path) => path.getAttribute("opacity") === "1");
      if (current >= 0 && current !== previous) {
        pulses.push({
          agent: current,
          path: paths[current].getAttribute("d"),
          length: paths[current].getAttribute("stroke-dasharray")?.split(" ")[0] ?? null,
        });
      }
      previous = current;
      await new Promise((resolve) => setTimeout(resolve, 25));
    }
    return pulses;
  });
  expect(pulses.map((pulse) => pulse.agent)).toEqual([0, 4, 4, 2]);
  expect(pulses[1].path).not.toBe(pulses[2].path);
  expect(new Set(pulses.map((pulse) => pulse.length)).size).toBe(1);

  await page.getByRole("button", { name: "Pause diagram", exact: true }).click();
  await expect(diagram).toHaveAttribute("data-active", "false");
  await expect(diagram.locator(".flow[opacity='1']")).toHaveCount(0);
  await page.waitForTimeout(500);
  const blobs = diagram.locator(".morph-blob path");
  const paused = await blobs.evaluateAll((elements) =>
    elements.map((element) => element.getAttribute("d")),
  );
  await page.waitForTimeout(300);
  expect(
    await blobs.evaluateAll((elements) => elements.map((element) => element.getAttribute("d"))),
  ).toEqual(paused);
});

test("team knowledge stays readable without motion", async ({ page }) => {
  await page.emulateMedia({ reducedMotion: "reduce" });
  await page.goto("/da/");
  const diagram = page.locator(".team-diagram");
  await diagram.scrollIntoViewIfNeeded();
  await expect(diagram.getByRole("img")).toHaveAccessibleName(
    "Fem individuelle agenter bidrager til og bruger teamets fælles viden.",
  );
  await expect(diagram).toContainText("Fælles");
  await expect(diagram.locator(".flow[opacity='1']")).toHaveCount(0);
  await expect(diagram.getByRole("button")).toHaveCount(0);
});
