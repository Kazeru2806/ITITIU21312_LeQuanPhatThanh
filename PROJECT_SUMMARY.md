# VN Party Thesis - Project Summary

## 📋 Overview

**VN Party** is a real-time multiplayer party game framework (similar to Jackbox Games) built for Vietnamese audiences. This is a research thesis project exploring WebSocket-based real-time game systems with fault tolerance and cryptographic fairness mechanisms.

### Tech Stack
- **Backend**: Phoenix/Elixir (WebSocket Channels, PubSub, OTP/GenServer, ETS)
- **Frontend**: React + TypeScript + Vite
- **State Management**: Zustand
- **Database**: PostgreSQL 17
- **Message Broker**: Redis 8 (configured but not actively used yet)
- **Deployment**: Docker

---

## 🎮 Game Mechanics Implemented

### Core Game Flow
1. **Lobby System**
   - Players join with a 6-character room code
   - First player becomes the host
   - Host can start the game when 2+ players are present
   - Real-time player list updates via WebSocket

2. **Game Rounds**
   - 5 rounds per game (configurable)
   - Each round presents a multiple-choice Vietnamese trivia question
   - 15-second time limit per question
   - Players select and commit their answers

3. **Answer Commit-Reveal System**
   - Players commit answers with cryptographic hashing (salt + hash)
   - Answers are revealed only after:
     - **All connected players have committed**, OR
     - **Timer expires** (time_limit + 2 seconds buffer)
   - Prevents cheating by hiding answers until reveal phase

4. **Scoring System**
   - Correct answers: +100 points
   - Incorrect answers: 0 points
   - Real-time leaderboard updates after each round
   - Players who don't submit get 0 points (game continues)

5. **Rematch System**
   - After game ends, players can vote to play again
   - Requires **2+ players** to vote for rematch
   - If 2+ players vote: Reset to lobby (only voters remain)
   - If <2 players vote: All players kicked to home page
   - 30-second timeout for voting

### Game States
- `lobby`: Waiting for players
- `round_start`: Round has started, question will be shown
- `answering`: Players are answering
- `commit_locked`: Answers are committed, waiting for reveal
- `revealing`: Answers are being revealed
- `scoring`: Round is being scored
- `round_end`: Round ended, showing results
- `game_end`: All rounds completed

---

## 🔧 What We Fixed in This Session

### 1. **Compilation Warnings Fixed**
   - **Issue**: `handle_info/2` function clauses were scattered throughout the file
   - **Fix**: Grouped all `handle_info/2` clauses together (Elixir requirement)
   - **Files Changed**: `backend/lib/vn_party_web/channels/game_channel.ex`

### 2. **Previous Session Fixes (Summary)**
   - **Bug 1 - Premature Answer Reveal**: Fixed to only reveal when all players commit or timer expires
   - **Bug 2 - Host Controls**: Removed host-only controls during gameplay; host is now a normal player
   - **Bug 3 - Rematch Logic**: Implemented proper rematch voting with ETS (shared state)
   - **Bug 4 - Stuck at "Đang chuẩn bị câu hỏi"**: Fixed by immediately broadcasting questions on game start/round advance
   - **Bug 5 - Rematch Vote Not Updating**: Migrated from `Process.get/put` to ETS for shared state across channel processes

---

## 📁 Project Structure

