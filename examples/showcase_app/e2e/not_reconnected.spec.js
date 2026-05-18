const { test, expect } = require("@playwright/test");
const { reconnect, routes, waitForConnected } = require("./helpers");

test.describe("All adapters - not reconnected", () => {
  test.use({ baseURL: "http://localhost:4000" });

  routes.forEach((route) => {
    test(`should not recover counter state after first mount on ${route}`, async ({
      page,
    }) => {
      await page.goto(route);

      const incrementBtn = page.getByLabel("Increment");
      const counterValue = page.locator(".stat-value");

      await waitForConnected(page);

      await incrementBtn.click();
      await expect(counterValue).toHaveText("1");

      await incrementBtn.click();
      await expect(counterValue).toHaveText("2");

      await page.goto("/");
      await page.goto(route);

      await waitForConnected(page);

      await reconnect(page);

      await expect(counterValue).toHaveText("0");
    });
  });
});
