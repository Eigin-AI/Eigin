import { expect, test } from "@playwright/test";
import originals from "./fixtures/documents.json" with { type: "json" };

const slugs = ["privacy", "terms", "contact", "support"] as const;

for (const locale of ["en", "da"]) {
  for (const slug of slugs) {
    test(`${locale}/${slug} preserves legal/English copy and localizes contact/support`, async ({
      page,
    }) => {
      await page.goto(`/${locale}/${slug}/`);
      await expect(page.locator("html")).toHaveAttribute("lang", locale);
      const legal = slug === "privacy" || slug === "terms";
      await expect(page.locator("main")).toHaveAttribute("lang", legal ? "en" : locale);
      await expect(page.locator("h1")).toHaveCount(1);
      await expect(page.locator(".document-prose details")).toHaveCount(0);
      const text = await page
        .locator(".document-updated, .document-title, .document-prose")
        .evaluateAll((nodes) =>
          nodes
            .map((node) => {
              const clone = node.cloneNode(true) as HTMLElement;
              for (const label of clone.querySelectorAll(".reach-channel-label, .reach-people"))
                label.remove();
              for (const br of clone.querySelectorAll("br")) br.replaceWith(" ");
              for (const block of clone.querySelectorAll("p,div,li,h2,h3,section,ul"))
                block.append(" ");
              return clone.textContent;
            })
            .join(" ")
            .replace(/\s+/g, " ")
            .trim(),
        );
      if (legal || (locale === "en" && slug === "contact")) expect(text).toBe(originals[slug].text);
      else if (locale === "en" && slug === "support") {
        expect(text).toContain("Something not working? Let us know and we'll help you fix it.");
        expect(text).toContain("Send Feedback");
        expect(text).toContain("feedback and support requests directly from the app.");
      } else {
        expect(text).not.toBe(originals[slug].text);
        await expect(page.locator("h1")).toHaveText(slug === "contact" ? "Kontakt" : "Support");
        await expect(page.locator(".reach-action a")).toHaveText(
          slug === "contact" ? "Sig hej" : "Skriv til os",
        );
        await expect(page.locator(".document-prose").first()).toContainText(
          slug === "contact" ? "Sådan får du fat i os." : "Virker noget ikke?",
        );
      }
      const links = await page.locator(".document-prose a").evaluateAll((nodes) =>
        nodes.map((node) => ({
          text: node.textContent!.replace(/\s+/g, " ").trim(),
          href: node.getAttribute("href"),
        })),
      );
      const expectedLinks = originals[slug].links
        .filter((_, index) => slug !== "contact" || index !== 1)
        .map((link) => ({
          ...link,
          href: /^\/(privacy|terms|contact|support)\/$/.test(link.href)
            ? `/${locale}${link.href}`
            : link.href,
        }));
      if (slug === "support") {
        expect(links.map((link) => link.href)).toEqual([
          "mailto:support@eigin.ai?subject=Eigin%20support%20request",
          "https://chat.eigin.ai",
          "https://code.eigin.ai",
          `/${locale}/contact/`,
        ]);
      } else if (legal || locale === "en") expect(links).toEqual(expectedLinks);
      else expect(links.map((link) => link.href)).toEqual(expectedLinks.map((link) => link.href));
      if (locale === "da" && legal)
        await expect(page.locator(".document-language")).toHaveAttribute("lang", "da");
      else await expect(page.locator(".document-language")).toHaveCount(0);
      const company = page.locator(".site-footer").getByRole("navigation", {
        name: locale === "en" ? "Company" : "Virksomhed",
        exact: true,
      });
      expect(
        await company
          .locator("a")
          .evaluateAll((nodes) => nodes.map((node) => node.getAttribute("href"))),
      ).toEqual(["contact", "support", "privacy", "terms"].map((name) => `/${locale}/${name}/`));
      for (const name of slugs) {
        await expect(page.locator(`.site-header a[href$="/${name}/"]`)).toHaveCount(0);
        await expect(company.locator(`a[href="/${locale}/${name}/"]`)).toHaveCount(1);
      }
    });
  }

  test(`${locale} documents fit small screens and keep readable desktop columns`, async ({
    page,
  }) => {
    for (const slug of slugs) {
      await page.goto(`/${locale}/${slug}/`);
      await page.evaluate(() => document.fonts.ready);
      for (const width of [320, 390, 600, 601, 768, 1023, 1024, 1440]) {
        await page.setViewportSize({ width, height: 900 });
        expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth)).toBe(
          true,
        );
        const legal = slug === "privacy" || slug === "terms";
        for (const prose of await page.locator(".document-prose").all()) {
          expect(
            await prose.evaluate(
              (node) =>
                parseFloat(getComputedStyle(node).lineHeight) /
                parseFloat(getComputedStyle(node).fontSize),
            ),
          ).toBeGreaterThanOrEqual(1.5);
          const box = (await prose.boundingBox())!;
          expect(box.x).toBeGreaterThanOrEqual(24);
          expect(box.x + box.width).toBeLessThanOrEqual(width - 23);
          if (legal) expect(box.width).toBeLessThanOrEqual(720);
        }
        if (slug === "contact") {
          const spacing = await page.locator(".reach-contact-details").evaluate((node) => {
            const style = getComputedStyle(node);
            return [parseFloat(style.paddingTop), parseFloat(style.paddingBottom)];
          });
          for (const value of spacing) expect(value).toBeGreaterThanOrEqual(64);
        }
        if (!legal) await expect(page.locator(".document-sidebar")).toHaveCount(0);
        else if (width >= 1024) {
          await expect(page.locator(".document-desktop-index")).toBeVisible();
          await expect(page.locator(".document-mobile-index")).toBeHidden();
        } else {
          await expect(page.locator(".document-desktop-index")).toBeHidden();
          await expect(page.locator(".document-mobile-index summary")).toBeVisible();
        }
      }
    }
  });

  test(`${locale} footer navigation, language switching, and keyboard section links work`, async ({
    page,
    browserName,
  }) => {
    await page.goto(`/${locale}/`);
    await page.locator(`.site-footer .footer-links a[href="/${locale}/privacy/"]`).click();
    await expect(page).toHaveURL(new RegExp(`/${locale}/privacy/$`));
    const other = locale === "en" ? "da" : "en";
    await page.locator("footer .language-links .picker-trigger").click();
    await page.locator(`.language-links a[href="/${other}/privacy/"]`).click();
    await expect(page).toHaveURL(new RegExp(`/${other}/privacy/$`));
    await page.setViewportSize({ width: 390, height: 844 });
    await page.evaluate(() => document.fonts.ready);
    const index = page.locator(".document-mobile-index");
    await index.locator("summary").focus();
    await page.keyboard.press("Enter");
    await expect(index).toHaveAttribute("open", "");
    await index.locator('a[href="#your-rights"]').focus();
    await page.keyboard.press("Enter");
    await expect(page).toHaveURL(/#your-rights$/);
    const heading = page.locator("h2#your-rights");
    await expect(heading).toBeFocused();
    await expect.poll(async () => (await heading.boundingBox())!.y).toBeGreaterThanOrEqual(72);
    await page.keyboard.press(browserName === "webkit" ? "Alt+Tab" : "Tab");
    await expect(
      page.locator(".document-section a").filter({ hasText: "datatilsynet.dk" }),
    ).toBeFocused();
  });
}

