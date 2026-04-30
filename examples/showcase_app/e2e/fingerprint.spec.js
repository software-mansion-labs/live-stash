const { test, expect } = require("@playwright/test");

test.describe("Browser memory adapter - fingerprint optimization", () => {
  test.use({ baseURL: "http://localhost:4000" });

  test("does not emit extra stash events when fingerprint is unchanged", async ({
    page,
  }) => {
    await page.addInitScript(() => {
      window.__stashCount = 0;
      window.addEventListener("phx:live-stash:stash-state", () => {
        window.__stashCount++;
      });
    });

    await page.goto("/test/counter/live_stash_client");

    const incrementBtn = page.getByLabel("Increment");
    const addZeroBtn = page.getByLabel("Add Zero");
    const counterValue = page.locator(".stat-value");

    const componentIncrementBtn = page.getByLabel("Component Plus");
    const componentCounterValue = page.getByTestId("component-count");

    await page.waitForFunction(
      () => window.liveSocket && window.liveSocket.isConnected(),
    );
    await expect(page.locator(".phx-connected").first()).toBeVisible();

    await incrementBtn.click();
    await expect(counterValue).toHaveText("1");

    await expect(async () => {
      const count = await page.evaluate(() => window.__stashCount);
      expect(count).toBe(1);
    }).toPass();

    await addZeroBtn.click();
    await expect(counterValue).toHaveText("1");

    await page.waitForTimeout(200);

    const stashCountAfterZero = await page.evaluate(() => window.__stashCount);
    expect(stashCountAfterZero).toBe(1);

    await componentIncrementBtn.click();
    await expect(componentCounterValue).toHaveText("1");

    await expect(async () => {
      const count = await page.evaluate(() => window.__stashCount);
      expect(count).toBe(2);
    }).toPass();

    await addZeroBtn.click();
    await expect(counterValue).toHaveText("1");

    await page.waitForTimeout(200);

    const stashCountAfterFinalZero = await page.evaluate(
      () => window.__stashCount,
    );
    expect(stashCountAfterFinalZero).toBe(2);
  });
});
