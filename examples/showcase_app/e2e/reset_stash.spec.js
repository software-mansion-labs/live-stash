const { test, expect } = require("@playwright/test");

const routes = [
  "/test/counter/live_stash_server",
  "/test/counter/live_stash_client",
];

test.describe("LiveView State Recovery - Single Node", () => {
  test.use({ baseURL: "http://localhost:4000" });

  routes.forEach((route) => {
    test(`should not recover counter state after reset stash event on ${route}`, async ({
      page,
    }) => {
      await page.goto(route);

      const incrementBtn = page.getByLabel("Increment");
      const resetStashBtn = page.getByLabel("Reset Stash");
      const counterValue = page.locator(".stat-value");

      await page.waitForFunction(
        () => window.liveSocket && window.liveSocket.isConnected(),
      );

      await incrementBtn.click();
      await expect(counterValue).toHaveText("1");

      await incrementBtn.click();
      await expect(counterValue).toHaveText("2");

      await resetStashBtn.click();
      await expect(counterValue).toHaveText("0");

      await page.evaluate(() => window.liveSocket.disconnect());

      await page.waitForFunction(
        () => window.liveSocket && !window.liveSocket.isConnected(),
      );

      await page.evaluate(() => window.liveSocket.connect());

      await page.waitForFunction(
        () => window.liveSocket && window.liveSocket.isConnected(),
      );
      await expect(counterValue).toHaveText("0");
    });
  });
});
