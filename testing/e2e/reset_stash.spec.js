const { test, expect } = require("@playwright/test");
const { reconnect, routes, waitForConnected } = require("./helpers");

test.describe("All adapters - reset stash", () => {
  test.use({ baseURL: "http://localhost:4000" });

  routes.forEach((route) => {
    test(`should not recover counter state after reset stash event on ${route}`, async ({
      page,
    }) => {
      await page.goto(route);

      const incrementBtn = page.getByLabel("Increment");
      const resetStashBtn = page.getByLabel("Reset Stash");
      const counterValue = page.locator(".stat-value");

      await waitForConnected(page);

      await incrementBtn.click();
      await expect(counterValue).toHaveText("1");

      await incrementBtn.click();
      await expect(counterValue).toHaveText("2");

      await resetStashBtn.click();
      await expect(counterValue).toHaveText("0");

      await reconnect(page);

      await expect(counterValue).toHaveText("0");
    });
  });
});
