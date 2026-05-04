const { test, expect } = require("@playwright/test");

/**
 * Performance tests — reconnect latency per adapter.
 *
 * What is measured - time from connect() to the DOM reflecting recovered status:
 *
 * Why the numbers differ between adapters
 * ----------------------------------------
 * ETS:           only a UUID (stash-id) travels browser ->server on reconnect.
 *                Reconnect latency is independent of payload size.
 *
 * BrowserMemory: the full signed token travels browser ->server on every reconnect
 *                as a URL query parameter in the WebSocket upgrade request.
 *                Larger state = larger URL = more transfer time + more verify work.
 *
 * BrowserMemory URL size constraint
 * ----------------------------------
 * The token lives in the WebSocket upgrade URL, so it is bounded by the server's
 * max request-line length (Bandit default: ~10 KB, Nginx default: ~8 KB).  A ~4 KB raw payload produces
 * a ~6 KB encoded token.
 * Larger payloads cause "Request URI is too long" — an architectural constraint.
 *
 * Payload sizes
 * -------------
 * small   ~15 B    %{count: 1}                        — shared
 * medium  ~4 KB    60 string entries × 60 chars each  — shared
 * large   ~254 KB  500 entries × 500 chars            — ETS only
 */

test.skip(
  !!process.env.CI,
  "Performance tests are skipped on CI to save time and avoid flakes",
);

const BASE_URL = "http://localhost:4000";

async function waitForStashed(page) {
  await page.waitForSelector('[data-stashed="true"]', { timeout: 15_000 });
}

async function measureReconnect(page) {
  await page.evaluate(() => window.liveSocket.disconnect());

  await page.waitForFunction(
    () => window.liveSocket && !window.liveSocket.isConnected(),
    { timeout: 10_000 },
  );

  const t0 = Date.now();

  await page.evaluate(() => window.liveSocket.connect());

  await page.waitForSelector('[data-status="recovered"]', { timeout: 15_000 });

  return Date.now() - t0;
}

// Reconnect latency — small + medium, both adapters

const adapters = [
  { name: "ETS", route: "/perf/ets" },
  { name: "BrowserMemory", route: "/perf/browser_memory" },
];

test.describe("reconnect latency (small + medium payloads)", () => {
  test.use({ baseURL: BASE_URL });

  test.beforeEach(async ({ page }) => {
    const client = await page.context().newCDPSession(page);
    await client.send("Network.enable");
    await client.send("Network.emulateNetworkConditions", {
      offline: false,
      downloadThroughput: (1.5 * 1024 * 1024) / 8, // 1.5 Mbps
      uploadThroughput: (750 * 1024) / 8, // 750 Kbps
      latency: 40, // 40 ms ping
    });
  });

  adapters.forEach((adapter) => {
    ["small", "medium"].forEach((size) => {
      test(`[${adapter.name}] reconnect with ${size} payload`, async ({
        page,
      }) => {
        await page.goto(`${adapter.route}?size=${size}`);

        await page.waitForFunction(
          () => window.liveSocket && window.liveSocket.isConnected(),
        );

        await waitForStashed(page);

        const bytes = await page
          .locator("#perf")
          .getAttribute("data-payload-bytes");

        const ms = await measureReconnect(page);

        console.log(
          `  [${adapter.name}] reconnect ${size}, payload ${bytes} B: ${ms} ms`,
        );
      });
    });
  });
});

// Reconnect latency — large payload, ETS only

test.describe("reconnect latency (large payload, ETS only)", () => {
  test.use({ baseURL: BASE_URL });

  test.beforeEach(async ({ page }) => {
    const client = await page.context().newCDPSession(page);
    await client.send("Network.enable");
    await client.send("Network.emulateNetworkConditions", {
      offline: false,
      downloadThroughput: (1.5 * 1024 * 1024) / 8, // 1.5 Mbps
      uploadThroughput: (750 * 1024) / 8, // 750 Kbps
      latency: 40, // 40 ms ping
    });
  });

  test("[ETS] reconnect with large payload", async ({ page }) => {
    await page.goto("/perf/ets?size=large");

    await page.waitForFunction(
      () => window.liveSocket && window.liveSocket.isConnected(),
    );

    await waitForStashed(page);

    const bytes = await page
      .locator("#perf")
      .getAttribute("data-payload-bytes");
    const ms = await measureReconnect(page);

    console.log(`[ETS] reconnect (large, ${bytes} B): ${ms} ms`);
  });
});

// Concurrent reconnects — medium payload, both adapters

const CONCURRENT_COUNT = 10;

test.describe("concurrent reconnects (medium payload)", () => {
  test.use({ baseURL: BASE_URL });
  test.setTimeout(120_000);

  adapters.forEach((adapter) => {
    test(`[${adapter.name}] ${CONCURRENT_COUNT} concurrent reconnects`, async ({
      browser,
    }) => {
      const pages = await Promise.all(
        Array.from({ length: CONCURRENT_COUNT }, () => browser.newPage()),
      );

      try {
        await Promise.all(
          pages.map((p) => p.goto(`${adapter.route}?size=medium`)),
        );

        await Promise.all(
          pages.map((p) =>
            p.waitForFunction(
              () => window.liveSocket && window.liveSocket.isConnected(),
            ),
          ),
        );

        await Promise.all(pages.map((p) => waitForStashed(p)));

        await Promise.all(
          pages.map((p) => p.evaluate(() => window.liveSocket.disconnect())),
        );

        await Promise.all(
          pages.map((p) =>
            p.waitForFunction(
              () => window.liveSocket && !window.liveSocket.isConnected(),
              { timeout: 10_000 },
            ),
          ),
        );

        const t0 = Date.now();

        await Promise.all(
          pages.map((p) => p.evaluate(() => window.liveSocket.connect())),
        );

        await Promise.all(
          pages.map((p) =>
            p.waitForSelector('[data-status="recovered"]', { timeout: 30_000 }),
          ),
        );

        const ms = Date.now() - t0;

        console.log(
          `  [${adapter.name}] ${CONCURRENT_COUNT} concurrent reconnects: ${ms} ms`,
        );
      } finally {
        await Promise.all(pages.map((p) => p.close()));
      }
    });
  });
});
