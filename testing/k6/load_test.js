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

// Adapter TTL, must match LiveView config
const TTL = parseFloat(__ENV.TTL || "15");

// Probability (0-100) that the gap between disconnect and reconnect is shorter
// than TTL (the stash is still recoverable).
const RECONNECT_WITHIN_TTL_PCT = parseFloat(
  __ENV.RECONNECT_WITHIN_TTL_PCT || "40",
);

// Test profile: ramp up + hold + ramp down.
const RAMP_UP_SEC = parseInt(__ENV.RAMP_UP_SEC || "30");
const RAMP_DOWN_SEC = parseInt(__ENV.RAMP_DOWN_SEC || "30");
const TEST_DURATION_SEC = parseInt(__ENV.TEST_DURATION_SEC || "120");
const HOLD_SEC = TEST_DURATION_SEC - RAMP_UP_SEC - RAMP_DOWN_SEC;

const FIRST_WAIT_SEC = parseInt(__ENV.FIRST_WAIT_SEC || "5");
const SECOND_WAIT_SEC = parseInt(__ENV.SECOND_WAIT_SEC || "5");

const MAX_WAIT_SEC = Math.max(FIRST_WAIT_SEC, SECOND_WAIT_SEC);
const DYNAMIC_TIMEOUT_MS = Math.ceil(MAX_WAIT_SEC * 2 * 1.2 + 10) * 1000;

const SOCKET_TIMEOUT_MS = parseInt(
  __ENV.SOCKET_TIMEOUT_MS || String(DYNAMIC_TIMEOUT_MS),
);

export const options = {
  // Reconnect WS URLs embed unique csrf/stash/state params per VU; drop `url`
  // so built-in metrics group on our explicit `name` tags instead.
  systemTags: [
    "check",
    "error",
    "error_code",
    "expected_response",
    "group",
    "method",
    "name",
    "proto",
    "scenario",
    "status",
    "subproto",
    "tls_version",
  ],
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
  // desynchronize iteration starts so VUs don't re-synchronise after the ramp.
  sleep(jitter(0.5, 1));

  const path = `${BASE_PATH}?size_kb=${SIZE_KB}`;
  const baseUrl = `http://${HOST}`;

  const res = http.get(`${baseUrl}${path}`, {
    tags: { name: "liveview_page" },
  });
  if (!check(res, { "HTTP 200": (r) => r.status === 200 })) {
    fail(`GET ${path} failed: ${res.status}`);
  }

  const { wsCsrfToken, phxSession, phxStatic, phxId } = grabLVProps(res);
  const topic = `lv:${phxId}`;
  const sessionCookie = extractSessionCookie(res);
  const wsUrl = `ws://${HOST}/live/websocket?vsn=2.0.0&_csrf_token=${wsCsrfToken}`;
  const wsHeaders = { Origin: baseUrl, Cookie: sessionCookie };
  const wsTags = (name) => ({ headers: wsHeaders, tags: { name } });

  let stashId = null;
  let nodeHint = null;
  let stashedState = null;

  // ── Connection 1 ────────────────────────────────────────────────────────
  // connect → wait → stash → wait → disconnect
  ws.connect(wsUrl, wsTags("ws_join"), (socket) => {
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
          jitter(FIRST_WAIT_SEC) * 1000,
        );
      } else if (
        phase === "stashing" &&
        (event === "diff" || (event === "phx_reply" && ref === "2"))
      ) {
        stashedState = extractStashedState(payload) ?? stashedState;
        stashRTT.add(Date.now() - stashSentAt, { stash_round: "1" });
        phase = "idle_after_stash";
        socket.setTimeout(() => socket.close(), jitter(FIRST_WAIT_SEC) * 1000);
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
  // watch out for first wait time, as it impacts length of necessary gap
  // RECONNECT_WITHIN_TTL_PCT % of iterations reconnect while the stash is
  // still recoverable; the rest wait long enough that it has expired.
  const withinTtl = Math.random() * 100 < RECONNECT_WITHIN_TTL_PCT;
  let gapSec = withinTtl
    ? Math.random() * (TTL * 0.5) // 0 .. 50% of TTL
    : TTL + 1 + Math.random() * 2; // TTL+1 .. TTL+3

  // works only for browser memory adapter
  // gapSec = Math.max(gapSec - FIRST_WAIT_SEC, 1);
  // // TEMPORARY FOR LOCAL SHORTER TESTS
  // gapSec = 5;

  sleep(gapSec);

  // ── Connection 2 ────────────────────────────────────────────────────────
  // reconnect → wait → stash again → wait → close
  const params = { _csrf_token: wsCsrfToken, _mounts: 1 };
  const liveStash = {};
  if (stashId) liveStash.stashId = stashId;
  if (nodeHint) liveStash.node = nodeHint;
  if (stashedState) liveStash.stashedState = stashedState;
  if (Object.keys(liveStash).length > 0) params.liveStash = liveStash;

  const queryString = serializeParams(params);
  const reconnectWsUrl = `ws://${HOST}/live/websocket?vsn=2.0.0&${queryString}`;

  ws.connect(reconnectWsUrl, wsTags("ws_reconnect"), (socket) => {
    let phase = "joining";
    let reconnectSentAt = 0;
    let stashSentAt = 0;

    socket.on("open", () => {
      reconnectSentAt = Date.now();

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
          jitter(SECOND_WAIT_SEC) * 1000,
        );
      } else if (
        phase === "stashing" &&
        (event === "diff" || (event === "phx_reply" && ref === "2"))
      ) {
        stashRTT.add(Date.now() - stashSentAt, { stash_round: "2" });
        phase = "idle_after_stash";
        socket.setTimeout(() => socket.close(), jitter(SECOND_WAIT_SEC) * 1000);
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

function serializeParams(obj, prefix) {
  const str = [];
  for (let p in obj) {
    if (obj.hasOwnProperty(p)) {
      let k = prefix ? prefix + "[" + p + "]" : p,
        v = obj[p];
      str.push(
        v !== null && typeof v === "object"
          ? serializeParams(v, k)
          : encodeURIComponent(k) + "=" + encodeURIComponent(v),
      );
    }
  }
  return str.join("&");
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
