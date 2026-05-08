const { test, expect } = require("@playwright/test");
const { routes, waitForConnected } = require("./helpers");

test.describe("All adapters - state recovery with bad state", () => {
  test.use({ baseURL: "http://localhost:4000" });

  routes.forEach((route) => {
    test(`should not kill app when state is bad on ${route}`, async ({
      page,
    }) => {
      await page.goto(route);

      const incrementBtn = page.getByLabel("Increment");
      const counterValue = page.locator(".stat-value");

      await waitForConnected(page);

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

      await waitForConnected(page);

      await incrementBtn.click();
      await expect(counterValue).toHaveText("1");
    });
  });
});
