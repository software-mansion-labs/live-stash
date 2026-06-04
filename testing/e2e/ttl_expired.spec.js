const { test, expect } = require("@playwright/test");
const { reconnect, routes, waitForConnected } = require("./helpers");

test.describe("All adapters - TTL expiration", () => {
  test.use({ baseURL: "http://localhost:4000" });

  routes.forEach((route) => {
    test(`should not recover expired state on ${route}`, async ({ page }) => {
      await page.goto(route);

      const incrementBtn = page.getByLabel("Increment");
      const counterValue = page.locator(".stat-value");

      await waitForConnected(page);

      await incrementBtn.click();
      await expect(counterValue).toHaveText("1");

      await incrementBtn.click();
      await expect(counterValue).toHaveText("2");

      await reconnect(page, { delayMs: 3000 });

      await expect(counterValue).toHaveText("0");
    });
  });
});
