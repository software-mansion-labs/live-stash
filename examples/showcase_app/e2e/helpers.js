const { expect } = require("@playwright/test");

const routes = [
  "/test/counter/live_stash_server",
  "/test/counter/live_stash_client",
  "/test/counter/live_stash_redis",
  "/test/counter/live_stash_mnesia",
];

async function waitForConnected(page) {
  await page.waitForFunction(
    () => window.liveSocket && window.liveSocket.isConnected(),
  );
  await expect(page.locator(".phx-connected").first()).toBeVisible();
}

async function reconnect(page, { delayMs = 0 } = {}) {
  await page.evaluate(
    () => new Promise((resolve) => window.liveSocket.disconnect(resolve)),
  );

  if (delayMs > 0) await page.waitForTimeout(delayMs);

  await page.evaluate(() => window.liveSocket.connect());
  await waitForConnected(page);
}

module.exports = { routes, waitForConnected, reconnect };
