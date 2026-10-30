import { expect, test } from "@playwright/test";

const guidance =
  "Eigin targets iPhone 15 or later for local models. You can still use Eigin with cloud AI.";

// These gallery checks keep the mirrored onboarding and Settings states reviewable.
test("unsupported onboarding explains local availability without offering a download", async ({
  page,
}) => {
  await page.goto("/#/screens/onboarding-inference");
  await page
    .locator(".device-picker")
    .getByRole("radio", { name: "unsupported device", exact: true })
    .click();
  const phone = page.locator(".device-viewport");
  await expect(phone.getByText(/I can think in the cloud/)).toBeVisible();
  await phone.getByRole("button", { name: "Use Eigin offline" }).click();
  await expect(phone.getByText("This device isn’t supported.")).toBeVisible();
  await expect(phone.getByText(guidance)).toBeVisible();
  await expect(phone.getByRole("button", { name: "Download", exact: true })).toHaveCount(0);
  await expect(phone.getByRole("button", { name: "Retry", exact: true })).toHaveCount(0);
  await phone.getByRole("button", { name: "Continue", exact: true }).click();
  await expect(phone.getByRole("button", { name: "Use Eigin", exact: true })).toBeVisible();
  await expect(phone.getByRole("button", { name: "Connect your own provider" })).toBeVisible();
});

test("local download leaves the explanation accessible and explains when switching is possible", async ({
  page,
}) => {
  await page.goto("/#/screens/onboarding-inference");
  const phone = page.locator(".device-viewport");
  await phone.getByRole("button", { name: "Use Eigin offline" }).click();
  await expect(
    phone.getByText("You can download a local model to use Eigin offline."),
  ).toBeVisible();
  await expect(
    phone.getByText(/After onboarding, you can switch to the local model once it’s ready/),
  ).toBeVisible();
  await phone.getByRole("button", { name: "Download", exact: true }).click();
  await expect(phone.getByRole("button", { name: "Download", exact: true })).toHaveCount(0);
  await phone.getByRole("button", { name: "Continue", exact: true }).click();
  await phone.getByRole("button", { name: "Use Eigin offline" }).click();
  await expect(phone.getByRole("button", { name: "Continue", exact: true })).toBeVisible();
});

for (const stage of ["failed", "storage blocked"]) {
  test(`${stage} local downloads remain retryable on supported devices`, async ({ page }) => {
    await page.goto("/#/screens/onboarding-inference");
    await page.evaluate(() => document.fonts.ready);
    const state = page.locator(".device-picker").getByRole("radio", { name: stage, exact: true });
    await state.click();
    await expect(state).toBeChecked();
    const phone = page.locator(".device-viewport");
    await phone.getByRole("button", { name: "Use Eigin offline" }).click();
    if (stage === "storage blocked") {
      await expect(
        phone.getByText("There isn’t enough free storage to download the local model."),
      ).toBeVisible();
    }
    await phone.getByRole("button", { name: "Retry", exact: true }).click();
    await expect(phone.getByRole("button", { name: "Continue", exact: true })).toBeVisible();
  });
}

test("unsupported Settings keeps local requirements visible without a setup action", async ({
  page,
}) => {
  await page.goto("/#/screens/connections");
  await page
    .locator(".device-picker")
    .getByRole("radio", { name: "unsupported device", exact: true })
    .click();
  const phone = page.locator(".device-viewport");
  await expect(phone.getByText("Local model", { exact: true })).toBeVisible();
  await expect(phone.getByText(`This device isn’t supported. ${guidance}`)).toBeVisible();
  await expect(phone.getByRole("button", { name: /Local model/ })).toHaveCount(0);
  await page
    .locator(".device-picker")
    .getByRole("radio", { name: "supported device", exact: true })
    .click();
  await phone.getByRole("button", { name: /Local model/ }).click();
  await expect(page).toHaveURL(/screens\/local-model$/);
});
