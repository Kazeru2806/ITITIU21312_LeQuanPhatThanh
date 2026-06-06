import http from "k6/http";
import { WebSocket } from "k6/websockets";
import { check, sleep } from "k6";
import { Trend, Rate } from "k6/metrics";

const apiBase = __ENV.API_BASE || "";
const wsBase = __ENV.WS_BASE || "";

if (!apiBase || !wsBase) {
  throw new Error("API_BASE and WS_BASE are required.");
}

const minPlayers = Number(__ENV.MIN_PLAYERS || "4");
const maxPlayers = Number(__ENV.MAX_PLAYERS || "8");

export const latencyMs = new Trend("s2c_question_revealed_latency_ms", true);
export const errorRate = new Rate("h2_errors");

export const options = {
  stages: [
    { duration: "2m", target: 50  },
    { duration: "5m", target: 50  },
    { duration: "2m", target: 100 },
    { duration: "5m", target: 100 },
    { duration: "2m", target: 150 },
    { duration: "5m", target: 150 },
    { duration: "2m", target: 0   },
  ],
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
  const res = http.post(
    `${apiBase}/rooms/${roomCode}/join`,
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
  if (!roomCode) return;

  const nPlayers = randInt(minPlayers, maxPlayers);
  const players = [];
  for (let i = 0; i < nPlayers; i++) {
    const p = joinRoom(roomCode, `k6_${__VU}_${i}`);
    if (!p || !p.id) return;
    players.push(p);
  }

  let gotQuestion = false;
  let questionLatencyDone = false;

  const sockets = [];
  let hostSocket = null;
  const topic = `game:${roomCode}`;

  for (let i = 0; i < nPlayers; i++) {
    const p = players[i];
    const isHost = p.is_host === true;
    const myJoinRef = String(i + 1);
    const nickname = `k6_${__VU}_${i}`;

    const socket = new WebSocket(`${wsBase}?vsn=2.0.0`);
    sockets.push(socket);
    if (isHost) {
      hostSocket = socket;
    }

    socket.onopen = () => {
      socket.send(JSON.stringify([
        myJoinRef, myJoinRef, topic, "phx_join",
        { nickname: nickname, player_id: p.id }
      ]));
    };

    socket.onmessage = (e) => {
      let msg;
      try { msg = JSON.parse(e.data); } catch { return; }
      const [, , , event, payload] = msg;

      if (event === "phx_reply" && payload?.status === "error" && isHost) {
        return;
      }

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

    socket.onerror = () => {};
  }

  // 1. Sleep to let all players connect and join
  sleep(2);

  // 2. Host sends start_game
  if (hostSocket) {
    hostSocket.send(JSON.stringify([
      "1", "99", topic, "start_game",
      { client_timestamp_ms: Date.now() }
    ]));
  }

  // 3. Sleep to let the game start and question get revealed
  sleep(6);

  // 4. Close all sockets
  for (const s of sockets) {
    try {
      s.close();
    } catch (err) {
      // ignore
    }
  }

  errorRate.add(gotQuestion ? 0 : 1);
}
