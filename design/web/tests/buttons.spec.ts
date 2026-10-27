import { expect, test } from "@playwright/test";

for (const colorScheme of ["light", "dark"] as const) {
  test(`disabled elevated and outline buttons match secondary text in ${colorScheme}`, async ({
    page,
  }) => {
    await page.emulateMedia({ colorScheme });
    await page.goto("/#/components/buttons");
    const controls = page.locator(".doc .controls").first();
    const button = page.getByRole("button", { name: "Action text", exact: true }).first();
    await controls.getByRole("radio", { name: "secondary", exact: true }).click();
    await controls.getByRole("radio", { name: "disabled", exact: true }).click();
    await expect(button).toBeDisabled();
    const secondaryColor = await button.evaluate((element) => getComputedStyle(element).color);

    for (const variant of ["elevated", "outline"]) {
      await controls.getByRole("radio", { name: variant, exact: true }).click();
      await expect(button).toBeDisabled();
      await expect(button).toHaveCSS("color", secondaryColor);
      if (variant === "outline") {
        await expect(button).toHaveCSS("background-color", "rgba(0, 0, 0, 0)");
        await expect(button).toHaveCSS("border-top-color", secondaryColor);
        expect(
          await button.evaluate((element) => getComputedStyle(element, "::before").backgroundColor),
        ).toBe("rgba(0, 0, 0, 0)");
      }
    }
  });
}
