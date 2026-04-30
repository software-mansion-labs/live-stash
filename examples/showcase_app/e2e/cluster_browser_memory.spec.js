const { test, expect } = require("@playwright/test");

test.describe("Browser memory adapter - state recovery on cluster", () => {
  test.use({ baseURL: "http://localhost:8080" });

  test("should retain state when a node goes down and traffic is redirected", async ({
    page,
  }) => {
    await page.goto("/test/counter/live_stash_client");

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
    await expect(componentCounterValue).toHaveText("2");
  });
});