test("all documents and their mobile section index work without JavaScript", async ({
  browser,
  baseURL,
}) => {
  const context = await browser.newContext({
    javaScriptEnabled: false,
    baseURL,
    viewport: { width: 390, height: 844 },
  });
  try {
    const page = await context.newPage();
    for (const locale of ["en", "da"])
      for (const slug of slugs) {
        await page.goto(`/${locale}/${slug}/`);
        await expect(page.locator("h1")).toBeVisible();
        if (slug === "privacy" || slug === "terms") {
          const index = page.locator(".document-mobile-index");
          await index.locator("summary").click();
          const link = index.locator("a").last();
          const target = await link.getAttribute("href");
          await link.click();
          await expect(page.locator(`h2${target}`)).toBeInViewport();
        } else {
          await expect(page.locator(".reach-action a")).toBeVisible();
          if (slug === "contact") await expect(page.locator(".reach-person img")).toHaveCount(2);
        }
        await expect(
          page.locator(`.site-footer .footer-links a[href="/${locale}/${slug}/"]`).first(),
        ).toHaveAttribute("href", `/${locale}/${slug}/`);
      }
  } finally {
    await context.close();
  }
});

test("printing keeps the complete text and removes site navigation", async ({ page }) => {
  await page.goto("/en/privacy/");
  await page.emulateMedia({ media: "print" });
  await expect(page.locator(".site-header")).toBeHidden();
  await expect(page.locator(".site-footer")).toBeHidden();
  await expect(page.locator(".document-sidebar")).toBeHidden();
  await expect(page.locator(".document-section")).toHaveCount(11);
  await expect(page.locator("h2#changes")).toBeVisible();
});

