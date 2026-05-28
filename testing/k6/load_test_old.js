import http from "k6/http";
import ws from "k6/ws";
import { check, fail } from "k6";
import { Trend } from "k6/metrics";

const firstRenderRTT = new Trend("first_render_rtt_ms", true);
const stashRTT = new Trend("stash_rtt_ms", true);
const reconnectRTT = new Trend("reconnect_rtt_ms", true);

const HOST = __ENV.HOST || "localhost:4000";
const SIZE_KB = __ENV.SIZE_KB || "100";
const BASE_PATH = __ENV.BASE_PATH || "/performance/livestash_ets";
const VUS = parseInt(__ENV.VUS || "50");
const ITERATIONS = parseInt(__ENV.ITERATIONS || "5000");

export const options = {
  scenarios: {
    load: {
      executor: "shared-iterations",
      vus: VUS,
      iterations: ITERATIONS,
      maxDuration: "10m",
    },
  },
};

export default function () {
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

  // Connection 1: fresh mount + stash
  let stashId = null;
  let state = "joining";
  let joinSentAt = 0;
  let eventSentAt = 0;

  ws.connect(wsUrl, { headers: wsHeaders }, (socket) => {
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
        state === "joining" &&
        event === "phx_reply" &&
        ref === "1" &&
        payload?.status === "ok"
      ) {
        firstRenderRTT.add(Date.now() - joinSentAt);
        stashId = extractStashId(payload);
        state = "waiting_diff";
        eventSentAt = Date.now();
        socket.send(
          phxMsg("1", "2", topic, "event", {
            type: "click",
            event: "regenerate",
            value: {},
          }),
        );
      } else if (
        state === "waiting_diff" &&
        (event === "diff" || (event === "phx_reply" && ref === "2"))
      ) {
        stashRTT.add(Date.now() - eventSentAt);
        socket.close();
      }
    });

    socket.on("error", (e) => {
      if (e.error() !== "websocket: close sent") {
        console.error(`WS error (connect): ${e.error()}`);
      }
    });

    socket.setTimeout(() => {
      console.error(`timeout in state: ${state}`);
      socket.close();
    }, 10_000);
  });

  // Connection 2: reconnect + recover
  let reconnectSentAt = 0;

  ws.connect(wsUrl, { headers: wsHeaders }, (socket) => {
    socket.on("open", () => {
      reconnectSentAt = Date.now();
      const params = { _csrf_token: wsCsrfToken, _mounts: 1 };
      if (stashId) params.liveStash = { stashId };
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

      if (event === "phx_reply" && ref === "1" && payload?.status === "ok") {
        reconnectRTT.add(Date.now() - reconnectSentAt);
        socket.close();
      }
    });

    socket.on("error", (e) => {
      if (e.error() !== "websocket: close sent") {
        console.error(`WS error (reconnect): ${e.error()}`);
      }
    });

    socket.setTimeout(() => {
      console.error("reconnect timeout");
      socket.close();
    }, 10_000);
  });
}

function phxMsg(joinRef, ref, topic, event, payload) {
  return JSON.stringify([joinRef, ref, topic, event, payload]);
}

function extractStashId(payload) {
  const events = payload?.response?.rendered?.e || [];
  const initEvent = events.find(([name]) => name === "live-stash:init-ets");
  return initEvent?.[1]?.stashId || null;
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
