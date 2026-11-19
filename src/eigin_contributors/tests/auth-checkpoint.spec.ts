import { testDatabaseUrl } from "./database.ts";
import { test, expect } from "@playwright/test";

test("public shell retains navigation and does not offer simulated submissions", async ({
  page,
}) => {
  await page.goto("/");
  await expect(
    page.getByRole("link", { name: "Sign in", exact: true }),
  ).toHaveAttribute("href", "/auth/gitlab?returnTo=%2F");
  await expect(
    page.getByRole("heading", { name: "Open calls", exact: true }),
  ).toBeVisible();
  const card = page
    .locator("#open-calls .call-card")
    .filter({ has: page.getByRole("link", { name: "Open fixture call" }) });
  await expect(
    card.getByRole("link", { name: "Read the call", exact: true }),
  ).toBeVisible();
  await expect(page.getByText("Simulate closed deadline")).toHaveCount(0);
  const copy = card.locator(".call-copy");
  const description = await copy.locator(".t-standfirst").boundingBox();
  const action = await copy
    .getByRole("link", { name: "Read the call" })
    .boundingBox();
  expect(action!.y).toBeGreaterThan(description!.y + description!.height);
  if (page.viewportSize()!.width > 760) {
    const tag = await copy.locator(".call-tags").boundingBox();
    const funding = await card.locator(":scope > .surface").boundingBox();
    expect(Math.abs(tag!.y - funding!.y)).toBeLessThan(2);
  }
  expect(
    await page.evaluate(
      () => document.documentElement.scrollWidth <= innerWidth,
    ),
  ).toBe(true);
});

test("private workflows and fictional calls cannot be read or posted to", async ({
  request,
}) => {
  for (const path of [
    "/review",
    "/review/fixture",
    "/calls/local-memory/specs/review-queue",
  ]) {
    const response = await request.get(path);
    expect(response.status()).toBe(404);
    expect(response.headers()["cache-control"]).toBe("no-store");
  }
  expect(
    (
      await request.post("/calls/tool-safety/submission", {
        multipart: { file: "private text" },
        headers: { Origin: "http://localhost:5276" },
      })
    ).status(),
  ).toBe(401);
});

test("OAuth start redirects to fixed GitLab with browser-bound cookie and PKCE", async ({
  request,
}) => {
  const response = await request.get(
    "/auth/gitlab?returnTo=https://evil.example",
    { maxRedirects: 0 },
  );
  expect(response.status()).toBe(303);
  const location = new URL(response.headers().location);
  expect(location.origin).toBe("https://code.eigin.ai");
  expect(location.searchParams.get("scope")).toBe("read_user");
  expect(location.searchParams.get("code_challenge_method")).toBe("S256");
  expect(location.searchParams.get("redirect_uri")).toBe(
    "http://localhost:5276/auth/callback",
  );
  expect(response.headers()["set-cookie"]).toContain("HttpOnly");
  expect(response.headers()["set-cookie"]).toContain("SameSite=Lax");
  expect(response.headers()["cache-control"]).toBe("no-store");
});

test("invalid callback and cross-origin logout fail without a session", async ({
  request,
}) => {
  const callback = await request.get(
    "/auth/callback?state=forged&code=forged",
    { maxRedirects: 0 },
  );
  expect(callback.status()).toBe(303);
  expect(callback.headers().location).toBe("/auth/problem");
  expect(callback.headers()["cache-control"]).toBe("no-store");
  expect((await request.get("/auth/logout")).status()).toBe(405);
  expect(
    (
      await request.post("/auth/logout", {
        headers: { Origin: "https://evil.example" },
      })
    ).status(),
  ).toBe(403);
});

test("guides retain the left-aligned shared shell", async ({ page }) => {
  for (const slug of ["process", "spec", "participation-terms"]) {
    await page.goto(`/guides/${slug}`);
    const left = await page
      .locator(".site-header .site-brand")
      .evaluate((el) => el.getBoundingClientRect().left);
    const title = await page
      .locator("main h1")
      .evaluate((el) => el.getBoundingClientRect().left);
    expect(Math.abs(title - left)).toBeLessThan(2);
    await expect(
      page
        .locator(".site-footer")
        .getByRole("link", { name: "Trust", exact: true }),
    ).toHaveAttribute("href", "https://www.eigin.ai/en/trust/");
  }
});