for (const locale of ["en", "da"]) {
  test(`${locale} contact shows the team and keeps contact/support language navigation local`, async ({
    page,
  }) => {
    await page.goto(`/${locale}/contact/`);
    const people = page.locator(".reach-person");
    await expect(people).toHaveCount(2);
    await expect(page.locator(".reach-detail a.arrow-link")).toHaveCount(0);
    await expect(
      page.locator('.reach-details-label .section-heading-icon[aria-hidden="true"]'),
    ).toHaveCount(1);
    await expect(page.locator(".reach-hero .reach-person")).toHaveCount(0);
    const companyDetails = page.locator(".reach-detail").filter({ has: page.locator("#company") });
    await expect(companyDetails.locator(".reach-person")).toHaveCount(2);
    await expect(companyDetails).toContainText(
      locale === "en"
        ? "We're a distributed team based in Copenhagen and Aarhus."
        : "Vi er et distribueret team med base i København og Aarhus.",
    );
    await expect(
      companyDetails.locator(".reach-detail-content > .document-section-copy"),
    ).toContainText("CVR 46428765");
    await expect(people.nth(0)).toContainText("Daniel Rothmann");
    await expect(people.nth(1)).toContainText("Therkel Sand Therkelsen");
    await expect(people.nth(0)).toContainText(
      locale === "da" ? "Medstifter og CTO" : "Co-founder and CTO",
    );
    await expect(people.nth(1)).toContainText(
      locale === "da" ? "Medstifter og CEO" : "Co-founder and CEO",
    );
    await expect
      .poll(() =>
        people
          .locator("img")
          .evaluateAll((nodes) =>
            nodes.every(
              (node) =>
                (node as HTMLImageElement).complete && (node as HTMLImageElement).naturalWidth > 0,
            ),
          ),
      )
      .toBe(true);
    await expect(page.locator(".reach-action a")).toHaveAttribute("href", "mailto:hello@eigin.ai");
    await page.locator(`.reach-detail a[href="/${locale}/support/"]`).click();
    await expect(page).toHaveURL(new RegExp(`/${locale}/support/$`));
    await expect(page.locator(".reach-action a")).toHaveAttribute(
      "href",
      "mailto:support@eigin.ai?subject=Eigin%20support%20request",
    );
    const other = locale === "en" ? "da" : "en";
    await page.locator("footer .language-links .picker-trigger").click();
    await page.locator(`.language-links a[href="/${other}/support/"]`).click();
    await expect(page).toHaveURL(new RegExp(`/${other}/support/$`));
    await expect(page.locator("main")).toHaveAttribute("lang", other);
    await page.locator(`.reach-support-other a[href="/${other}/contact/"]`).click();
    await expect(page).toHaveURL(new RegExp(`/${other}/contact/$`));
    await expect(page.locator("h1")).toHaveText(other === "da" ? "Kontakt" : "Contact");
  });
}

