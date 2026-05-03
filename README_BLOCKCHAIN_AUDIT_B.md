## Blockchain Audit Trail (Option B)

This project now supports a real blockchain anchoring path for game events.

### How it works

1. Every `game_events` row is hashed (`event_hash`).
2. Hashes are linked as a chain per room (`prev_chain_hash -> chain_hash`).
3. Each chain hash is written to `blockchain_anchors`.
4. If blockchain env vars are configured, the backend submits an on-chain tx and stores `tx_hash`.
5. Host UI fetches `/api/rooms/:code/audit` and shows the latest anchors.

### Status values

- `pending` - anchor row created, waiting to submit
- `anchored` - submitted to chain successfully, has `tx_hash`
- `failed` - submission failed, check `error`
- `simulated` - blockchain not configured; anchor chain still works locally

### Environment variables

Set these before starting backend:

```bash
export BLOCKCHAIN_RPC_URL="http://127.0.0.1:8545"
export BLOCKCHAIN_FROM_ADDRESS="0xYourUnlockedAddress"
export BLOCKCHAIN_TO_ADDRESS="0xReceiverAddressOrSameAsFrom"
```

If unset, the system runs in simulated mode.

### Local dev chain quick setup (Anvil)

```bash
anvil --host 0.0.0.0 --port 8545
```

Use one of Anvil's unlocked accounts for `BLOCKCHAIN_FROM_ADDRESS`.

### Start backend

```bash
cd backend
mix ecto.migrate
mix phx.server
```

### Verify anchoring

1. Create room and play normally.
2. Query audit API:

```bash
curl "http://localhost:4000/api/rooms/ROOMCODE/audit"
```

3. In host `Results` screen, open **Blockchain Audit Trail** panel and check:
   - `status`
   - `chain_hash`
   - `tx_hash` (when anchored)

### Tamper-evidence property

Because each event is linked via `prev_chain_hash`, editing a historical event breaks all downstream chain hashes. If anchored on-chain, mismatch is cryptographically provable.

