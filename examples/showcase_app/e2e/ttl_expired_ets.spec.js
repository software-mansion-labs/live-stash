const { test, expect } = require("@playwright/test");

test.describe("LiveView State Recovery - Single Node", () => {
  test.use({ baseURL: "http://localhost:4000" });

  test(`should not recover counter state after ttl expires in ETS adapter`, async ({
    page,
  }) => {
    await page.goto("/test/counter/live_stash_server");

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
