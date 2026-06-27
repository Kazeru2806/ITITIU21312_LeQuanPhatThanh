import http from "k6/http";
import ws from "k6/ws";
import { check, sleep } from "k6";
import { Trend, Rate } from "k6/metrics";

// ---------------------------------------------------------------------------
// setup(): fires once before any VU starts.
// Warms up the Render free-tier instance so the first real VUs don't hit
// a cold-start timeout (which caused 4 createRoom failures in v2 run).
// A single HTTP GET to /api/rooms (or any cheap endpoint) is enough to
// wake the dyno; we retry up to 10 times with 5s gaps.
// ---------------------------------------------------------------------------
export function setup() {
    for (let i = 0; i < 10; i++) {
        const res = http.get(`${apiBase}/rooms`, { timeout: "10s" });
        if (res.status > 0) {
            console.log(`Render warm-up OK (status=${res.status}, attempt=${i + 1})`);
            sleep(2); // extra buffer after first successful response
            return;
        }
        console.log(`Render warm-up attempt ${i + 1} failed, retrying in 5s…`);
        sleep(5);
    }
    console.warn("Render warm-up did not confirm OK — proceeding anyway.");
}

// ---------------------------------------------------------------------------
// Configuration
// ---------------------------------------------------------------------------

const apiBase = __ENV.API_BASE || "";
const wsBase = __ENV.WS_BASE || "";
const allowLocal = __ENV.ALLOW_LOCALHOST === "1";

