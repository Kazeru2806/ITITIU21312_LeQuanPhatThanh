import http from "k6/http";
import ws from "k6/ws";
import { check, sleep } from "k6";
import { Trend, Rate } from "k6/metrics";

const apiBase = __ENV.API_BASE || "";
const wsBase = __ENV.WS_BASE || "";
const allowLocal = __ENV.ALLOW_LOCALHOST === "1";

function assertProductionTargets() {
  if (!apiBase || !wsBase) {
    throw new Error(
      "H2 requires API_BASE and WS_BASE. " +
      "Example: API_BASE=https://your-app.onrender.com/api " +
      "WS_BASE=wss://your-app.onrender.com/socket/websocket"
    );
  }
  const local =
    /127\.0\.0\.1|localhost/i.test(apiBase) ||
    /127\.0\.0\.1|localhost/i.test(wsBase);
  if (local && !allowLocal) {
    throw new Error(
      "H2 thesis runs must target deployed backend. " +
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
        { duration: "2m", target: 100 },  // warm-up
        { duration: "3m", target: 100 },  // hold — confirm baseline still passes
        { duration: "3m", target: 200 },  // ramp
        { duration: "5m", target: 200 },  // hold
        { duration: "3m", target: 350 },  // ramp
        { duration: "5m", target: 350 },  // hold
        { duration: "3m", target: 500 },  // ramp to thesis target
        { duration: "10m", target: 500 },  // hold — main measurement window
        { duration: "3m", target: 0 },  // ramp down
      ],
      gracefulRampDown: "90s",
      gracefulStop: "90s",
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
//
// Design note (for thesis documentation):
//
// Each VU represents one complete game room. All N players (4–8) join the
// room via HTTP, so the server maintains full room state in ETS for all
// players. WebSocket game-flow latency is measured from the HOST player's
// perspective only. This avoids a k6/ws limitation where nested ws.connect()
// calls block sequentially (causing zero iterations to complete in a
// multi-socket design). Since the server broadcasts question_revealed to
// all connected sockets simultaneously, the host socket latency is
// representative of the per-player S2C delivery time.
//
// ---------------------------------------------------------------------------

export default function () {
  // ── 1. Create room ──────────────────────────────────────────────────────
  const roomCode = createRoom();
  if (!roomCode) {
    errorRate.add(true);
    sleep(5);
    return;
  }

  // ── 2. All N players join via HTTP ──────────────────────────────────────
  // The room is fully populated in ETS with N players; game state is correct.
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

  // ── 3. Host opens one WebSocket; drives the game lifecycle ──────────────
  const topic = `game:${roomCode}`;
  const host = players[0];

  let gotQuestion = false;
  let questionLatencyDone = false;

  // ws.connect() blocks until socket.close() is called, giving us a clean
  // 60-second session window with a functioning event loop.
  ws.connect(`${wsBase}?vsn=2.0.0`, {}, function (socket) {

    socket.on("open", () => {
      // Join the Phoenix channel as host
      socket.send(JSON.stringify([
        "1", "1", topic, "phx_join",
        { nickname: `k6_${__VU}_0`, player_id: host.id },
      ]));

      // Heartbeat to keep the Phoenix channel alive
      socket.setInterval(() => {
        socket.send(JSON.stringify([
          null, "heartbeat_ref", "phoenix", "heartbeat", {},
        ]));
      }, 30000);

      // Start the game after 2 s (allows server-side join processing to settle)
      socket.setTimeout(() => {
        socket.send(JSON.stringify([
          "1", "99", topic, "start_game",
          { client_timestamp_ms: Date.now() },
        ]));
      }, 2000);

      // End session cleanly after sessionDurationMs
      socket.setTimeout(() => {
        socket.close();
      }, sessionDurationMs);
    });

    socket.on("message", (raw) => {
      let msg;
      try { msg = JSON.parse(raw); } catch { return; }
      const [, , , event, payload] = msg;

      // Capture S2C latency on the first question_revealed broadcast
      if (event === "question_revealed" && !questionLatencyDone) {
        gotQuestion = true;
        questionLatencyDone = true;
        if (payload?.server_timestamp_ms) {
          const lat = Date.now() - payload.server_timestamp_ms;
          if (lat >= 0 && lat <= 10000) {
            latencyMs.add(lat);
          }
        }
      }
    });

    socket.on("error", () => { /* swallow; error rate tracked via gotQuestion */ });
  });

  // ── 4. Record pass/fail AFTER ws.connect() returns (socket closed) ──────
  // gotQuestion is true only if question_revealed arrived before session end.
  errorRate.add(gotQuestion ? 0 : 1);
}