for (const locale of ["en", "da"]) {
  test(`${locale} policy links are reciprocal and legal section navigation tracks scrolling`, async ({
    page,
  }) => {
    await page.setViewportSize({ width: 1440, height: 1000 });
    await page.goto(`/${locale}/privacy/`);
    await page.evaluate(() => document.fonts.ready);
    const index = page.locator(".document-desktop-index");
    for (const id of ["who-we-are", "ai-models", "your-rights", "your-data-stays-on-your-device"]) {
      await page.locator(`h2#${id}`).evaluate((node) => {
        const offset = parseFloat(getComputedStyle(document.documentElement).scrollPaddingTop);
        window.scrollTo(0, node.getBoundingClientRect().top + scrollY - offset);
      });
      await expect(index.locator(`a[href="#${id}"]`)).toHaveAttribute("aria-current", "location");
      await expect(index.locator('[aria-current="location"]')).toHaveCount(1);
    }
    await page.locator(`.document-related a[href="/${locale}/trust/"]`).click();
    await expect(page).toHaveURL(new RegExp(`/${locale}/trust/$`));
    await expect(page.locator(`main a[href="/${locale}/privacy/"]`)).toHaveCount(1);
    await expect(page.locator(`main a[href="/${locale}/terms/"]`)).toHaveCount(1);
    await expect(
      page.locator(
        'main a[href="https://www.eigin.ai/privacy/"], main a[href="https://www.eigin.ai/terms/"]',
      ),
    ).toHaveCount(0);
    await page.locator(`main a[href="/${locale}/privacy/"]`).click();
    await page.setViewportSize({ width: 390, height: 844 });
    const toc = (await page.locator(".document-mobile-index").boundingBox())!;
    const prose = (await page.locator(".document-prose").boundingBox())!;
    expect(Math.abs(toc.x - prose.x)).toBeLessThan(1);
    expect(Math.abs(toc.width - prose.width)).toBeLessThan(1);
  });
}

for (const locale of ["en", "da"]) {
  test(`${locale} support distinguishes feedback, email diagnostics, and optional logs with clear primary and secondary routes`, async ({
    page,
  }) => {
    await page.setViewportSize({ width: 1440, height: 1000 });
    await page.goto(`/${locale}/support/`);
    await page.evaluate(() => document.fonts.ready);
    await expect(page.locator(".reach-copy")).toContainText(
      locale === "en" ? "Send Feedback" : "Giv feedback",
    );
    await expect(page.locator(".reach-copy")).toContainText(
      locale === "en"
        ? "feedback and support requests directly from the app."
        : "feedback og bede om hjælp direkte fra appen.",
    );
    await expect(
      page.getByRole("heading", {
        name: locale === "en" ? "Email us" : "Skriv til os",
        exact: true,
      }),
    ).toHaveCount(0);
    await expect(page.locator(".reach-action a")).toBeVisible();
    await expect(page.locator(".reach-copy")).toContainText("support@eigin.ai");
    await expect(page.locator(".reach-action a")).toHaveText(
      locale === "en" ? "Reach out" : "Skriv til os",
    );
    const leads = page.locator(".reach-introduction .document-lead");
    await expect(leads).toHaveCount(2);
    const typography = await leads.evaluateAll((nodes) =>
      nodes.map((node) => {
        const style = getComputedStyle(node);
        return {
          fontSize: style.fontSize,
          lineHeight: style.lineHeight,
          fontFamily: style.fontFamily,
        };
      }),
    );
    expect(typography[0]).toEqual(typography[1]);
    await expect(page.locator(".reach-help-panel li")).toHaveCount(4);
    await expect(page.locator(".reach-help-panel")).toContainText(
      locale === "en" ? "Settings → About" : "Indstillinger → Om",
    );
    await expect(page.locator(".reach-help-panel")).toContainText(
      locale === "en"
        ? "Settings → Advanced → Logging → Export Log"
        : "Indstillinger → Avanceret → Logning → Eksportér log",
    );
    await expect(page.locator(".support-privacy-note")).toContainText(
      locale === "en"
        ? "Avoid sending us your conversations if you can."
        : "Undlad så vidt muligt at sende dine samtaler.",
    );
    await expect(page.locator('.reach-hero a[href="https://chat.eigin.ai"]')).toHaveCount(0);
    await expect(page.locator(".reach-support-other a")).toHaveCount(3);
    const primary = (await page.locator(".reach-hero").boundingBox())!;
    const secondary = (await page.locator(".reach-support-other").boundingBox())!;
    expect(secondary.y).toBeGreaterThanOrEqual(primary.y + primary.height - 1);
  });
}
