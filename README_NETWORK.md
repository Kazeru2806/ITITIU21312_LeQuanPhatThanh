# Network setup — Mac browser + Ubuntu VM

Your VM IP: **192.168.64.2**

Both frontends ship with `.env.development` pointing API/WebSocket to that IP.  
**Do not open `localhost:5173` or `localhost:5174` on your Mac** unless you also run backend on the Mac.

## URLs to use on your Mac browser

| App    | URL |
|--------|-----|
| Host (big screen) | http://192.168.64.2:5174 |
| Player (phones / join) | http://192.168.64.2:5173 |
| Backend API | http://192.168.64.2:4000/api |

## Start everything on the VM

**Terminal 1 — backend**
```bash
cd ~/vn-party-thesis/backend
mix phx.server
```

**Terminal 2 — host UI**
```bash
cd ~/vn-party-thesis/frontend-host
npm install
npm run dev
```

**Terminal 3 — player UI**
```bash
cd ~/vn-party-thesis/frontend-player
npm install
npm run dev
```

After changing `.env.development`, restart both `npm run dev` processes.

## Test LAN (same Wi‑Fi, not “localhost trick”)

1. On Mac: open http://192.168.64.2:5174 → create room → **Copy code** (should show “Copied!”).
2. On Mac or phone (same Wi‑Fi): open http://192.168.64.2:5173 → enter code + name → join.
3. Pass: player appears in host lobby; no “Server timeout” error.

Quick API check from Mac:
```bash
curl -s http://192.168.64.2:4000/api/rooms -X POST -H 'Content-Type: application/json' -d '{}'
```
Should return JSON with `"success":true` within a few seconds.

## LAN vs true cross‑network (internet)

| | LAN test | Cross‑network (players anywhere) |
|--|----------|----------------------------------|
| Who can join | Devices on same Wi‑Fi / virtual LAN | Anyone with internet |
| What you need | VM IP `192.168.64.2` + ports open on VM | **Public IP or domain** + firewall/NAT forwarding **or** tunnel (ngrok, Cloudflare Tunnel) |
| Your current `.env` | ✅ Ready for LAN | ❌ Not enough by itself |

**Cross‑network** means a player on mobile data in another city can join. That requires either:

- Deploy backend + frontends on a cloud server with a public IP and open ports **4000, 5173, 5174**, then set `.env` to that public host; **or**
- Run a tunnel, e.g. `ngrok http 4000` and set `VITE_API_URL` / `VITE_WS_URL` to the ngrok URLs.

There is no magic “works everywhere” without one of those.

## If you still see “Server timeout”

1. Confirm backend log shows `Running VnPartyWeb.Endpoint with Bandit … at 0.0.0.0:4000`.
2. Use **192.168.64.2** in the browser address bar, not `localhost`.
3. From Mac: `curl http://192.168.64.2:4000/api/rooms -X POST -H 'Content-Type: application/json' -d '{}'`.
4. Restart host/player dev servers after copying new `.env.development`.
