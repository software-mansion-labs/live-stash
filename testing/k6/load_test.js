import http from "k6/http";
import ws from "k6/ws";
import { check, fail, sleep } from "k6";
import { Trend } from "k6/metrics";

const firstRenderRTT = new Trend("first_render_rtt_ms", true);
const stashRTT = new Trend("stash_rtt_ms", true);
const reconnectRTT = new Trend("reconnect_rtt_ms", true);

const HOST = __ENV.HOST || "localhost:4000";
const SIZE_KB = __ENV.SIZE_KB || "100";
const BASE_PATH = __ENV.BASE_PATH || "/performance/livestash_ets";
const VUS = parseInt(__ENV.VUS || "50");

// Adapter TTL (must match the LiveStash :ttl in the LiveView module).
const TTL = parseFloat(__ENV.TTL || "300");

// Probability (0-100) that the gap between disconnect and reconnect is shorter
// than TTL (i.e. the stash is still recoverable). The complement reconnects
// after TTL has elapsed → fresh mount.
const RECONNECT_WITHIN_TTL_PCT = parseFloat(
  __ENV.RECONNECT_WITHIN_TTL_PCT || "100",
);

// Test profile: 5 min total = ramp up + hold + ramp down.
const RAMP_UP_SEC = parseInt(__ENV.RAMP_UP_SEC || "30");
const RAMP_DOWN_SEC = parseInt(__ENV.RAMP_DOWN_SEC || "30");
const TEST_DURATION_SEC = parseInt(__ENV.TEST_DURATION_SEC || "120");
const HOLD_SEC = TEST_DURATION_SEC - RAMP_UP_SEC - RAMP_DOWN_SEC;

// Per-VU per-socket safety net so a stuck connection doesn't block the iteration
// forever. Must comfortably exceed conn-2's nominal lifetime (~30 s).
const SOCKET_TIMEOUT_MS = parseInt(__ENV.SOCKET_TIMEOUT_MS || "60000");

export const options = {
  scenarios: {
    load: {
      executor: "ramping-vus",
      startVUs: 0,
      stages: [
        { duration: `${RAMP_UP_SEC}s`, target: VUS },
        { duration: `${HOLD_SEC}s`, target: VUS },
        { duration: `${RAMP_DOWN_SEC}s`, target: 0 },
      ],
      gracefulRampDown: "15s",
    },
  },
};

// Multiplicative jitter: returns seconds * (1 ± spread).
function jitter(seconds, spread = 0.2) {
  return seconds * (1 + (Math.random() * 2 - 1) * spread);
}