```
vn-party-thesis/
├── backend/                    # Phoenix/Elixir backend
│   ├── lib/
│   │   ├── vn_party/          # Business logic
│   │   │   ├── game.ex        # Game context (CRUD operations)
│   │   │   └── game/          # Schemas
│   │   │       ├── room.ex
│   │   │       ├── player.ex
│   │   │       ├── answer_commit.ex
│   │   │       ├── event.ex
│   │   │       └── snapshot.ex
│   │   └── vn_party_web/      # Web layer
│   │       ├── channels/
│   │       │   └── game_channel.ex  # ⚠️ CRITICAL - WebSocket logic
│   │       ├── controllers/
│   │       └── router.ex
│   ├── priv/repo/migrations/  # Database migrations
│   └── config/                # Configuration
│
├── frontend-player/            # React player client
│   ├── src/
│   │   ├── pages/
│   │   │   ├── JoinPage.tsx   # Join/create room
│   │   │   ├── LobbyPage.tsx  # Wait for game start
│   │   │   ├── GamePage.tsx   # Play the game
│   │   │   └── ResultsPage.tsx # Final scores & rematch
│   │   ├── hooks/
│   │   │   └── useGameSocket.ts  # ⚠️ CRITICAL - WebSocket hook
│   │   ├── store/
│   │   │   └── gameStore.ts   # Zustand state management
│   │   ├── types/
│   │   │   └── game.ts        # TypeScript types
│   │   └── lib/
│   │       └── api.ts         # REST API calls
│
└── frontend-host/              # React host client (minimal, not actively used)
```

---

## ⚠️ CRITICAL: What NOT to Touch When Upgrading Frontend

### 🔴 **DO NOT MODIFY** - Backend WebSocket Protocol

#### 1. **Channel Events (Backend → Frontend)**
These events are broadcast by the backend and MUST be handled correctly:

```typescript
// In useGameSocket.ts - DO NOT CHANGE EVENT NAMES
channel.on('player_joined', ...)           // ✅ Keep
channel.on('player_disconnected', ...)      // ✅ Keep
channel.on('game_started', ...)            // ✅ Keep
channel.on('question_revealed', ...)       // ✅ Keep
channel.on('player_committed', ...)        // ✅ Keep
channel.on('round_scored', ...)            // ✅ Keep
channel.on('round_started', ...)           // ✅ Keep
channel.on('game_ended', ...)              // ✅ Keep
channel.on('rematch_vote_updated', ...)   // ✅ Keep
channel.on('rematch_approved', ...)       // ✅ Keep
channel.on('rematch_cancelled', ...)       // ✅ Keep
```

#### 2. **Channel Messages (Frontend → Backend)**
These messages are sent to the backend and MUST use exact names:

```typescript
// In useGameSocket.ts - DO NOT CHANGE MESSAGE NAMES
channel.push('start_game', {})                    // ✅ Keep
channel.push('commit_answer', { answer, question_id })  // ✅ Keep
channel.push('request_rematch', {})               // ✅ Keep
channel.push('decline_rematch', {})               // ✅ Keep
channel.push('get_state', {})                     // ✅ Keep
```

#### 3. **Channel Join Parameters**
```typescript
// In useGameSocket.ts - DO NOT CHANGE
const channel = socket.channel(`game:${roomCode}`, {
    nickname,      // ✅ Keep
    player_id,     // ✅ Keep (snake_case required by backend)
});
```

#### 4. **Event Data Structures**
The backend sends specific data structures. DO NOT change the expected shape:

```typescript
// Example: round_scored event
interface RoundScoredData {
    round: number;
    scores: Array<{
        player_id: string;      // ✅ Keep
        is_correct: boolean;    // ✅ Keep
        points: number;         // ✅ Keep
        answer: string;         // ✅ Keep
    }>;
    leaderboard: LeaderboardEntry[];  // ✅ Keep
    correct_answer?: string;           // ✅ Keep
}
```

### 🟡 **BE CAREFUL** - Backend Files

#### `backend/lib/vn_party_web/channels/game_channel.ex`
- **DO NOT** modify the event names being broadcast
- **DO NOT** modify the message handlers (`handle_in`)
- **DO NOT** change the game flow logic (auto-advance, scoring, rematch)
- **OK TO** modify: Helper functions, formatting, comments

#### `backend/lib/vn_party/game.ex`
- **DO NOT** modify database schema or core CRUD operations
- **OK TO** modify: Query optimizations, additional helper functions

### 🟢 **SAFE TO MODIFY** - Frontend Files

