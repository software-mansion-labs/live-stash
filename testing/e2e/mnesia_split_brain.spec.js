const { test, expect } = require("@playwright/test");

const NODE_A = "http://localhost:4002";
const NODE_B = "http://localhost:4001";

async function nodeInfo(request, baseUrl) {
  const res = await request.get(`${baseUrl}/test/mnesia/info`);
  expect(res.ok()).toBeTruthy();
  return res.json();
}

test.describe("Mnesia adapter - split-brain auto-heal", () => {
  test("auto-heals after :inconsistent_database event and preserves session state", async ({
    page,
    request,
  }) => {
    const infoA = await nodeInfo(request, NODE_A);
    const infoB = await nodeInfo(request, NODE_B);
    expect(infoA.node).toBe("a@node_a");
    expect(infoB.node).toBe("b@node_b");
    expect(infoA.connected_nodes).toContain("b@node_b");
    expect(infoB.connected_nodes).toContain("a@node_a");
    expect(infoA.mnesia_running).toBeTruthy();
    expect(infoB.mnesia_running).toBeTruthy();

    await page.goto(`${NODE_A}/test/counter/live_stash_mnesia`);
    await page.waitForFunction(
      () => window.liveSocket && window.liveSocket.isConnected(),
    );
    await expect(page.locator(".phx-connected").first()).toBeVisible();

    const incrementBtn = page.getByLabel("Increment");
    const counterValue = page.locator(".stat-value");

    await incrementBtn.click();
    await incrementBtn.click();
    await incrementBtn.click();
    await expect(counterValue).toHaveText("3");

    await expect
      .poll(
        async () => {
          const [a, b] = await Promise.all([
            nodeInfo(request, NODE_A),
            nodeInfo(request, NODE_B),
          ]);
          return a.table_size > 0 && b.table_size === a.table_size;
        },
        { timeout: 5_000, intervals: [200, 500] },
      )
      .toBe(true);

    const poisonRes = await request.post(`${NODE_B}/test/mnesia/poison`);

    if (!poisonRes.ok()) {
      console.error("POISON ENDPOINT FAILED:");
      console.error("Status:", poisonRes.status());
      console.error("Body:", await poisonRes.text());
    }

    expect(poisonRes.ok()).toBeTruthy();

    await expect
      .poll(
        async () => {
          const [a, b] = await Promise.all([
            nodeInfo(request, NODE_A),
            nodeInfo(request, NODE_B),
          ]);
          return b.table_size > a.table_size;
        },
        { timeout: 5_000, intervals: [200, 500] },
      )
      .toBe(true);

    const trigger = await request.post(
      `${NODE_B}/test/mnesia/simulate-inconsistency`,
      { data: { from: "a@node_a" } },
    );
    expect(trigger.ok()).toBeTruthy();

    await expect
      .poll(
        async () => {
          const [a, b] = await Promise.all([
            nodeInfo(request, NODE_A),
            nodeInfo(request, NODE_B),
          ]);
          return a.table_size === b.table_size;
        },
        { timeout: 10_000, intervals: [200, 500] },
      )
      .toBe(true);

    await page.evaluate(() => window.liveSocket.disconnect());
    await page.waitForFunction(
      () => window.liveSocket && !window.liveSocket.isConnected(),
    );
    await page.evaluate(() => window.liveSocket.connect());
    await page.waitForFunction(
      () => window.liveSocket && window.liveSocket.isConnected(),
    );

    await expect(counterValue).toHaveText("3");

    await incrementBtn.click();
    await expect(counterValue).toHaveText("4");

    await expect
      .poll(
        async () => {
          const [a, b] = await Promise.all([
            nodeInfo(request, NODE_A),
            nodeInfo(request, NODE_B),
          ]);
          return a.table_size === b.table_size;
        },
        { timeout: 5_000, intervals: [200, 500] },
      )
      .toBe(true);
  });
});
