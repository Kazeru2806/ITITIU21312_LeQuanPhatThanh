# Sync Mac → Ubuntu VM

Use this **every time** you change code on your Mac and run the app on the VM (`192.168.64.2`).

## 1. Copy project to VM

Run on your **Mac**:

```bash
rsync -avz --delete \
  --exclude 'node_modules' \
  --exclude '_build' \
  --exclude 'deps' \
  --exclude '.git' \
  --exclude 'priv/static/assets' \
  /Users/kazeru2806/Documents/GitHub/vn-party-thesis/ \
  ubuntu@192.168.64.2:~/vn-party-thesis/
```

## 2. On the VM — backend

```bash
ssh ubuntu@192.168.64.2
cd ~/vn-party-thesis/backend
mix deps.get
mix ecto.migrate
mix phx.server
```

## 3. On the VM — frontends (two terminals)

```bash
cd ~/vn-party-thesis/frontend-host && npm install && npm run dev
```

```bash
cd ~/vn-party-thesis/frontend-player && npm install && npm run dev
```

## 4. Open on Mac browser

| App | URL |
|-----|-----|
| Host (TV) | http://192.168.64.2:5174 |
| Player | http://192.168.64.2:5173 |

Do **not** use `localhost` on the Mac unless the backend also runs on the Mac.

## Optional: one-line sync script on Mac

```bash
bash ~/vn-party-thesis/scripts/sync-to-vm.sh
```

(Create `scripts/sync-to-vm.sh` with the rsync command above if you want a shortcut.)