#### ✅ **Safe to Change:**
- `frontend-player/src/pages/*.tsx` - UI/UX improvements
- `frontend-player/src/components/*` - Component styling/logic
- `frontend-player/src/store/gameStore.ts` - State management (as long as it matches backend events)
- CSS/styling files
- Routing logic (as long as routes match backend expectations)

#### ⚠️ **Modify with Caution:**
- `frontend-player/src/hooks/useGameSocket.ts`
  - **OK**: Add new event handlers, improve error handling
  - **NOT OK**: Change event names, message names, or data structure expectations
  - **NOT OK**: Remove existing event handlers

---

## 🔌 WebSocket Protocol Reference

### Connection
```
URL: ws://localhost:4000/socket
Channel: "game:{room_code}"
Join Params: { nickname: string, player_id: string }
```

### Backend → Frontend Events

| Event | When | Data Structure |
|-------|------|----------------|
| `player_joined` | Player joins room | `{ player_id, nickname, timestamp, players[] }` |
| `player_disconnected` | Player disconnects | `{ player_id, nickname? }` |
| `game_started` | Game begins | `{ round, total_rounds, timestamp }` |
| `question_revealed` | Question shown | `{ id, text, options[], correct, time_limit }` |
| `player_committed` | Player commits answer | `{ player_id, timestamp }` |
| `round_scored` | Round scored | `{ round, scores[], leaderboard[], correct_answer }` |
| `round_started` | New round begins | `{ round, total_rounds }` |
| `game_ended` | Game finished | `{ final_scores[], winner? }` |
| `rematch_vote_updated` | Rematch vote cast | `{ vote_count, total_players, voters[] }` |
| `rematch_approved` | Rematch approved (2+ votes) | `{ message, voters[] }` |
| `rematch_cancelled` | Rematch cancelled (<2 votes) | `{ message, kick_to_home: boolean }` |

### Frontend → Backend Messages

| Message | Purpose | Payload |
|---------|---------|---------|
| `start_game` | Start the game | `{}` |
| `commit_answer` | Commit answer | `{ answer: string, question_id: string }` |
| `request_rematch` | Vote for rematch | `{}` |
| `decline_rematch` | Decline rematch | `{}` |
| `get_state` | Get current game state | `{}` |

---

## 🎯 Current Game Flow (Automated)

### Game Start
1. Host clicks "Bắt đầu trò chơi" → `start_game` message
2. Backend broadcasts `game_started` event
3. Backend **immediately** generates and broadcasts `question_revealed`
4. Frontend navigates to `/game` and shows question

### Answer Submission
1. Player selects answer and clicks commit → `commit_answer` message
2. Backend stores answer, broadcasts `player_committed`
3. **If all connected players committed**: Backend schedules `auto_reveal`
4. **If timer expires**: Backend triggers `force_auto_reveal`
5. Backend scores answers, broadcasts `round_scored`
6. After 5 seconds, backend automatically advances to next round

### Round Advancement
1. Backend calls `Game.advance_round()`
2. Backend broadcasts `round_started`
3. Backend **immediately** generates and broadcasts `question_revealed` for new round
4. Process repeats until `current_round >= total_rounds`

### Game End & Rematch
1. After final round, backend broadcasts `game_ended`
2. Frontend navigates to `/results`
3. Players vote: `request_rematch` or `decline_rematch`
4. Backend uses **ETS** (shared state) to track votes
5. **If 2+ votes**: Backend removes non-voters, resets room, broadcasts `rematch_approved`
6. **If <2 votes**: Backend broadcasts `rematch_cancelled` with `kick_to_home: true`
7. 30-second timeout triggers same logic

---

## 🗄️ Database Schema

### Tables
- `rooms` - Game rooms (code, state, current_round, total_rounds, etc.)
- `players` - Players in rooms (nickname, score, is_host, connected, etc.)
- `answer_commits` - Committed answers (answer, salt, hash, points_awarded, etc.)
- `game_events` - Event log for event sourcing
- `snapshots` - Game state snapshots (not actively used yet)

