# H3 — Commit–reveal security (what is actually being tested)

## Hypothesis

**H3:** The commit–reveal protocol detects cheating attempts (hash tampering, replay, late commit, suspicious timing) at a rate **≥ 95%** per attack type.

---

## Two layers of evidence (read this for the thesis)

### Layer A — Automated detection logic (white-box)

File: `backend/test/h3_attack_sim_test.exs`

```bash
cd backend
MIX_ENV=test mix ecto.create
MIX_ENV=test mix ecto.migrate
MIX_ENV=test mix test test/h3_attack_sim_test.exs
```

This runs **400 controlled attempts** (4 scenarios × 100 each) by calling `Game` / commit functions directly.

**What this proves:** The detection **code paths** work when fed known-bad inputs.

**What this does NOT prove alone:** That a remote attacker cannot bypass checks via HTTP/WebSocket in production. That requires Layer B.

### Layer B — Independent verification (black-box / audit)

Automated (run with Layer A):

```bash
cd backend
MIX_ENV=test mix test test/h3_ws_commit_test.exs test/truth_results_test.exs --trace
```

`h3_ws_commit_test.exs` exercises **replay**, **late commit**, and **hash tampering** through `Game.commit_answer_secure/5` — the same enforcement the WebSocket `commit_answer` handler uses (not a separate mock).

After real games on Render:

1. **Audit API:** `GET /api/rooms/:code/audit` — hash chain in `blockchain_anchors`
2. **Results ready fallback:** `POST /api/rooms/:code/truth_results_ready` with `{ "player_id": "..." }` if mobile WebSocket push fails
3. **DB tamper detection:** If someone edits `answer_commits` in Postgres, reveal/score must flag `hash_tampering`

**What this proves:** The running system + audit trail align with the protocol design.

---

## Attack scenarios (Layer A)

| Scenario | What it simulates | Expected detection |
|----------|-------------------|-------------------|
| `hash_tampering` | Stored answer changed after commit | Recompute hash ≠ `commit_hash` |
| `replay_attack` | Reuse same commit hash in another round | Rejected as duplicate |
| `late_commit` | Commit after window closed | Rejected |
| `timing_manipulation` | Commit in last milliseconds | Flagged suspicious |

Pass criterion: **≥ 95% detected** per scenario (test prints rates).

---

## How to run Layer A (step by step)

```bash
# Postgres for test DB
docker compose up -d

docker exec -i vnparty_postgres createdb -U vnparty_dev vnparty_test 2>/dev/null || true

cd backend
mix ecto.migrate
MIX_ENV=test mix test test/h3_attack_sim_test.exs --trace
```

Save the printed summary for your appendix.

---

## Layer B — Production checklist (Render)

After deploying backend with migrations:

1. Play one full Classic round on Vercel + Render
2. Call audit endpoint:

```bash
curl -s "https://YOUR-SERVICE.onrender.com/api/rooms/ROOMCODE/audit" | jq .
```

3. Confirm `blockchain_anchors` rows chain (`prev_chain_hash` → `chain_hash`)
4. Document that commits are stored **before** reveal and hashes are verified at reveal time (see `README_SECURITY_ANSWER_COMMITS.md`)

---

## Academic honesty (important)

| Approach | Valid for thesis? |
|----------|-------------------|
| `h3_attack_sim_test.exs` only | **Partial** — implementation verification |
| Sim test + audit API + one manual API rejection | **Strong** — design + deployment |
| Sim test + third-party pen test | **Strongest** — if available |

State clearly in your methodology: *“Automated tests validate detection logic; production audit endpoint validates append-only event hashing after live sessions.”*

---

## Blockchain link (H3 + audit trail)

Each `answer_committed`, `answer_revealed`, `distortion_used`, etc. creates a `game_events` row. `AuditTrail.on_event/1` appends SHA-256 chain entries. Optional EVM anchor when configured.

---

## VM sync

See [README_SYNC_VM.md](README_SYNC_VM.md).
