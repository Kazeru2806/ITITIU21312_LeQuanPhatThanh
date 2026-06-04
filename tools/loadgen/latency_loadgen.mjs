import { Socket } from "phoenix";

function sleep(ms) {
  return new Promise((r) => setTimeout(r, ms));
}

function randNick(i) {
  return `lg_${i}_${Math.random().toString(16).slice(2, 6)}`;
}

async function joinRoom(apiBase, roomCode, nickname) {
  const res = await fetch(`${apiBase}/rooms/${roomCode}/join`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ nickname }),
  });
  if (!res.ok) throw new Error(`join failed: ${res.status}`);
  const json = await res.json();
  return json.player.id;
}

async function createRoom(apiBase, mode) {
  const res = await fetch(`${apiBase}/rooms`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ mode }),
  });
  if (!res.ok) throw new Error(`create failed: ${res.status}`);
  const json = await res.json();
  return json.room.code;
}

async function run() {
  const argv = process.argv.slice(2);
  const getArg = (k, def) => {
    const idx = argv.indexOf(k);
    if (idx === -1) return def;
    return argv[idx + 1] ?? def;
  };

  const host = getArg("--host", "127.0.0.1");
  const apiBase = getArg("--api", `http://${host}:4000/api`).replace(/\/+$/, "");
  const wsUrl = getArg("--ws", `ws://${host}:4000/socket`).replace(/\/websocket$/, "");

  const players = Number(getArg("--players", "8"));
  const messagesPerPlayer = Number(getArg("--messages", "100"));
  const roomCodeArg = getArg("--room", "");
  /** @type {"truth_collapse"|"classic"} */
  const gameMode = getArg("--mode", "truth_collapse");
  const intervalMs = Number(getArg("--interval-ms", "500"));
  const pattern = getArg("--pattern", "parallel");
  const joinTimeoutMs = Number(getArg("--join-timeout-ms", "120000"));
  const socketTimeoutMs = Number(getArg("--socket-timeout-ms", "120000"));

  const roomCode = roomCodeArg
    ? roomCodeArg.toUpperCase()
    : await createRoom(apiBase, gameMode);
  console.log(
    `room=${roomCode} mode=${gameMode} interval_ms=${intervalMs} pattern=${pattern}`
  );

  // Join N players via HTTP so we have player_id.
  const playerIds = [];
  for (let i = 0; i < players; i++) {
    const pid = await joinRoom(apiBase, roomCode, randNick(i + 1));
    playerIds.push(pid);
  }

  // Connect sockets + join channels.
  const channels = [];
  for (let i = 0; i < players; i++) {
    const socket = new Socket(wsUrl, {
      params: {},
      timeout: socketTimeoutMs,
    });
    socket.connect();
    const channel = socket.channel(`game:${roomCode}`, {
      nickname: `lg_${i + 1}`,
      player_id: playerIds[i],
    });

    await new Promise((resolve, reject) => {
      channel
        .join(joinTimeoutMs)
        .receive("ok", resolve)
        .receive("error", reject)
        .receive("timeout", () =>
          reject(new Error(`join timeout (${joinTimeoutMs}ms)`))
        );
    });
    channels.push({ socket, channel, playerId: playerIds[i] });
  }

  // Start game as host (first joined player is host).
  await new Promise((resolve, reject) => {
    channels[0].channel
      .push("start_game", { client_timestamp_ms: Date.now() })
      .receive("ok", resolve)
      .receive("error", reject);
  });
  console.log("started game");

  // We measure “submit_prediction” (truth_collapse) — records latency_measurements.
  // Default interval_ms=500 matches the thesis load (reduces TCP pile-up vs 10–20ms bursts).
  const opts = ["A", "B", "C", "D"];
  const start = Date.now();

  const sendOne = (channel, n) => {
    const option_id = opts[(n + Math.floor(Math.random() * 4)) % 4];
    channel.push("submit_prediction", {
      option_id,
      client_timestamp_ms: Date.now(),
    });
  };

  if (pattern === "round-robin") {
    for (let n = 0; n < messagesPerPlayer; n++) {
      for (const { channel } of channels) {
        sendOne(channel, n);
        await sleep(intervalMs);
      }
    }
  } else {
    await Promise.all(
      channels.map(async ({ channel }) => {
        for (let n = 0; n < messagesPerPlayer; n++) {
          sendOne(channel, n);
          await sleep(intervalMs);
        }
      })
    );
  }

  const dur = Date.now() - start;
  console.log(`sent ${(players * messagesPerPlayer)} messages in ${dur}ms`);

  // Cleanup.
  for (const c of channels) {
    try {
      c.channel.leave();
      c.socket.disconnect();
    } catch {}
  }
}

run().catch((e) => {
  console.error(e);
  process.exit(1);
});

