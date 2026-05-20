const { test, expect } = require("@playwright/test");
const { reconnect, routes, waitForConnected } = require("./helpers");

test.describe("All adapters - bumps ttl", () => {
  test.use({ baseURL: "http://localhost:4000" });

  routes.forEach((route) => {
    test(`should recover counter state after websocket reconnect on ${route}`, async ({
      page,
    }) => {
      await page.goto(route);

      const incrementBtn = page.getByLabel("Increment");
      const counterValue = page.locator(".stat-value");

      await waitForConnected(page);

      await incrementBtn.click();
      await expect(counterValue).toHaveText("1");

      await page.waitForTimeout(700);

      await incrementBtn.click();
      await expect(counterValue).toHaveText("2");

      await reconnect(page, { delayMs: 400 });

      await expect(counterValue).toHaveText("2");
    });
  });
});