test("signed-in account has spacing, a shared logout button, and access to the call", async ({
  page,
  context,
}) => {
  const { Auth } = await import("../src/lib/server/auth.ts");
  const { createPool } = await import("../src/lib/server/database.ts");
  const pool = createPool(testDatabaseUrl());
  const id = 8000000000000000 + Math.floor(Math.random() * 1000000000);
  const fakeGitLab: typeof fetch = async (url) =>
    Response.json(
      String(url).endsWith("/oauth/token")
        ? { access_token: "test-only" }
        : {
            id,
            username: "walkthrough-test",
            name: "Walkthrough Test",
            commit_email: "gitlab-author@example.org",
          },
    );
  const auth = new Auth(
    pool,
    { origin: "http://localhost:5276", clientId: "test", clientSecret: "test" },
    fakeGitLab,
  );
  let token: string | undefined;
  try {
    const attempt = await auth.begin();
    const login = await auth.complete(
      attempt.binding,
      new URL(attempt.url).searchParams.get("state"),
      "test-code",
    );
    token = login.token;
    await context.addCookies([
      {
        name: "contributors_session",
        value: token,
        url: "http://localhost:5276",
        httpOnly: true,
        sameSite: "Lax",
      },
    ]);
    await page.goto("/account");
    await expect(
      page.getByText("Walkthrough Test · @walkthrough-test"),
    ).toBeVisible();
    await expect(page.getByRole("button", { name: "Sign out" })).toHaveClass(
      /eigin-btn/,
    );
    const title = await page.locator("main h1").boundingBox();
    const identity = await page.locator("main .intro").boundingBox();
    expect(identity!.y - title!.y - title!.height).toBeGreaterThanOrEqual(16);
    await page.getByRole("link", { name: "Browse open calls" }).click();
    await expect(page).toHaveURL(/#open-calls$/);
    await page.goto("/calls/tool-safety");
    await expect(
      page.getByRole("heading", {
        name: "Local detection of malicious instructions",
        exact: true,
      }),
    ).toBeVisible();
    const sectionSize = await page
      .getByRole("heading", { name: "Constraints", level: 2 })
      .evaluate((el) => parseFloat(getComputedStyle(el).fontSize));
    const subsectionSize = await page
      .locator(".call-constraints summary")
      .filter({ hasText: "Local-first" })
      .evaluate((el) => parseFloat(getComputedStyle(el).fontSize));
    expect(subsectionSize).toBeLessThan(sectionSize);
    await expect(page.getByText("€500", { exact: true })).toBeVisible();
    await expect(page.getByText("€250", { exact: true })).toBeVisible();
    expect(
      await page.evaluate(
        () => document.documentElement.scrollWidth <= innerWidth,
      ),
    ).toBe(true);
    const funding = page.getByRole("complementary", { name: "Call funding" });
    if (page.viewportSize()!.width > 760) {
      await page.evaluate(() => window.scrollTo(0, 1000));
      const first = await funding.boundingBox();
      await page.evaluate(() => window.scrollBy(0, 300));
      const second = await funding.boundingBox();
      expect(Math.abs(second!.y - first!.y)).toBeLessThan(2);
      expect(second!.y).toBeGreaterThanOrEqual(100);
    } else {
      expect(
        await funding.evaluate((el) => getComputedStyle(el).position),
      ).toBe("static");
    }
    await page.getByRole("link", { name: "Submit your spec" }).click();
    await expect(
      page.getByLabel("Git author email", { exact: true }),
    ).toHaveValue("gitlab-author@example.org");
    const chooseFile = page.getByRole("button", {
      name: "Choose file",
      exact: true,
    });
    await expect(chooseFile).toHaveClass(/eigin-btn/);
    const chooserEvent = page.waitForEvent("filechooser");
    await chooseFile.click();
    const chooser = await chooserEvent;
    await chooser.setFiles({
      name: "spec.md",
      mimeType: "text/markdown",
      buffer: Buffer.from(
        "# My private spec\n\nAn approach.\n\n```rust\nlet safe = false;\n```",
      ),
    });
    const preview = page.getByRole("region", { name: "Markdown preview" });
    await expect(preview.locator("pre")).toBeVisible();
    for (const panel of [preview, preview.locator("pre")]) {
      expect(
        await panel.evaluate((el) =>
          parseFloat(getComputedStyle(el).borderTopLeftRadius),
        ),
      ).toBeGreaterThan(0);
    }
    await page.getByLabel("Contact email", { exact: true }).focus();
    await page
      .getByLabel("Contact email", { exact: true })
      .fill("contact@example.org");
    await page.getByLabel("Git author email", { exact: true }).focus();
    await page
      .getByLabel("Git author email", { exact: true })
      .fill("author@example.org");
    await expect(
      page.getByRole("complementary", { name: "Support Eigin" }),
    ).toHaveCount(0);
    await expect(page.getByRole("checkbox")).toHaveCount(2);
    for (const checkbox of await page.getByRole("checkbox").all())
      await checkbox.check();
    await expect(
      page.getByRole("link", { name: "participation terms", exact: true }),
    ).toHaveAttribute("href", "/guides/participation-terms");
    await page.getByRole("button", { name: "Submit", exact: true }).click();
    await expect(
      page.getByText("Submission received", { exact: true }),
    ).toBeVisible();
    await page.reload();
    await expect(
      page.getByText("Submission received", { exact: true }),
    ).toBeVisible();
    const support = page.getByRole("complementary", { name: "Support Eigin" });
    await expect(support).toContainText("Help others discover Eigin");
    for (const [name, href] of [
      ["Star on GitHub", "https://github.com/Eigin-AI/Eigin"],
      ["Star on GitLab", "https://code.eigin.ai/dev/eigin"],
    ]) {
      const link = support.getByRole("link", { name, exact: true });
      await expect(link).toHaveAttribute("href", href);
      await expect(link).toHaveAttribute("target", "_blank");
      await expect(link).toHaveAttribute("rel", "noopener");
    }
    const download = await page.request.get(
      "/calls/tool-safety/submission/download",
    );
    expect(await download.text()).toContain("My private spec");
    expect(download.headers()["cache-control"]).toBe("no-store");
    await expect(
      page
        .getByRole("status")
        .getByRole("link", { name: "Download your spec" }),
    ).toBeVisible();
    await expect(
      page.getByText("Local rehearsal ·", { exact: false }),
    ).toHaveCount(0);
    await page.getByRole("link", { name: "Back to the call" }).click();
    await expect(
      page.getByRole("link", { name: "Submit your spec", exact: true }),
    ).toHaveCount(0);
    await page.getByRole("link", { name: "Edit your spec" }).click();
    await expect(
      page.getByRole("complementary", { name: "Support Eigin" }),
    ).toHaveCount(0);
    const cancel = page.getByRole("link", { name: "Cancel", exact: true });
    await expect(cancel).toHaveClass(/eigin-btn/);
    const saveBox = await page
      .getByRole("button", { name: "Save changes" })
      .boundingBox();
    const cancelBox = await cancel.boundingBox();
    expect(Math.abs(saveBox!.width - cancelBox!.width)).toBeLessThan(2);
    expect(Math.abs(saveBox!.height - cancelBox!.height)).toBeLessThan(1);
    await page
      .getByLabel("Git author name", { exact: true })
      .fill("Unsaved author");
    await cancel.click();
    await expect(
      page.getByText("Unsaved author", { exact: false }),
    ).toHaveCount(0);
    await page.getByRole("link", { name: "Edit your spec" }).click();
    await page
      .getByLabel("Git author name", { exact: true })
      .fill("Updated Author");
    for (const checkbox of await page.getByRole("checkbox").all())
      await expect(checkbox).toBeChecked();
    await page.getByRole("button", { name: "Save changes" }).click();
    await expect(
      page.getByText("Submission received", { exact: true }),
    ).toBeVisible();
    await expect(
      page.getByText("Updated Author", { exact: false }),
    ).toBeVisible();
    await page.getByRole("button", { name: "Sign out" }).click();
    await expect(
      page.getByRole("link", { name: "Sign in", exact: true }),
    ).toBeVisible();
    expect(await auth.user(token)).toBe(null);
    expect((await page.request.get("/drafts/tool-safety")).status()).toBe(404);
  } finally {
    await auth.logout(token);
    const user = (
      await pool.query("SELECT id FROM users WHERE gitlab_user_id=$1", [id])
    ).rows[0];
    if (user) {
      await pool.query(
        "UPDATE submissions SET current_revision_id=NULL WHERE user_id=$1",
        [user.id],
      );
      await pool.query(
        "DELETE FROM submission_revisions WHERE submission_id IN (SELECT id FROM submissions WHERE user_id=$1)",
        [user.id],
      );
      await pool.query("DELETE FROM submissions WHERE user_id=$1", [user.id]);
      await pool.query("DELETE FROM users WHERE id=$1", [user.id]);
    }
    await pool.end();
  }
});

test("sign-in leaves the portal through a full document navigation", async ({
  page,
}) => {
  let documentRequest = false;
  await page.route("**/auth/gitlab?**", async (route) => {
    documentRequest = route.request().isNavigationRequest();
    await route.fulfill({
      contentType: "text/html",
      body: "<h1>OAuth navigation boundary</h1>",
    });
  });
  await page.goto("/");
  await page.getByRole("link", { name: "Sign in", exact: true }).click();
  await expect(
    page.getByRole("heading", { name: "OAuth navigation boundary" }),
  ).toBeVisible();
  expect(documentRequest).toBe(true);
});

test("signed-out submission entry preserves its destination when starting login", async ({
  request,
}) => {
  const response = await request.get("/calls/tool-safety/submission?edit=1", {
    maxRedirects: 0,
  });
  expect(response.status()).toBe(303);
  const location = new URL(
    response.headers().location,
    "http://localhost:5276",
  );
  expect(location.pathname).toBe("/auth/gitlab");
  expect(location.searchParams.get("returnTo")).toBe(
    "/calls/tool-safety/submission?edit=1",
  );
});

test("header sign-in preserves the current page and section", async ({
  page,
}) => {
  for (const path of [
    "/#open-calls",
    "/calls/tool-safety",
    "/guides/process",
  ]) {
    await page.goto(path);
    await expect(
      page.getByRole("link", { name: "Sign in", exact: true }),
    ).toHaveAttribute(
      "href",
      "/auth/gitlab?returnTo=" + encodeURIComponent(path),
    );
  }
});

test("spec guide links to a readable example and its original Markdown download", async ({
  page,
  request,
}) => {
  await page.goto("/guides/spec");
  await page.getByRole("link", { name: "Read an example spec" }).click();
  await expect(
    page.getByRole("heading", {
      name: "Schedule follow-ups from a conversation",
      level: 1,
    }),
  ).toBeVisible();
  await expect(
    page.getByRole("heading", {
      name: "Implementation",
      level: 2,
      exact: true,
    }),
  ).toBeVisible();
  await expect(
    page.getByRole("heading", { name: "Implementation steps", level: 2 }),
  ).toBeVisible();
  await expect(page.locator("pre").first()).toContainText(
    "FollowUpTool.execute(",
  );
  const codeStyle = await page
    .locator("pre")
    .first()
    .evaluate((el) => ({
      background: getComputedStyle(el).backgroundColor,
      radius: parseFloat(getComputedStyle(el).borderTopLeftRadius),
    }));
  const pageBackground = await page
    .locator(".contributor-page")
    .evaluate((el) => getComputedStyle(el).backgroundColor);
  expect(codeStyle.background).not.toBe(pageBackground);
  expect(codeStyle.radius).toBeGreaterThan(0);
  await expect(page.locator(".preview-scroll")).toHaveCount(0);
  const outcomes = page.locator(".task-marker");
  await expect(outcomes).toHaveCount(6);
  for (const checkbox of await outcomes.all()) {
    await expect(checkbox).toHaveAttribute("aria-disabled", "true");
    await expect(checkbox).toHaveAttribute("aria-checked", "false");
    await expect(checkbox.locator("button")).toBeDisabled();
    const alignment = await checkbox.evaluate((marker) => {
      const square = marker
        .querySelector(".indicator")!
        .getBoundingClientRect();
      const copy = document.getElementById(
        marker.getAttribute("aria-labelledby")!,
      )!.firstElementChild!;
      const lineCenter =
        copy.getBoundingClientRect().top +
        parseFloat(getComputedStyle(copy).lineHeight) / 2;
      return Math.abs(square.top + square.height / 2 - lineCenter);
    });
    expect(alignment).toBeLessThan(1);
  }
  const response = await request.get("/guides/example/download");
  expect(response.status()).toBe(200);
  expect(response.headers()["content-type"]).toContain("text/markdown");
  expect(response.headers()["content-disposition"]).toBe(
    'attachment; filename="schedule-follow-ups-from-a-conversation.md"',
  );
  const { readFile } = await import("node:fs/promises");
  expect(await response.text()).toBe(
    await readFile(
      new URL(
        "../content/examples/schedule-follow-ups-from-a-conversation.md",
        import.meta.url,
      ),
      "utf8",
    ),
  );
  expect(
    await page.evaluate(
      () => document.documentElement.scrollWidth <= innerWidth,
    ),
  ).toBe(true);
});

test("participation terms links share one page", async ({ page }) => {
  await page.goto("/guides/process");
  await page
    .locator("summary")
    .filter({ hasText: "3. We review and select" })
    .click();
  await page
    .locator("summary")
    .filter({ hasText: "5. Arrange payment" })
    .click();
  const termsLinks = page.getByRole("link", {
    name: "participation terms",
    exact: true,
  });
  for (const link of await termsLinks.all())
    await expect(link).toHaveAttribute("href", "/guides/participation-terms");
  await termsLinks.first().click();
  await expect(
    page.getByRole("heading", { name: "Participation terms", exact: true }),
  ).toBeVisible();
  await expect(
    page.getByText(
      "Draft for review. These terms are not open for acceptance.",
    ),
  ).toHaveCount(0);
  await expect(
    page.getByRole("heading", { name: "Local rehearsal terms" }),
  ).toHaveCount(0);
  await expect(page.locator("#participation-draft")).toContainText(
    "10 working days",
  );
  await expect(page.locator("#participation-draft")).toContainText(
    "withdraw before selection",
  );
  await expect(page.getByRole("checkbox")).toHaveCount(0);
  expect(
    await page.evaluate(
      () => document.documentElement.scrollWidth <= innerWidth,
    ),
  ).toBe(true);
  await page.goto("/guides/terms");
  await expect(page).toHaveURL(/\/guides\/participation-terms$/);
  expect((await page.request.get("/guides/rehearsal-terms")).status()).toBe(
    404,
  );
});

test("terms overview follows sections on desktop and mobile", async ({
  page,
}) => {
  await page.emulateMedia({ reducedMotion: "reduce" });
  await page.goto("/guides/participation-terms");
  await page.evaluate(() => document.fonts.ready.then(() => {}));
  if (page.viewportSize()!.width < 1024) {
    await page
      .getByText("On this page", { exact: true })
      .filter({ visible: true })
      .click();
  }
  const navigation = page.getByRole("navigation", { name: "On this page" });
  await expect(navigation.getByRole("link")).toHaveCount(6);
  await navigation
    .getByRole("link", { name: "4. Payment", exact: true })
    .click();
  await expect(page).toHaveURL(/#payment$/);
  await expect(
    navigation.getByRole("link", { name: "4. Payment", exact: true }),
  ).toHaveAttribute("aria-current", "location");
  const heading = await page.locator("#payment").boundingBox();
  expect(heading!.y).toBeGreaterThan(70);
  if (page.viewportSize()!.width >= 1024) {
    const sidebar = await navigation.boundingBox();
    expect(sidebar!.x + sidebar!.width).toBeLessThan(heading!.x);
  }
  expect(
    await page.evaluate(
      () => document.documentElement.scrollWidth <= innerWidth,
    ),
  ).toBe(true);
});

test("portal uses the current shared logo, favicons, and website footer destinations", async ({
  page,
}) => {
  const { readFile } = await import("node:fs/promises");
  await page.goto("/");
  const brand = page.locator(".site-header .site-brand");
  await expect(brand).toContainText("Eigin");
  await expect(
    page.getByText("For contributors", { exact: true }),
  ).toBeVisible();
  await expect(brand).toHaveAttribute("href", "/");
  const artwork = await readFile(
    new URL("../../../design/assets/icons/brand/avatar.svg", import.meta.url),
    "utf8",
  );
  for (const logo of await page.locator(".site-brand svg").all()) {
    await expect(logo).toHaveAttribute(
      "viewBox",
      artwork.match(/viewBox="([^"]+)"/)![1],
    );
    expect(
      await logo
        .locator("path")
        .evaluateAll((paths) => paths.map((path) => path.getAttribute("d"))),
    ).toEqual(
      [...artwork.matchAll(/<path[^>]+d="([^"]+)"/g)].map((match) => match[1]),
    );
  }
  for (const [selector, filename] of [
    ['link[rel="icon"][type="image/svg+xml"]', "favicon.svg"],
    ['link[rel="icon"][type="image/png"]', "favicon-32.png"],
    ['link[rel="apple-touch-icon"]', "apple-touch-icon.png"],
  ]) {
    const bytes = await page.evaluate(async (selector) => {
      const link = document.querySelector<HTMLLinkElement>(selector)!;
      const response = await fetch(link.href);
      if (!response.ok) throw new Error(`Asset failed: ${response.status}`);
      return Array.from(new Uint8Array(await response.arrayBuffer()));
    }, selector);
    const expected = await readFile(
      new URL(`../../eigin_website/static/${filename}`, import.meta.url),
    );
    if (filename.endsWith(".svg")) {
      // Vite can inline SVGs with normalized whitespace and quotes.
      expect(
        await page.evaluate(
          ({ actual, expected }) => {
            const normalize = (text: string) =>
              new XMLSerializer()
                .serializeToString(
                  new DOMParser().parseFromString(text, "image/svg+xml"),
                )
                .replace(/>\s+</g, "><")
                .trim();
            return normalize(actual) === normalize(expected);
          },
          {
            actual: Buffer.from(bytes).toString(),
            expected: expected.toString(),
          },
        ),
      ).toBe(true);
    } else {
      expect(Buffer.from(bytes)).toEqual(expected);
    }
  }
  await expect(
    page
      .locator(".site-footer")
      .getByRole("link", { name: "News", exact: true }),
  ).toHaveAttribute("href", "https://www.eigin.ai/en/news/");
});

test("open call identifies its format above the title", async ({ page }) => {
  await page.goto("/calls/tool-safety");
  const tag = page.getByText("Request for spec", { exact: true });
  await expect(tag).toBeVisible();
  const tagBox = await tag.boundingBox();
  const titleBox = await page.getByRole("heading", { level: 1 }).boundingBox();
  expect(tagBox!.y + tagBox!.height).toBeLessThan(titleBox!.y);
});

test("call constraints use independent fold-outs without changing the rest of the brief", async ({
  page,
}) => {
  await page.goto("/calls/tool-safety");
  const constraints = page.locator(".call-constraints details");
  await expect(constraints).toHaveCount(7);
  await expect(page.locator(".call-constraints summary")).toHaveText([
    "Local-first",
    "Cross-platform",
    "Small distribution",
    "Small footprint",
    "Multiple languages",
    "Conservative fallback",
    "Permissive licensing",
  ]);
  for (const disclosure of await constraints.all()) {
    await expect(disclosure).not.toHaveAttribute("open", "");
    await expect(disclosure.locator(".prose")).not.toBeVisible();
    await disclosure.locator("summary").click();
    await expect(disclosure.locator(".prose")).toBeVisible();
  }
  await expect(constraints.nth(2)).toContainText("100 MB");
  await expect(constraints.nth(5)).toContainText(
    "retain the existing approval requirement",
  );
  await constraints.first().locator("summary").focus();
  await page.keyboard.press("Enter");
  await expect(constraints.first()).not.toHaveAttribute("open", "");
  await expect(
    page.getByRole("heading", {
      name: "Boundaries and permissions",
      exact: true,
    }),
  ).toBeVisible();
  expect(
    await page.evaluate(
      () => document.documentElement.scrollWidth <= innerWidth,
    ),
  ).toBe(true);
});

test("About steps and spec qualities fold out while closing paragraphs stay visible", async ({
  page,
}) => {
  await page.goto("/guides/process");
  const steps = page.locator(".foldout-guide details");
  await expect(steps).toHaveCount(5);
  for (const step of await steps.all()) {
    await expect(step.locator(".prose")).not.toBeVisible();
    await step.locator("summary").click();
    await expect(step.locator(".prose")).toBeVisible();
  }
  await expect(
    page.getByRole("heading", { name: "Help us shape the format" }),
  ).toBeVisible();
  await page.goto("/guides/spec");
  const qualities = page.locator(".foldout-guide details");
  await expect(qualities).toHaveCount(8);
  await expect(qualities.first().locator("summary")).toHaveText(
    "It's easy to read",
  );
  for (const quality of await qualities.all())
    await expect(quality.locator(".prose")).not.toBeVisible();
  await expect(
    page.getByText("You're welcome to work with a coding agent.", {
      exact: false,
    }),
  ).toBeVisible();
  await expect(
    page.getByRole("link", { name: "Read an example spec" }),
  ).toBeVisible();
  await qualities.first().locator("summary").click();
  await expect(qualities.first().locator(".prose")).toContainText(
    "Keep it short and use plain language.",
  );
  await expect(qualities.last()).not.toContainText(
    "You're welcome to work with a coding agent.",
  );
  expect(
    await page.evaluate(
      () => document.documentElement.scrollWidth <= innerWidth,
    ),
  ).toBe(true);
});

test("call discussion links to the issue separately from the submission action", async ({
  page,
}) => {
  await page.goto("/calls/tool-safety");
  const discussion = page.getByRole("region", {
    name: "Questions about this call?",
    exact: true,
  });
  await expect(discussion).toBeVisible();
  await expect(
    discussion.getByRole("link", { name: "Chat on Matrix" }),
  ).toHaveAttribute("href", "https://chat.eigin.ai");
  await expect(
    discussion.getByRole("link", { name: "Discuss on GitLab" }),
  ).toHaveAttribute("href", "https://code.eigin.ai/dev/eigin/-/issues/417");
  await expect(discussion.locator(".eigin-btn")).toHaveCount(0);
  const submit = await page
    .getByRole("link", { name: "Submit your spec", exact: true })
    .boundingBox();
  const links = await discussion.boundingBox();
  expect(links!.y).toBeGreaterThan(submit!.y + submit!.height);
});

test("Open Calls header navigation preserves the section anchor offset", async ({
  page,
}) => {
  await page.emulateMedia({ reducedMotion: "reduce" });
  await page.goto("/guides/process");
  await page.evaluate(() => document.fonts.ready.then(() => {}));
  if (page.viewportSize()!.width < 960) {
    await page.getByRole("button", { name: "Menu", exact: true }).click();
    await page
      .getByRole("link", { name: "Open Calls", exact: true })
      .filter({ visible: true })
      .click();
  } else {
    await page
      .getByRole("navigation", { name: "Main navigation" })
      .getByRole("link", { name: "Open Calls", exact: true })
      .click();
  }
  await expect(page).toHaveURL(/\/#open-calls$/);
  const section = page.locator("#open-calls");
  await expect(section).toBeVisible();
  await expect
    .poll(() =>
      section.evaluate((element) =>
        parseFloat(getComputedStyle(element).scrollMarginTop),
      ),
    )
    .toBeGreaterThan(0);
  await expect
    .poll(() =>
      section.evaluate((element) => {
        const expected =
          parseFloat(getComputedStyle(element).scrollMarginTop) +
          parseFloat(
            getComputedStyle(document.documentElement).scrollPaddingTop,
          );
        return Math.abs(element.getBoundingClientRect().top - expected);
      }),
    )
    .toBeLessThan(2);
});

test("a newly configured open call is listed and links to its own submission route", async ({
  page,
  request,
}) => {
  await page.goto("/");
  const link = page
    .locator("#open-calls")
    .getByRole("link", { name: "Open fixture call" });
  await link.click();
  const submit = page.getByRole("link", { name: "Submit your spec" });
  const href = await submit.getAttribute("href");
  expect(href).toMatch(
    /^\/calls\/publication-test-[a-f0-9]{16}-open\/submission$/,
  );
  const response = await request.get(href!, { maxRedirects: 0 });
  expect(response.status()).toBe(303);
  expect(response.headers().location).toBe(
    "/auth/gitlab?returnTo=" + encodeURIComponent(href!),
  );
});
