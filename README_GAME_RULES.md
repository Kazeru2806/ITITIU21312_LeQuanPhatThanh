# Truth Collapse — game rules (thesis reference)

## Host and lobby

- First player in an empty room becomes **host** (can start from their phone).
- Closing the tab or **Return to main screen** removes that player immediately; host badge passes to another connected player.
- **Return to main screen** on the **host TV** calls `POST /api/rooms/:code/close` and broadcasts `room_closed` so every player is sent home immediately.

## Distortion powers — full limits

All limits are enforced **server-side** (`DistortionRules`). Each use also writes `game_events` + blockchain anchor.

| Power | Cost (charges) | Per player / game | Per room / game | Notes |
|-------|----------------|-------------------|-----------------|-------|
| **Remove option** | 2 | **1** | **3** total | Cannot target yourself; removes wrong options from target’s view next round |
| **Swap category** | 2 | **2** | **4** total | Changes category theme for next round |
| **Force blind** | 3 | **1** | **3** total | Shuffles answer order for target; cannot target yourself |
| **Inject fake option** | 4 | **1** | — | Two-step: lock → enter text (max 60 chars, safety filter) |
| **Merge realities** | 4 | — | **1** total | No effect on final round; merges scoring realities once per game |

### Committee answer: “How many deletes per session?”

**Remove option** = delete answer: **at most 3 times in the entire room per game**, and **each player may use it at most once**.

### Why room-wide caps?

Without room caps, 8 players could each spam swap/blind and break game flow. Room caps keep distortions **tactical**, not chaotic.

### When to use distortions

- **Discussion phase:** pick a power, then tap **Done — start answering**. Powers apply when the answer phase begins.
- **Results phase:** same flow before the next round.
- Tap **Done** early with all players ready to skip the discussion timer.

## Charges (distortion power)

- Players earn charges from Truth Collapse scoring (wrong-guess rewards, etc.).
- Server rejects use if `charges < cost` or limits exceeded.

## Mid-game join

- **Lobby:** open until host starts.
- **After start:** only reconnect with same `player_id` (sessionStorage). New strangers rejected (`game_in_progress`).

## Disconnect

- Tab closed / network drop → removed from roster (abnormal WebSocket close).
- In-app navigation (lobby → game) → **not** treated as leave (same player reconnects channel).
- Tab still open → heartbeat every 10s keeps connection alive.

## Blockchain

`GET /api/rooms/:code/audit` — hash chain over game events. See `README_H3_COMMIT_REVEAL.md` and `README_SECURITY_ANSWER_COMMITS.md`.