export default function () {
  // Smear iteration starts so VUs don't re-synchronise after the ramp.
  sleep(jitter(0.5, 1));

  const path = `${BASE_PATH}?size_kb=${SIZE_KB}`;
  const baseUrl = `http://${HOST}`;

  const res = http.get(`${baseUrl}${path}`);
  if (!check(res, { "HTTP 200": (r) => r.status === 200 })) {
    fail(`GET ${path} failed: ${res.status}`);
  }

  const { wsCsrfToken, phxSession, phxStatic, phxId } = grabLVProps(res);
  const topic = `lv:${phxId}`;
  const sessionCookie = extractSessionCookie(res);
  const wsUrl = `ws://${HOST}/live/websocket?vsn=2.0.0&_csrf_token=${wsCsrfToken}`;
  const wsHeaders = { Origin: baseUrl, Cookie: sessionCookie };

  let stashId = null;
  let nodeHint = null;
  let stashedState = null;

  // ── Connection 1 ────────────────────────────────────────────────────────
  // connect → wait ~5 s → stash → wait ~15 s → disconnect
  ws.connect(wsUrl, { headers: wsHeaders }, (socket) => {
    let phase = "joining";
    let joinSentAt = 0;
    let stashSentAt = 0;

    socket.on("open", () => {
      joinSentAt = Date.now();
      socket.send(
        phxMsg("1", "1", topic, "phx_join", {
          url: `${baseUrl}${path}`,
          params: { _csrf_token: wsCsrfToken, _mounts: 0 },
          session: phxSession,
          static: phxStatic,
        }),
      );
    });

    socket.on("message", (raw) => {
      const [, ref, , event, payload] = JSON.parse(raw);

      if (
        phase === "joining" &&
        event === "phx_reply" &&
        ref === "1" &&
        payload?.status === "ok"
      ) {
        firstRenderRTT.add(Date.now() - joinSentAt);
        const init = extractStashInit(payload);
        stashId = init.stashId;
        nodeHint = init.node;
        phase = "idle_before_stash";
        socket.setTimeout(
          () => {
            phase = "stashing";
            stashSentAt = Date.now();
            socket.send(
              phxMsg("1", "2", topic, "event", {
                type: "click",
                event: "regenerate",
                value: {},
              }),
            );
          },
          jitter(5) * 1000,
        );
      } else if (
        phase === "stashing" &&
        (event === "diff" || (event === "phx_reply" && ref === "2"))
      ) {
        stashedState = extractStashedState(payload) ?? stashedState;
        stashRTT.add(Date.now() - stashSentAt, { stash_round: "1" });
        phase = "idle_after_stash";
        socket.setTimeout(() => socket.close(), jitter(15) * 1000);
      }
    });

    socket.on("error", (e) => {
      if (e.error() !== "websocket: close sent") {
        console.error(`WS error (conn1): ${e.error()}`);
      }
    });

    socket.setTimeout(() => {
      if (phase !== "idle_after_stash") {
        console.error(`conn1 stuck in phase: ${phase}`);
      }
      socket.close();
    }, SOCKET_TIMEOUT_MS);
  });

  // ── Gap before reconnect ────────────────────────────────────────────────
  // RECONNECT_WITHIN_TTL_PCT % of iterations reconnect while the stash is
  // still recoverable; the rest wait long enough that it has expired.
  const withinTtl = Math.random() * 100 < RECONNECT_WITHIN_TTL_PCT;
  let gapSec = withinTtl
    ? Math.random() * (TTL * 0.8) // 0 .. 80% of TTL
    : TTL + 1 + Math.random() * 2; // TTL+1 .. TTL+3

  // TEMPORARY FOR LOCAL SHORTER TESTS
  gapSec = 10;

  sleep(gapSec);

  // ── Connection 2 ────────────────────────────────────────────────────────
  // reconnect (with stashId) → wait ~15 s → stash again → wait ~15 s → close
  ws.connect(wsUrl, { headers: wsHeaders }, (socket) => {
    let phase = "joining";
    let reconnectSentAt = 0;
    let stashSentAt = 0;

    socket.on("open", () => {
      reconnectSentAt = Date.now();
      const params = { _csrf_token: wsCsrfToken, _mounts: 1 };
      const liveStash = {};
      if (stashId) liveStash.stashId = stashId;
      if (nodeHint) liveStash.node = nodeHint;
      if (stashedState) liveStash.stashedState = stashedState;
      if (Object.keys(liveStash).length > 0) params.liveStash = liveStash;
      socket.send(
        phxMsg("1", "1", topic, "phx_join", {
          url: `${baseUrl}${path}`,
          params,
          session: phxSession,
          static: phxStatic,
        }),
      );
    });

    socket.on("message", (raw) => {
      const [, ref, , event, payload] = JSON.parse(raw);

      if (
        phase === "joining" &&
        event === "phx_reply" &&
        ref === "1" &&
        payload?.status === "ok"
      ) {
        reconnectRTT.add(Date.now() - reconnectSentAt, {
          within_ttl: String(withinTtl),
        });
        phase = "idle_before_stash";
        socket.setTimeout(
          () => {
            phase = "stashing";
            stashSentAt = Date.now();
            socket.send(
              phxMsg("1", "2", topic, "event", {
                type: "click",
                event: "regenerate",
                value: {},
              }),
            );
          },
          jitter(15) * 1000,
        );
      } else if (
        phase === "stashing" &&
        (event === "diff" || (event === "phx_reply" && ref === "2"))
      ) {
        stashRTT.add(Date.now() - stashSentAt, { stash_round: "2" });
        phase = "idle_after_stash";
        socket.setTimeout(() => socket.close(), jitter(15) * 1000);
      }
    });

    socket.on("error", (e) => {
      if (e.error() !== "websocket: close sent") {
        console.error(`WS error (conn2): ${e.error()}`);
      }
    });

    socket.setTimeout(() => {
      if (phase !== "idle_after_stash") {
        console.error(`conn2 stuck in phase: ${phase}`);
      }
      socket.close();
    }, SOCKET_TIMEOUT_MS);
  });
}

function phxMsg(joinRef, ref, topic, event, payload) {
  return JSON.stringify([joinRef, ref, topic, event, payload]);
}

function findPushEvent(payload, name) {
  const events =
    payload?.response?.rendered?.e ||
    payload?.response?.diff?.e ||
    payload?.diff?.e ||
    payload?.e ||
    [];
  return events.find(([eventName]) => eventName === name)?.[1] || null;
}

const INIT_EVENTS = [
  "live-stash:init-ets",
  "live-stash:init-redis",
  "live-stash:init-mnesia",
];

function extractStashInit(payload) {
  for (const name of INIT_EVENTS) {
    const detail = findPushEvent(payload, name);
    if (detail) {
      return { stashId: detail.stashId || null, node: detail.node || null };
    }
  }
  return { stashId: null, node: null };
}

function extractStashedState(payload) {
  return findPushEvent(payload, "live-stash:stash-state")?.assigns || null;
}

function grabLVProps(response) {
  const wsCsrfToken = response
    .html()
    .find("meta[name='csrf-token']")
    .attr("content");

  if (!check(wsCsrfToken, { "csrf-token present": (t) => !!t })) {
    fail("csrf-token not found");
  }

  const main = response.html().find("[data-phx-main]");
  const phxSession = main.data("phx-session");
  const phxStatic = main.data("phx-static");
  const phxId = main.attr("id");

  if (!check(phxSession, { "phx-session present": (s) => !!s })) {
    fail("phx-session not found — is the LiveView rendering?");
  }

  return { wsCsrfToken, phxSession, phxStatic, phxId };
}

function extractSessionCookie(res) {
  const cookies = res.cookies;
  const key = Object.keys(cookies).find(
    (k) => k.startsWith("_") && k.endsWith("_key"),
  );
  if (!key) return "";
  return `${key}=${cookies[key][0].value}`;
}
