const { test, expect } = require("@playwright/test");

const routes = [
  "/test/counter/live_stash_server",
  "/test/counter/live_stash_client",
];

test.describe("ETS & Browser memory adapters - state recovery after reconnect", () => {
  test.use({ baseURL: "http://localhost:4000" });

  routes.forEach((route) => {
    test(`should recover root and component counter state after websocket reconnect on ${route}`, async ({
      page,
    }) => {
      await page.goto(route);

      const incrementBtn = page.getByLabel("Increment");
      const counterValue = page.locator(".stat-value");

      const componentIncrementBtn = page.getByLabel("Component Plus");
      const componentCounterValue = page.getByTestId("component-count");

      await page.waitForFunction(
        () => window.liveSocket && window.liveSocket.isConnected(),
      );

      await expect(page.locator(".phx-connected").first()).toBeVisible();

      await incrementBtn.click();
      await expect(counterValue).toHaveText("1");

      await incrementBtn.click();
      await expect(counterValue).toHaveText("2");

      await componentIncrementBtn.click();
      await expect(componentCounterValue).toHaveText("1");

      await componentIncrementBtn.click();
      await expect(componentCounterValue).toHaveText("2");

      await componentIncrementBtn.click();
      await expect(componentCounterValue).toHaveText("3");

      await page.evaluate(() => window.liveSocket.disconnect());

      await page.waitForFunction(
        () => window.liveSocket && !window.liveSocket.isConnected(),
      );

      await page.evaluate(() => window.liveSocket.connect());

      await page.waitForFunction(
        () => window.liveSocket && window.liveSocket.isConnected(),
      );

      await expect(page.locator(".phx-connected").first()).toBeVisible();

      await expect(counterValue).toHaveText("2");
      await expect(componentCounterValue).toHaveText("3");
    });
  });
});
