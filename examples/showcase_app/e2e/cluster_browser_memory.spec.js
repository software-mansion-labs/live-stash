const { test, expect } = require("@playwright/test");
const { execSync } = require("child_process");

test.describe("LiveView State Recovery - Cluster", () => {
  test.use({ baseURL: "http://localhost:8080" });

  test("should retain state when a node goes down and traffic is redirected", async ({
    page,
  }) => {
    await page.goto("/counter/live_stash_client");

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

    await page.evaluate(() => window.liveSocket.connect());

    await page.waitForFunction(
      () => window.liveSocket && window.liveSocket.isConnected(),
    );

    await expect(page.locator(".phx-connected").first()).toBeVisible();

    await expect(counterValue).toHaveText("2");
  });
});
