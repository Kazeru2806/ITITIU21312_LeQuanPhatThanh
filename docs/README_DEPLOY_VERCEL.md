# Deploying VN Party (monorepo: 2 frontends + Phoenix backend)

This repo has three runnable apps:

| App | Folder | Stack |
|-----|--------|--------|
| API + WebSockets | `backend/` | Elixir / Phoenix |
| Player UI | `frontend-player/` | Vite + React |
| Host / TV UI | `frontend-host/` | Vite + React |

**Important:** Vercel is ideal for the two static frontends. The Phoenix backend needs a long‑running server (WebSockets, ETS, Postgres). Do **not** expect `mix phx.server` to run on Vercel serverless as-is.

---

## Recommended architecture

1. **Backend** → [Fly.io](https://fly.io), [Railway](https://railway.app), [Render](https://render.com), or a VPS (your Ubuntu VM).
2. **frontend-player** → Vercel project #1
3. **frontend-host** → Vercel project #2

Both frontends call the same public API URL via `VITE_API_URL` and `VITE_WS_URL`.

---

## Step 1 — Deploy the backend (example: Fly.io)

From your machine (with [flyctl](https://fly.io/docs/hands-on/install-flyctl/) installed):

```bash
cd backend
fly launch
```

- Create a Postgres app when prompted (or attach an existing DB).
- Set secrets, for example:

```bash
fly secrets set DATABASE_URL="ecto://..." SECRET_KEY_BASE="$(mix phx.gen.secret)"
```

- Ensure `PHX_HOST` / `PORT` match Fly’s config in `config/runtime.exs` (Fly sets `PORT=8080`).

Deploy:

```bash
fly deploy
```

Note your public URL, e.g. `https://vn-party.fly.dev`.

**Health check:** open `https://vn-party.fly.dev/api/health` (or create room via API).

---

## Step 2 — Player frontend on Vercel

1. Push this repo to GitHub.
2. In [Vercel](https://vercel.com) → **Add New Project** → import the repo.
3. **Root Directory:** `frontend-player`
4. **Framework Preset:** Vite
5. **Build Command:** `npm run build`
6. **Output Directory:** `dist`
7. **Environment variables** (Production + Preview):

| Name | Example |
|------|---------|
| `VITE_API_URL` | `https://vn-party.fly.dev/api` |
| `VITE_WS_URL` | `wss://vn-party.fly.dev/socket` |

8. Deploy. Save the URL, e.g. `https://vn-party-player.vercel.app`.

---

## Step 3 — Host frontend on Vercel (second project)

Repeat Step 2 with:

- **Root Directory:** `frontend-host`
- Same `VITE_API_URL` and `VITE_WS_URL` pointing at the **same** backend.

Example host URL: `https://vn-party-host.vercel.app`.

---

## Step 4 — CORS and WebSocket origin (backend)

In production, allow your Vercel origins in Phoenix (e.g. `config/runtime.exs` or `endpoint.ex`):

- `https://vn-party-player.vercel.app`
- `https://vn-party-host.vercel.app`

Redeploy the backend after changing CORS/check_origin.

---

## Step 5 — Smoke test

1. Open the **host** Vercel URL → create / join display room.
2. Open the **player** URL on a phone → join with room code.
3. Confirm WebSocket connects (no “failed to join” in browser console).
4. Start a game from the player who has the **Host** badge.

## Step 6 — Hypothesis tests on production

| Hypothesis | Doc | Target |
|------------|-----|--------|
| H1 Latency | [README_H1_ACADEMIC_TEST.md](README_H1_ACADEMIC_TEST.md) | Render API + WSS |
| H2 Scalability | [README_H2_LOADTEST.md](README_H2_LOADTEST.md) | Render + `REDIS_URL` (not localhost) |
| H3 Security | [README_H3_COMMIT_REVEAL.md](README_H3_COMMIT_REVEAL.md) | Mix tests + `/api/rooms/:code/audit` on Render |

Set on **Render** (backend):

- `ALLOWED_ORIGINS` = comma-separated Vercel URLs if you add new preview domains

---

## Local / LAN testing (optional)

See [README_NETWORK.md](README_NETWORK.md) for `192.168.64.2` VM setup. Vercel is for internet-facing demos; LAN uses `.env.development` in each frontend.

---

## Optional: single Vercel account checklist

- [ ] Backend live with HTTPS + WSS
- [ ] Postgres migrated (`mix ecto.migrate` on deploy)
- [ ] Two Vercel projects (player + host), correct root dirs
- [ ] Env vars set on both frontends
- [ ] Backend CORS/check_origin includes both Vercel domains

---

## Why not one Vercel project for everything?

Vercel one project = one root directory per deployment. You can use a monorepo with **two projects** (above), or a custom build script at repo root that builds both `dist` folders into different output paths—that is harder to maintain than two projects.

The backend must stay on a platform that supports OTP, persistent connections, and Postgres.
