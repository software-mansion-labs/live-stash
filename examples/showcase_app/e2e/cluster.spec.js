const { test, expect } = require("@playwright/test");
const { reconnect, routes, waitForConnected } = require("./helpers");

const CLUSTER_NODES = 2;

test.describe("All adapters - state recovery on cluster", () => {
  test.use({ baseURL: "http://localhost:8080" });

  routes.forEach((route) => {
    test(`should recover state in cluster on ${route}`, async ({ page }) => {
      await page.goto(route);

      const incrementBtn = page.getByLabel("Increment");
      const counterValue = page.locator(".stat-value");

      await waitForConnected(page);

      await incrementBtn.click();
      await expect(counterValue).toHaveText("1");

      await incrementBtn.click();
      await expect(counterValue).toHaveText("2");

      for (let i = 0; i < CLUSTER_NODES + 1; i++) {
        await reconnect(page, { delayMs: 100 });
        await expect(counterValue).toHaveText("2");
      }
    });
  });
});
