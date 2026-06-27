import http from "k6/http";
import ws from "k6/ws";           // ← synchronous API; drives its own event loop
import { check, sleep } from "k6";
import { Trend, Rate } from "k6/metrics";

const apiBase = __ENV.API_BASE || "";
const wsBase = __ENV.WS_BASE || "";
const allowLocal = __ENV.ALLOW_LOCALHOST === "1";

function assertProductionTargets() {
  if (!apiBase || !wsBase) {
    throw new Error(
      "H2 requires API_BASE and WS_BASE (Render production URLs). " +
      "Example: API_BASE=https://your-app.onrender.com/api " +
      "WS_BASE=wss://your-app.onrender.com/socket/websocket"
    );
  }
  const local =
    /127\.0\.0\.1|localhost/i.test(apiBase) ||
    /127\.0\.0\.1|localhost/i.test(wsBase);
  if (local && !allowLocal) {
    throw new Error(
      "H2 thesis runs must target deployed backend, not localhost. " +
      "Set ALLOW_LOCALHOST=1 only for dev smoke tests."
    );
  }
}

assertProductionTargets();

const minPlayers = Number(__ENV.MIN_PLAYERS || "4");
const maxPlayers = Number(__ENV.MAX_PLAYERS || "8");
const sessionDurationMs = Number(__ENV.SESSION_DURATION_MS || "60000");

export const latencyMs = new Trend("s2c_question_revealed_latency_ms", true);
export const errorRate = new Rate("h2_errors");

export const options = {
  scenarios: {
    default: {
      executor: "ramping-vus",
      stages: [
        { duration: "2m", target: 50 },
        { duration: "5m", target: 50 },
        { duration: "2m", target: 100 },
        { duration: "5m", target: 100 },
        { duration: "2m", target: 150 },
        { duration: "5m", target: 150 },
        { duration: "2m", target: 0 },
      ],
      gracefulRampDown: "75s",
      gracefulStop: "75s",
    },
  },
  thresholds: {
    h2_errors: ["rate<0.01"],
    s2c_question_revealed_latency_ms: ["p(95)<=300"],
  },
};

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function randInt(min, max) {
  return Math.floor(Math.random() * (max - min + 1)) + min;
}

function createRoom() {
  const res = http.post(
    `${apiBase}/rooms`,
    JSON.stringify({}),
    { headers: { "Content-Type": "application/json" } }
  );
  check(res, { "create room 201": (r) => r.status === 201 });
  if (res.status !== 201) return null;
  return res.json()?.room?.code || null;
}

function joinRoom(roomCode, nickname) {
  const res = http.post(
    http.url`${apiBase}/rooms/${roomCode}/join`,
    JSON.stringify({ nickname }),
    { headers: { "Content-Type": "application/json" } }
  );
  check(res, { "join room 201": (r) => r.status === 201 });
  if (res.status !== 201) return null;
  const json = res.json();
  return { id: json?.player?.id, is_host: json?.player?.is_host };
}

// ---------------------------------------------------------------------------
// Default VU function
// ---------------------------------------------------------------------------

