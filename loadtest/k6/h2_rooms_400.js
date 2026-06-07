import http from "k6/http";
import { WebSocket } from "k6/websockets";
import { check, sleep } from "k6";
import { Trend, Rate } from "k6/metrics";

const apiBase = __ENV.API_BASE || "";
const wsBase = __ENV.WS_BASE || "";
const allowLocal = __ENV.ALLOW_LOCALHOST === "1";

function assertProductionTargets() {
  if (!apiBase || !wsBase) {
    throw new Error(
      "H2 requires API_BASE and WS_BASE (Render production URLs). Example: API_BASE=https://your-app.onrender.com/api WS_BASE=wss://your-app.onrender.com/socket/websocket"
    );
  }
  const local = /127\.0\.0\.1|localhost/i.test(apiBase) || /127\.0\.0\.1|localhost/i.test(wsBase);
  if (local && !allowLocal) {
    throw new Error(
      "H2 thesis runs must target deployed backend, not localhost. Set ALLOW_LOCALHOST=1 only for dev smoke tests."
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
        { duration: "2m", target: 50  },
        { duration: "5m", target: 50  },
        { duration: "2m", target: 100 },
        { duration: "5m", target: 100 },
        { duration: "2m", target: 200 },
        { duration: "5m", target: 200 },
        { duration: "3m", target: 400 },
        { duration: "5m", target: 400 },
        { duration: "2m", target: 0   },
      ],
      gracefulStop: "75s",
    },
  },
  thresholds: {
    h2_errors: ["rate<0.01"],
    s2c_question_revealed_latency_ms: ["p(95)<=300"],
  },
};

function randInt(min, max) {
  return Math.floor(Math.random() * (max - min + 1)) + min;
}

function createRoom() {
  const res = http.post(`${apiBase}/rooms`, JSON.stringify({}), {
    headers: { "Content-Type": "application/json" },
  });
  check(res, { "create room 201": (r) => r.status === 201 });
  if (res.status !== 201) return null;
  return res.json()?.room?.code || null;
}

function joinRoom(roomCode, nickname) {
  // Use http.url template tag to group dynamic roomCode metrics and prevent memory leaks/high-cardinality bloat
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

export default function () {
  const roomCode = createRoom();
  if (!roomCode) {
    errorRate.add(true);
    sleep(5); // Prevent tight failure loop
    return;
  }

  const nPlayers = randInt(minPlayers, maxPlayers);
  const players = [];
  for (let i = 0; i < nPlayers; i++) {
    const p = joinRoom(roomCode, `k6_${__VU}_${i}`);
    if (!p || !p.id) {
      errorRate.add(true);
      sleep(5); // Prevent tight failure loop
      return;
    }
    players.push(p);
  }

  let gotQuestion = false;
  let questionLatencyDone = false;

  const sockets = [];
  const topic = `game:${roomCode}`;

  for (let i = 0; i < nPlayers; i++) {
    const p = players[i];
    const isHost = p.is_host === true;
    const myJoinRef = String(i + 1);
    const nickname = `k6_${__VU}_${i}`;

    const socket = new WebSocket(`${wsBase}?vsn=2.0.0`);
    sockets.push(socket);

    socket.onopen = () => {
      try {
        socket.send(JSON.stringify([
          myJoinRef, myJoinRef, topic, "phx_join",
          { nickname: nickname, player_id: p.id }
        ]));
      } catch (err) {
        console.log(`Error sending phx_join: ${err}`);
      }

      // Send heartbeats every 30 seconds to keep the Phoenix channel connection alive
      socket.heartbeatInterval = setInterval(() => {
        try {
          if (socket.readyState === 1) {
            socket.send(JSON.stringify([
              null, "heartbeat_ref", "phoenix", "heartbeat", {}
            ]));
          }
        } catch (err) {
          // ignore
        }
      }, 30000);

      if (isHost) {
        setTimeout(() => {
          try {
            if (socket.readyState === 1) {
              socket.send(JSON.stringify([
                "1", "99", topic, "start_game",
                { client_timestamp_ms: Date.now() }
              ]));
            }
          } catch (err) {
            console.log(`Error sending start_game: ${err}`);
          }
        }, 2000);
      }
    };

    socket.onmessage = (e) => {
      let msg;
      try { msg = JSON.parse(e.data); } catch { return; }
      const [, , , event, payload] = msg;

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
    };

    socket.onerror = () => {
      if (socket.heartbeatInterval) {
        clearInterval(socket.heartbeatInterval);
      }
    };

    socket.onclose = () => {
      if (socket.heartbeatInterval) {
        clearInterval(socket.heartbeatInterval);
      }
    };
  }

  // Wait asynchronously for game-start and question-revealed events, then cleanup
  setTimeout(() => {
    for (const s of sockets) {
      try {
        if (s.heartbeatInterval) {
          clearInterval(s.heartbeatInterval);
        }
        s.close();
      } catch (err) {
        // ignore
      }
    }
    errorRate.add(gotQuestion ? 0 : 1);
  }, sessionDurationMs);
}
