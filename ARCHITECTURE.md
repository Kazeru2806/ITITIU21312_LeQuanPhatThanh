# VN Party Thesis - High Level Architecture

```mermaid
flowchart LR
  subgraph Browser
    P[frontend-player SPA]
    H[frontend-host SPA]
  end

  subgraph Backend[Backend Phoenix App]
    S[Phoenix Socket Endpoint]
    GC[Game Channel]
    DC[Display Channel]
    API[HTTP Controllers / API]
    GL[Game Logic / Domain]
    REPO[Ecto Repo / PostgreSQL]
    BC[Blockchain Anchor / Audit Trail]
    TM[Telemetry / Latency Measurement]
  end

  subgraph Infra[Tools & Testing]
    LT[loadtest/k6]
    LG[tools/loadgen]
    NE[netem scripts]
  end

  P -->|WS Phoenix Channel| GC
  H -->|WS Phoenix Channel| DC
  P -->|REST / API| API
  H -->|REST / API| API
  GC --> GL
  DC --> GL
  API --> GL
  GL --> REPO
  BC --> REPO
  TM --> REPO
  LT -->|Traffic generation| Backend
  LG -->|Traffic generation| Backend
  NE -->|Network shaping| Browser
```

## Description

- `frontend-player` is the player-facing SPA that connects to the Phoenix backend via WebSocket channels and HTTP API calls.
- `frontend-host` is the host/display SPA for lobby and game display, also using WebSocket channels and API access.
- The Phoenix backend runs the game domain, channels, API controllers, persistence, blockchain anchoring, and telemetry.
- `Ecto Repo / PostgreSQL` stores rooms, players, game events, answer commits, snapshots, latency measurements, and blockchain anchors.
- `loadtest/k6`, `tools/loadgen`, and `scripts/netem` provide performance testing and network condition simulation.