export default function () {
  // ── 1. Create room ──────────────────────────────────────────────────────
  const roomCode = createRoom();
  if (!roomCode) {
    errorRate.add(true);
    sleep(5);
    return;
  }

  // ── 2. Join all players via HTTP ────────────────────────────────────────
  const nPlayers = randInt(minPlayers, maxPlayers);
  const players = [];
  for (let i = 0; i < nPlayers; i++) {
    const p = joinRoom(roomCode, `k6_${__VU}_${i}`);
    if (!p || !p.id) {
      errorRate.add(true);
      sleep(5);
      return;
    }
    players.push(p);
  }

  // ── 3. Open WebSockets (k6/ws synchronous API) ──────────────────────────
  //
  // k6/ws.connect() blocks until socket.close() is called or the
  // callback returns.  We open the HOST socket first, which drives the
  // game lifecycle via socket.setTimeout().  Guest sockets are opened
  // inside the host callback so everything runs on the same VU coroutine.
  //
  // Why NOT k6/websockets (async)?
  //   k6/websockets' setTimeout/setInterval run in a micro-task queue that
  //   k6 does not pump correctly inside default().  As a result the session
  //   collapses to ~22 s, gotQuestion is always false, and every iteration
  //   records an error.  The synchronous k6/ws API is the correct choice for
  //   this scenario-style test.

  const topic = `game:${roomCode}`;

  // State shared across all socket callbacks for this iteration
  let gotQuestion = false;
  let questionLatencyDone = false;
  let hostSocket = null;
  const guestSockets = [];

  // Helper: open one guest WebSocket (non-blocking inside host callback)
  function openGuest(p, i) {
    const nickname = `k6_${__VU}_${i}`;
    const myJoinRef = String(i + 1);

    ws.connect(`${wsBase}?vsn=2.0.0`, {}, function (socket) {
      socket.on("open", () => {
        socket.send(JSON.stringify([
          myJoinRef, myJoinRef, topic, "phx_join",
          { nickname, player_id: p.id },
        ]));

        // Heartbeat every 30 s
        socket.setInterval(() => {
          socket.send(JSON.stringify([
            null, "heartbeat_ref", "phoenix", "heartbeat", {},
          ]));
        }, 30000);
      });

      socket.on("message", (raw) => {
        let msg;
        try { msg = JSON.parse(raw); } catch { return; }
        const [, , , event, payload] = msg;

        if (event === "question_revealed" && !questionLatencyDone) {
          gotQuestion = true;
          questionLatencyDone = true;
          if (payload?.server_timestamp_ms) {
            const lat = Date.now() - payload.server_timestamp_ms;
            if (lat >= 0 && lat <= 10000) latencyMs.add(lat);
          }
        }
      });

      socket.on("error", () => { /* swallow */ });

      // Guest stays connected for the full session duration; host closes it
      guestSockets.push(socket);
    });
  }

  // Open host socket — this call BLOCKS for sessionDurationMs
  ws.connect(`${wsBase}?vsn=2.0.0`, {}, function (socket) {
    hostSocket = socket;

    socket.on("open", () => {
      // Host joins channel
      socket.send(JSON.stringify([
        "1", "1", topic, "phx_join",
        { nickname: `k6_${__VU}_0`, player_id: players[0].id },
      ]));

      // Heartbeat
      socket.setInterval(() => {
        socket.send(JSON.stringify([
          null, "heartbeat_ref", "phoenix", "heartbeat", {},
        ]));
      }, 30000);

      // Open guest sockets (players[1..n-1])
      for (let i = 1; i < nPlayers; i++) {
        openGuest(players[i], i);
      }

      // Start game after 2 s
      socket.setTimeout(() => {
        socket.send(JSON.stringify([
          "1", "99", topic, "start_game",
          { client_timestamp_ms: Date.now() },
        ]));
      }, 2000);

      // End session after sessionDurationMs
      socket.setTimeout(() => {
        // Close all guest sockets first
        for (const gs of guestSockets) {
          try { gs.close(); } catch { /* ignore */ }
        }
        socket.close();
      }, sessionDurationMs);
    });

    socket.on("message", (raw) => {
      let msg;
      try { msg = JSON.parse(raw); } catch { return; }
      const [, , , event, payload] = msg;

      if (event === "question_revealed" && !questionLatencyDone) {
        gotQuestion = true;
        questionLatencyDone = true;
        if (payload?.server_timestamp_ms) {
          const lat = Date.now() - payload.server_timestamp_ms;
          if (lat >= 0 && lat <= 10000) latencyMs.add(lat);
        }
      }
    });

    socket.on("error", () => { /* swallow */ });
  });

  // ── 4. Record outcome AFTER sockets have closed ─────────────────────────
  errorRate.add(gotQuestion ? 0 : 1);
}