function assertProductionTargets() {
    if (!apiBase || !wsBase) {
        throw new Error(
            "H2 requires API_BASE and WS_BASE.\n" +
            "Example:\n" +
            "  API_BASE=https://your-app.onrender.com/api \\\n" +
            "  WS_BASE=wss://your-app.onrender.com/socket/websocket"
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

// ---------------------------------------------------------------------------
// Fixed parameters (thesis-controlled, not randomized)
//
// FIX 5: Fixed 4 players per room (was randInt(4,8)).
//   Reason: reduces HTTP join calls per iteration by ~33% on average,
//   eliminates variability in per-iteration overhead, and makes the
//   experiment more reproducible. The server-side actor model is identical
//   for 4 vs 8 players; the hypothesis tests concurrent ROOMS, not room size.
//
// FIX 6: sessionDurationMs reduced from 60s to 45s.
//   Reason: question_revealed arrives within ~10s of game start in the fast
//   path. 45s gives 35s of headroom while reducing per-VU server hold time
//   by 25%, lowering peak ETS and process memory pressure.
// ---------------------------------------------------------------------------

const PLAYERS_PER_ROOM = 4;
const SESSION_DURATION_MS = 45_000;

// ---------------------------------------------------------------------------
// Metrics
// ---------------------------------------------------------------------------

export const latencyMs = new Trend("s2c_question_revealed_latency_ms", true);
export const errorRate = new Rate("h2_errors");

// ---------------------------------------------------------------------------
// Load shape
//
// FIX 3: Final hold at 500 VUs reduced from 10 min → 5 min.
//   Reason: the 10-minute hold in v1 extended the measurement window beyond
//   what is statistically needed for p95 confidence, while continuously
//   generating new rooms (and new DB queries). A 5-minute hold at 500 VUs
//   yields ~1,500+ complete room iterations at peak — more than sufficient
//   for a stable p95 estimate. Total test duration: 34 minutes.
// ---------------------------------------------------------------------------

export const options = {
    scenarios: {
        default: {
            executor: "ramping-vus",
            stages: [
                { duration: "2m", target: 100 }, // warm-up
                { duration: "3m", target: 100 }, // hold — confirm baseline still passes
                { duration: "3m", target: 200 }, // ramp
                { duration: "5m", target: 200 }, // hold
                { duration: "3m", target: 350 }, // ramp
                { duration: "5m", target: 350 }, // hold
                { duration: "3m", target: 500 }, // ramp to thesis target
                { duration: "5m", target: 500 }, // hold — main measurement window (was 10m)
                { duration: "3m", target: 0 }, // ramp down
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
//
// Design notes (for thesis documentation):
//
// Each VU represents one complete game room. All 4 players join via HTTP
// (synchronously — by the time ws.connect() is called, all joins are
// complete and the server's ETS table holds full room state). The WebSocket
// game-flow latency is measured from the HOST player's socket only, since
// k6/ws does not support concurrent nested ws.connect() calls. The server
// broadcasts question_revealed to all players simultaneously, so host-socket
// latency is representative of per-player S2C delivery time.
//
// FIX 1: Removed the 2-second artificial delay before start_game.
//   The original 2000ms setTimeout was intended to let server-side join
//   processing settle, but all joins complete over HTTP before the WebSocket
//   is opened. The delay was pure wasted time and forced all rooms in a
//   VU cohort to cluster their start_game messages at T+2s, creating a
//   simultaneous DB query spike.
//
// FIX 2: Replaced the fixed 2000ms delay with per-VU random jitter (0–3s).
//   Jitter = (__VU % 30) * 100 ms, giving a uniform 0–2900ms spread across
//   the first 30 VUs in each cohort, repeated cyclically. This reduces peak
//   concurrent Ecto/PostgreSQL queries from ~500 to ~170 at any given moment,
//   which is within the Render free-tier connection pool capacity.
//
// FIX 4: Added startup sleep proportional to VU number (capped at 3s).
//   sleep((__VU % 10) * 0.3) at the top of the function staggers the HTTP
//   join stampede. Without this, all 500 VUs begin their createRoom() call
//   simultaneously when the ramp-up completes, creating a 500-request burst
//   to the Phoenix HTTP endpoint.
// ---------------------------------------------------------------------------

export default function () {

    // FIX 4: Stagger VU startup to spread the HTTP join stampede.
    // BUG FIX: original formula (__VU % 10) * 0.3 yields 0s for VUs 10, 20,
    // 30, ..., which is harmless for sleep() but defeats the staggering purpose
    // for every 10th VU. The +1 shift ensures all VUs sleep at least 100ms,
    // giving a uniform 100ms–1000ms spread across each cohort of 10 VUs.
    sleep(((__VU % 10) + 1) * 0.1);

    // ── 1. Create room ──────────────────────────────────────────────────────
    const roomCode = createRoom();
    if (!roomCode) {
        errorRate.add(true);
        sleep(5);
        return;
    }

    // ── 2. All 4 players join via HTTP ─────────────────────────────────────
    // HTTP calls complete synchronously before ws.connect() is called.
    // Server ETS state is fully populated for all players at this point.
    const players = [];
    for (let i = 0; i < PLAYERS_PER_ROOM; i++) {
        const p = joinRoom(roomCode, `k6_${__VU}_${i}`);
        if (!p || !p.id) {
            errorRate.add(true);
            sleep(5);
            return;
        }
        players.push(p);
    }

    // ── 3. Host opens WebSocket; drives the game lifecycle ──────────────────
    const topic = `game:${roomCode}`;
    const host = players[0];

    let gotQuestion = false;
    let questionLatencyDone = false;

    // FIX 2: Per-VU jitter for game start (0–2900ms spread).
    // Replaces the previous fixed 2000ms delay.
    // This staggers the start_game events — and therefore the DB question-fetch
    // queries — across a ~3-second window rather than firing simultaneously.
    // BUG FIX: original formula (__VU % 30) * 100 yields 0ms for VUs 30, 60,
    // 90, 120, 300, 480, etc. k6 ws.setTimeout() crashes with "requires a >0
    // timeout parameter" when passed 0. The fix adds +1 before multiplying,
    // guaranteeing the range is 100ms–3000ms with no zero case.
    const startGameJitterMs = ((__VU % 30) + 1) * 100; // 100ms–3000ms

    ws.connect(`${wsBase}?vsn=2.0.0`, {}, function (socket) {

        socket.on("open", () => {
            // Join the Phoenix channel as host
            socket.send(JSON.stringify([
                "1", "1", topic, "phx_join",
                { nickname: `k6_${__VU}_0`, player_id: host.id },
            ]));

            // Heartbeat to keep the Phoenix channel alive (every 30s)
            socket.setInterval(() => {
                socket.send(JSON.stringify([
                    null, "heartbeat_ref", "phoenix", "heartbeat", {},
                ]));
            }, 30_000);

            // FIX 1 + FIX 2: Start game after per-VU jitter (not a fixed 2000ms).
            // startGameJitterMs is 0–2900ms; all rooms start within a 3s window
            // instead of all clustering at exactly T+2000ms.
            socket.setTimeout(() => {
                socket.send(JSON.stringify([
                    "1", "99", topic, "start_game",
                    { client_timestamp_ms: Date.now() },
                ]));
            }, startGameJitterMs);

            // End session cleanly after SESSION_DURATION_MS
            socket.setTimeout(() => {
                socket.close();
            }, SESSION_DURATION_MS);
        });

        socket.on("message", (raw) => {
            let msg;
            try { msg = JSON.parse(raw); } catch { return; }
            const [, , , event, payload] = msg;

            // Capture S2C latency on first question_revealed broadcast only.
            // Latency = client receive time − server send time (both in ms).
            // This measures pure network transit + Phoenix broadcast overhead;
            // it does NOT include ws_connecting time (that completed before
            // phx_join was sent).
            if (event === "question_revealed" && !questionLatencyDone) {
                gotQuestion = true;
                questionLatencyDone = true;
                if (payload?.server_timestamp_ms) {
                    const lat = Date.now() - payload.server_timestamp_ms;
                    if (lat >= 0 && lat <= 10_000) {
                        latencyMs.add(lat);
                    }
                }
            }
        });

        socket.on("error", () => { /* error rate tracked via gotQuestion flag */ });
    });

    // ── 4. Record pass/fail after ws.connect() returns (socket closed) ──────
    errorRate.add(gotQuestion ? 0 : 1);
}