### Key Relationships
- Room has_many Players
- Room has_many AnswerCommits
- Room has_many Events
- Player belongs_to Room

---

## 🔐 Security Features

1. **Answer Commit-Reveal**: Cryptographic hashing prevents cheating
   - Salt generated server-side
   - Hash stored before reveal
   - Answer revealed only after all commit or timer expires

2. **Connection Tracking**: Players marked as connected/disconnected
   - Only connected players counted for game flow
   - Disconnected players don't block game progression

3. **Host Reassignment**: If host leaves, new host assigned automatically

---

## 🚀 Development Commands

### Backend
```bash
cd backend
mix deps.get
mix ecto.create
mix ecto.migrate
mix phx.server  # Runs on http://localhost:4000
```

### Frontend Player
```bash
cd frontend-player
npm install
npm run dev  # Runs on http://localhost:5173
```

### Database (Docker)
```bash
docker-compose up -d  # Start PostgreSQL & Redis
```

---

## 📝 Notes for Frontend Improvements

### What Can Be Improved (Safely)
1. **UI/UX Enhancements**
   - Better animations and transitions
   - Improved mobile responsiveness
   - Better error messages and loading states
   - Vietnamese language improvements

2. **User Experience**
   - Better visual feedback for committed players
   - Improved timer display
   - Better leaderboard visualization
   - Sound effects (optional)

3. **Code Quality**
   - Better TypeScript types
   - Improved error handling
   - Better state management patterns
   - Component refactoring

### What Must Stay the Same
1. **WebSocket event names** (exact match required)
2. **Message names** sent to backend (exact match required)
3. **Data structure expectations** (must match backend)
4. **Game flow logic** (backend controls this)

---

## 🐛 Known Issues / Future Improvements

1. **Mock Questions**: Currently using hardcoded Vietnamese trivia questions
   - Future: Database-backed question bank
   - Future: Question categories/difficulty levels

2. **No Authentication**: Players identified only by nickname
   - Future: User accounts, persistent profiles

3. **No Spectator Mode**: Disconnected players can't rejoin mid-game
   - Future: Reconnection logic for disconnected players

4. **Single Game Type**: Only trivia questions
   - Future: Multiple game modes (drawing, word games, etc.)

5. **No Room Persistence**: Rooms deleted when empty
   - Future: Room history, saved games

---

## 📚 Key Files Reference

### Backend
- `backend/lib/vn_party_web/channels/game_channel.ex` - **Main WebSocket logic**
- `backend/lib/vn_party/game.ex` - **Game business logic**
- `backend/lib/vn_party/game/room.ex` - **Room schema**
- `backend/lib/vn_party/game/player.ex` - **Player schema**
- `backend/lib/vn_party/game/answer_commit.ex` - **Answer commit schema**

### Frontend
- `frontend-player/src/hooks/useGameSocket.ts` - **WebSocket hook (CRITICAL)**
- `frontend-player/src/store/gameStore.ts` - **State management**
- `frontend-player/src/pages/GamePage.tsx` - **Main game UI**
- `frontend-player/src/pages/ResultsPage.tsx` - **Results & rematch UI**

---

## ✅ Testing Checklist

Before deploying frontend changes, verify:
- [ ] Players can join rooms
- [ ] Game starts when host clicks button
- [ ] Questions appear immediately
- [ ] Answers can be committed
- [ ] Answers reveal only after all commit or timer expires
- [ ] Scoring works correctly
- [ ] Rounds advance automatically
- [ ] Game ends after 5 rounds
- [ ] Rematch voting works (2+ players)
- [ ] Rematch cancellation works (<2 players)
- [ ] Players are removed correctly on rematch decline
- [ ] Navigation between pages works
- [ ] Connection status updates correctly

---

## 📞 Contact

**Author**: Lê Quan Phát Thành - ITITIU21312  
**Institution**: International University - VNU HCMC  
**Project**: VN Party - Real-Time Multiplayer Party Game Framework

---

**Last Updated**: After fixing compilation warnings (handle_info grouping)

