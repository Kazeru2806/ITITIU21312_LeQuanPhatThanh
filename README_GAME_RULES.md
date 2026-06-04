# Truth Collapse — game rules (thesis reference)

## Host and lobby

- First player in an empty room becomes **host** (can start the game from their phone).
- If the host **closes the tab**, presses **Return to main screen**, or disconnects, they are **removed from the lobby immediately** and host passes to another **connected** player.
- **Return to main screen** on the **host TV** ends the room for everyone (`room_closed`).

## Distortion power (answered for committee)

**Remove option** (“delete answer”): removes wrong options from a **target player’s** view next round.

**Maximum per game session (this build):**

| Distortion | Per player (per game) | Whole room (per game) |
|------------|----------------------|------------------------|
| Remove option | **1** | **3** total |
| Swap category | 2 | — |
| Force blind | 1 | — |
| Inject fake option | 1 | — |
| Merge realities | — | **1** total |

So the teacher’s question “how many deletes can occur in one session?” → **at most 3 remove-option effects in the entire room**, and **each player may use remove option at most once**.

Charges still cost distortion power (2 charges for remove option, etc.). Limits are enforced server-side; events are written to the **event log** and **blockchain anchor chain** when enabled.

## Mid-game join

- **Lobby:** anyone with a name can join until the host starts.
- **After start:** only **reconnect** with the same `player_id` (stored in browser session). New names / strangers are rejected.

## Disconnect

- Close tab / leave room → **immediate removal** from lobby (no 30s / 75s wait).
- Brief tab switch with game tab still open → **heartbeat** keeps the WebSocket alive.

## Blockchain (H3)

Each `player_joined`, `player_left`, `distortion_used`, `player_rejoined`, `room_closed`, etc. creates a `game_events` row. `AuditTrail.on_event/1` appends a **hash chain** in `blockchain_anchors` (and optionally anchors on-chain if `EVM` is configured).

Room audit API: `GET /api/rooms/:code/audit`
