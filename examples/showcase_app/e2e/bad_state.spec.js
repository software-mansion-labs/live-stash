const { test, expect } = require("@playwright/test");

const routes = [
  "/test/counter/live_stash_server",
  "/test/counter/live_stash_client",
];

test.describe("LiveView State Recovery - Single Node", () => {
  test.use({ baseURL: "http://localhost:4000" });

  routes.forEach((route) => {
    test(`should not kill app when state is bad on ${route}`, async ({
      page,
    }) => {
      await page.goto(route);

      const incrementBtn = page.getByLabel("Increment");
      const counterValue = page.locator(".stat-value");

      await page.waitForFunction(
        () => window.liveSocket && window.liveSocket.isConnected(),
      );

      await page.evaluate(() => window.liveSocket.disconnect());

      await page.waitForFunction(
        () => window.liveSocket && !window.liveSocket.isConnected(),
      );

      await page.evaluate(() => {
        const originalParamsFn = window.liveSocket.params.bind(
          window.liveSocket,
        );

        window.liveSocket.params = () => {
          const p = originalParamsFn();

          p.liveStash = { invalid: "data" };

          return p;
        };
      });

      await page.evaluate(() => window.liveSocket.connect());

      await page.waitForFunction(
        () => window.liveSocket && window.liveSocket.isConnected(),
      );

      await expect(page.locator(".phx-connected").first()).toBeVisible();

      await incrementBtn.click();
      await expect(counterValue).toHaveText("1");
    });
  });
});
