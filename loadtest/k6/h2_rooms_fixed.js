import http from "k6/http";
import { WebSocket } from "k6/websockets";
import { check } from "k6";
import { Trend, Rate } from "k6/metrics";

const apiBase = __ENV.API_BASE || "";
const wsBase  = __ENV.WS_BASE  || "";
const allowLocal = __ENV.ALLOW_LOCALHOST === "1";

function assertProductionTargets() {
  if (!apiBase || !wsBase) throw new Error("API_BASE and WS_BASE are required.");
  const local = /127\.0\.0\.1|localhost/i.test(apiBase + wsBase);
  if (local && !allowLocal) throw new Error("Set ALLOW_LOCALHOST=1 for dev only.");
}
assertProductionTargets();

const minPlayers = Number(__ENV.MIN_PLAYERS || "4");
const maxPlayers = Number(__ENV.MAX_PLAYERS || "8");

export const latencyMs = new Trend("s2c_question_revealed_latency_ms", true);
export const errorRate  = new Rate("h2_errors");

// NOTE: stages are overridden by --stage flag in h2_test_all.sh
// This default is for manual runs
export const options = {
  scenarios: {
    default: {
      executor: "ramping-vus",
      stages: [
        { duration: "2m", target: 50  },
        { duration: "5m", target: 50  },
        { duration: "2m", target: 100 },
        { duration: "5m", target: 100 },
        { duration: "2m", target: 150 },
        { duration: "5m", target: 150 },
        { duration: "1m", target: 0   },
      ],
      gracefulStop: "0s",
    },
  },
  thresholds: {
    h2_errors:                        ["rate<0.01"],
    s2c_question_revealed_latency_ms: ["p(95)<=300"],
  },
};

function randInt(min, max) {
  return Math.floor(Math.random() * (max - min + 1)) + min;
}

function createRoom() {
  const res = http.post(`${apiBase}/rooms`, JSON.stringify({}), {
    headers: { "Content-Type": "application/json" },
    timeout: "10s",
  });
  check(res, { "create room 201": (r) => r.status === 201 });
  if (res.status !== 201) return null;
  return res.json()?.room?.code || null;
}

function joinRoom(roomCode, nickname) {
  const res = http.post(
    http.url`${apiBase}/rooms/${roomCode}/join`,
    JSON.stringify({ nickname }),
    { headers: { "Content-Type": "application/json" }, timeout: "10s" }
  );
  check(res, { "join room 201": (r) => r.status === 201 });
  if (res.status !== 201) return null;
  const json = res.json();
  return { id: json?.player?.id, is_host: json?.player?.is_host };
}

export default function () {
  const roomCode = createRoom();
  if (!roomCode) { errorRate.add(true); return; }

  const nPlayers = randInt(minPlayers, maxPlayers);
  const players  = [];
  for (let i = 0; i < nPlayers; i++) {
    const p = joinRoom(roomCode, `k6_${__VU}_${i}`);
    if (!p || !p.id) { errorRate.add(true); return; }
    players.push(p);
  }

  let gotQuestion       = false;
  let questionLatencyDone = false;
  const sockets = [];
  const topic   = `game:${roomCode}`;

  for (let i = 0; i < nPlayers; i++) {
    const p      = players[i];
    const isHost = p.is_host === true;
    const ref    = String(i + 1);

    const socket = new WebSocket(`${wsBase}?vsn=2.0.0`);
    sockets.push(socket);

    socket.onopen = () => {
      try {
        socket.send(JSON.stringify([ref, ref, topic, "phx_join",
          { nickname: `k6_${__VU}_${i}`, player_id: p.id }]));
      } catch (_) {}

      if (isHost) {
        // Start game after 2s — gives all parallel sockets time to join
        setTimeout(() => {
          try {
            if (socket.readyState === 1)
              socket.send(JSON.stringify(["1","99",topic,"start_game",
                { client_timestamp_ms: Date.now() }]));
          } catch (_) {}
        }, 2000);
      }
    };

    socket.onmessage = (e) => {
      let msg;
      try { msg = JSON.parse(e.data); } catch { return; }
      const [,,,event,payload] = msg;
      if (event === "question_revealed" && !questionLatencyDone) {
        gotQuestion       = true;
        questionLatencyDone = true;
        if (payload?.server_timestamp_ms) {
          const lat = Date.now() - payload.server_timestamp_ms;
          if (lat >= 0 && lat <= 10000) latencyMs.add(lat);
        }
      }
    };

    socket.onerror = () => {};
    socket.onclose = () => {};
  }

  // Close after 13s — matches actual server game-start time under load
  // No heartbeat intervals — keeps connection count low
  setTimeout(() => {
    for (const s of sockets) { try { s.close(); } catch (_) {} }
    errorRate.add(gotQuestion ? 0 : 1);
  }, 13000);
}
