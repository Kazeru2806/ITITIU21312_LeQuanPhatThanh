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

async function createRoom(apiBase) {
  const res = await fetch(`${apiBase}/rooms`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({}),
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
  const apiBase = `http://${host}:4000/api`;
  const wsUrl = `ws://${host}:4000/socket`;

  const players = Number(getArg("--players", "8"));
  const messagesPerPlayer = Number(getArg("--messages", "100"));
  const roomCodeArg = getArg("--room", "");

  const roomCode = roomCodeArg ? roomCodeArg.toUpperCase() : await createRoom(apiBase);
  console.log(`room=${roomCode}`);

  // Join N players via HTTP so we have player_id.
  const playerIds = [];
  for (let i = 0; i < players; i++) {
    const pid = await joinRoom(apiBase, roomCode, randNick(i + 1));
    playerIds.push(pid);
  }

  // Connect sockets + join channels.
  const channels = [];
  for (let i = 0; i < players; i++) {
    const socket = new Socket(wsUrl, { params: {} });
    socket.connect();
    const channel = socket.channel(`game:${roomCode}`, {
      nickname: `lg_${i + 1}`,
      player_id: playerIds[i],
    });

    await new Promise((resolve, reject) => {
      channel
        .join()
        .receive("ok", resolve)
        .receive("error", reject);
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

  // We measure “submit_prediction” because it’s safe (no question_id needed).
  // Send messagesPerPlayer predictions per player with timestamps.
  const opts = ["A", "B", "C", "D"];
  const start = Date.now();

  await Promise.all(
    channels.map(async ({ channel }) => {
      for (let n = 0; n < messagesPerPlayer; n++) {
        const option_id = opts[(n + Math.floor(Math.random() * 4)) % 4];
        channel.push("submit_prediction", { option_id, client_timestamp_ms: Date.now() });
        await sleep(10 + Math.floor(Math.random() * 10));
      }
    })
  );

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

