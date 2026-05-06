const { test, expect } = require("@playwright/test");

const routes = [
  "/test/counter/live_stash_server",
  "/test/counter/live_stash_client",
  "/test/counter/live_stash_redis",
];

test.describe("ETS, BrowserMemory, and Redis adapters - TTL expiration", () => {
  test.use({ baseURL: "http://localhost:4000" });

  routes.forEach((route) => {
    test(`should not recover expired state on ${route}`, async ({ page }) => {
      await page.goto(route);

      const incrementBtn = page.getByLabel("Increment");
      const counterValue = page.locator(".stat-value");

      await page.waitForFunction(
        () => window.liveSocket && window.liveSocket.isConnected(),
      );

      await expect(page.locator(".phx-connected").first()).toBeVisible();

      await incrementBtn.click();
      await expect(counterValue).toHaveText("1");

      await incrementBtn.click();
      await expect(counterValue).toHaveText("2");

      await page.evaluate(() => window.liveSocket.disconnect());

      await page.waitForFunction(
        () => window.liveSocket && !window.liveSocket.isConnected(),
      );

      await page.waitForTimeout(2000);

      await page.evaluate(() => window.liveSocket.connect());

      await page.waitForFunction(
        () => window.liveSocket && window.liveSocket.isConnected(),
      );

      await expect(page.locator(".phx-connected").first()).toBeVisible();

      await expect(counterValue).toHaveText("0");
    });
  });
});
