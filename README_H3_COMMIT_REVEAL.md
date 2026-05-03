## H3 (Commit–Reveal Anti-Cheating) – Attack Simulation + Detection Rate

### Status

H3 is **implemented and empirically testable** in this repo.

What is enforced/detected:
- **Hash tampering**: if stored `answer`/`salt` are modified, we recompute and detect mismatch against `commit_hash`
- **Replay attack**: same `commit_hash` cannot be reused by the same player in the same room across rounds
- **Late commit**: commits after the reveal window closes are rejected
- **Timing manipulation**: commits very near the deadline are flagged as suspicious (`violation_reason="timing_manipulation"`)

### What “finished” means (success criterion)

Run 4 attack scenarios × 100 attempts each (400 total) and verify:
- detection rate **>= 95%** for each scenario

### Prereqs (macOS + Docker Postgres)

From repo root, start Postgres (and Redis if you want it running too):

```bash
docker compose up -d
docker compose ps
```

Create the test database **once** (the repo expects `vnparty_test` in MIX_ENV=test):

```bash
docker exec -i vnparty_postgres createdb -U vnparty_dev vnparty_test || true
```

### Run the H3 attack simulations

```bash
cd backend
mix ecto.migrate
MIX_ENV=test mix ecto.create
MIX_ENV=test mix ecto.migrate
MIX_ENV=test mix test test/h3_attack_sim_test.exs
```

### How to interpret the output

The test prints a report like:

- `hash_tampering: detected=100/100 rate=100%`
- `replay_attack: detected=100/100 rate=100%`
- `late_commit: detected=100/100 rate=100%`
- `timing_manipulation: detected=100/100 rate=100%`

If any scenario is below **95%**, H3 fails and needs adjustments (thresholds, enforcement, or protocol design).

