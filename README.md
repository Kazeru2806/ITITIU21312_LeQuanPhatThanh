# VN Party - Real-Time Multiplayer Party Game Framework

A research thesis project exploring real-time multiplayer game systems through the design and implementation of a Jackbox-inspired party game framework for Vietnamese audiences.

## 🎯 Research Objectives

- Design comprehensive protocol for real-time party games
- Implement WebSocket-based communication with fault tolerance
- Evaluate performance under realistic network conditions
- Validate cryptographic fairness mechanisms

## 🏗️ Architecture

- **Backend**: Phoenix/Elixir (WebSocket, PubSub, OTP)
- **Frontend**: React + TypeScript + Vite
- **Database**: PostgreSQL 17
- **Message Broker**: Redis 8
- **Deployment**: Docker

## 🚀 Quick Start

### Prerequisites
- Elixir 1.19+
- Node.js 25+
- PostgreSQL 17+
- Redis 8+
- Docker

### Start Development Databases
```bash
docker-compose up -d
```

### Start Backend
```bash
cd backend
mix deps.get
mix ecto.create
mix ecto.migrate
mix phx.server
# Opens at http://localhost:4000
```

### Start Player Client
```bash
cd frontend-player
npm install
npm run dev
# Opens at http://localhost:5173
```

### Start Host Client
```bash
cd frontend-host
npm install
npm run dev
# Opens at http://localhost:5174
```

## 📊 Research Hypotheses

- **H1**: Maintain p95 latency ≤300ms for 8-player games
- **H2**: Support ≥500 concurrent game rooms
- **H3**: Achieve ≥95% cheat detection rate

## 📁 Project Structure
```
vn-party-thesis/
├── backend/              # Phoenix/Elixir backend
├── frontend-player/      # React player client
├── frontend-host/        # React host client
└── docker-compose.yml    # Development databases
```

## 👨‍🎓 Author

Lê Quan Phát Thành - ITITIU21312
International University - VNU HCMC

## 📝 License

MIT License - See LICENSE file
