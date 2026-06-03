# Answer commits: hash vs plaintext in the database

## What we store

Each player answer uses a **commit–reveal** pattern:

1. **Commit phase:** client sends the chosen option; server stores `commit_hash = SHA256(answer + ":" + salt)` and records the commit time.
2. **Reveal / scoring:** server checks the hash and awards points.

The `answer_commits` table has:

| Column | Role |
|--------|------|
| `commit_hash` | Binding commitment (tamper-evident) |
| `salt` | Randomness so hashes are not guessable by brute force |
| `answer` | Plaintext option id (e.g. `"A"`) — optional depending on config |

## Why plaintext was stored next to the hash

For a **party trivia thesis prototype**, storing `answer` at commit time was a pragmatic choice:

- **Auto-scoring** when all players commit does not require a second “reveal” message.
- **Truth Collapse** live option counts read committed answers from the DB.
- **Simpler recovery** if a channel process crashes before reveal.

The **hash still proves** the commit was made at submit time; the risk is not “fake commits” but **who can read the answer before reveal**.

## Threat model (honest)

| Concern | With plaintext in DB | Hash-only at commit (`store_commit_plaintext: false`) |
|---------|----------------------|--------------------------------------------------------|
| DB leak before round ends | Attacker sees answers | Only hashes + salts |
| Compromised server / admin | Can read early answers | Answers in ETS until scoring, then scoring uses memory |
| Client cheating | Still blocked by commit window + hash | Same |
| Audit / replay | Hash chain in events still applies | Same |

For a classroom demo on a trusted VM, plaintext-in-DB is often acceptable. For production or high-stakes play, prefer hash-only at commit.

## What we implemented

In `config/config.exs`:

```elixir
config :vn_party, store_commit_plaintext: true
```

- **`true` (default):** `answer` is written to Postgres at commit (current behaviour).
- **`false`:** only `commit_hash` + `salt` go to the DB; plaintext is kept in the `:pending_answers` ETS table until scoring. Scoring paths use `Game.commit_answer_text/1` to resolve the answer.

To harden a deployment:

```bash
# config/prod.exs or runtime env
config :vn_party, store_commit_plaintext: false
```

Then redeploy the backend (ETS is per-node; single-node Fly/Railway is fine).

## Stronger options (future)

1. **Two-step reveal:** client sends `reveal` with answer + salt after the timer; server runs `AnswerCommit.reveal_changeset/2` and never stores answer before reveal.
2. **Encrypt at rest:** encrypt `answer` with a server key (still decryptable by the app, but not by a raw DB dump alone).
3. **On-chain anchor only:** keep hashes in the audit trail; never persist plaintext (matches H3 “integrity” story without exposing gameplay).

## Summary

- Storing plaintext **alongside** the hash is **not** redundant security—it trades **confidentiality until reveal** for **operational simplicity**.
- The commit hash remains the integrity mechanism for “they locked this answer at time T”.
- Use `store_commit_plaintext: false` when you want hash-only commits in the database for demos or production hardening.
