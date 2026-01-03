# Frontend Upgrade Guide - What NOT to Touch

## 🚨 CRITICAL: Backend Protocol - DO NOT MODIFY

### WebSocket Event Names (Backend → Frontend)
These exact event names are broadcast by the backend. **DO NOT CHANGE THEM**:

```typescript
// In useGameSocket.ts - These MUST stay exactly as they are:
'player_joined'
'player_disconnected'
'game_started'
'question_revealed'
'player_committed'
'round_scored'
'round_started'
'game_ended'
'rematch_vote_updated'
'rematch_approved'
'rematch_cancelled'
```

### WebSocket Message Names (Frontend → Backend)
These exact message names are sent to the backend. **DO NOT CHANGE THEM**:

```typescript
// In useGameSocket.ts - These MUST stay exactly as they are:
'start_game'
'commit_answer'
'request_rematch'
'decline_rematch'
'get_state'
```

### Event Data Structures
The backend sends data in these exact shapes. **DO NOT CHANGE THE EXPECTED STRUCTURE**:

```typescript
// Example: round_scored event
{
    round: number;
    scores: Array<{
        player_id: string;      // ✅ Keep as-is
        is_correct: boolean;    // ✅ Keep as-is
        points: number;         // ✅ Keep as-is
        answer: string;         // ✅ Keep as-is
    }>;
    leaderboard: Array<{
        player_id: string;      // ✅ Keep as-is
        nickname: string;       // ✅ Keep as-is
        score: number;          // ✅ Keep as-is
    }>;
    correct_answer?: string;    // ✅ Keep as-is
}
```

### Channel Join Parameters
```typescript
// In useGameSocket.ts - DO NOT CHANGE
socket.channel(`game:${roomCode}`, {
    nickname: string,      // ✅ Keep
    player_id: string,    // ✅ Keep (snake_case required by backend)
});
```

---

## ⚠️ Backend Files - DO NOT MODIFY

### `backend/lib/vn_party_web/channels/game_channel.ex`
- **DO NOT** change event names being broadcast
- **DO NOT** change message handler names (`handle_in`)
- **DO NOT** modify game flow logic (auto-advance, scoring, rematch)
- **DO NOT** change the automated game progression

### `backend/lib/vn_party/game.ex`
- **DO NOT** modify database operations
- **DO NOT** change function signatures that are called by the channel

---

## ✅ Safe to Modify - Frontend Files

### Pages (UI/UX)
- ✅ `frontend-player/src/pages/JoinPage.tsx` - Styling, layout
- ✅ `frontend-player/src/pages/LobbyPage.tsx` - Styling, layout
- ✅ `frontend-player/src/pages/GamePage.tsx` - Styling, animations, UI improvements
- ✅ `frontend-player/src/pages/ResultsPage.tsx` - Styling, layout

### Components
- ✅ `frontend-player/src/components/*` - All component files
- ✅ Create new components as needed

### Styling
- ✅ All CSS files
- ✅ Tailwind classes
- ✅ Color schemes, fonts, animations

### State Management
- ✅ `frontend-player/src/store/gameStore.ts` - As long as it matches backend event data structures

### Routing
- ✅ Route paths (as long as they match navigation calls)
- ✅ Route guards and redirects

---

## ⚠️ Modify with Caution

### `frontend-player/src/hooks/useGameSocket.ts`
**OK TO:**
- Add new event handlers for new events
- Improve error handling
- Add logging/debugging
- Refactor code structure (as long as event names stay the same)

**NOT OK TO:**
- Change event names (e.g., `'game_started'` → `'gameStart'`)
- Change message names (e.g., `'start_game'` → `'startGame'`)
- Remove existing event handlers
- Change expected data structures
- Change channel join parameters

---

## 🎯 Game Flow (Backend Controlled - Don't Try to Override)

The backend **automatically** handles:
1. ✅ Game progression (rounds advance automatically)
2. ✅ Question generation and broadcasting
3. ✅ Answer reveal timing (all commit OR timer expires)
4. ✅ Scoring calculations
5. ✅ Rematch voting logic
6. ✅ Player removal on rematch decline

**Frontend should:**
- ✅ Display what the backend sends
- ✅ Send user actions to backend
- ✅ React to backend events
- ❌ **NOT** try to control game flow
- ❌ **NOT** try to advance rounds manually
- ❌ **NOT** try to reveal answers manually

---

## 📋 Quick Checklist Before Frontend Changes

Before making frontend changes, ask:
- [ ] Am I changing any WebSocket event names? → **STOP, DON'T**
- [ ] Am I changing any message names sent to backend? → **STOP, DON'T**
- [ ] Am I changing expected data structures? → **STOP, DON'T**
- [ ] Am I trying to control game flow? → **STOP, DON'T** (backend does this)
- [ ] Am I only changing UI/styling? → **OK, PROCEED**
- [ ] Am I only improving UX/animations? → **OK, PROCEED**
- [ ] Am I only refactoring code (keeping same behavior)? → **OK, PROCEED**

---

## 🔍 How to Verify Your Changes Don't Break Things

1. **Test the full game flow:**
   - Join room → Start game → Answer questions → See results → Rematch

2. **Check browser console:**
   - No WebSocket errors
   - Events are received correctly
   - Messages are sent successfully

3. **Verify event handlers:**
   - All events from backend are handled
   - Data structures match what backend sends

4. **Test edge cases:**
   - Player disconnects
   - Timer expires
   - All players commit early
   - Rematch with 2+ players
   - Rematch with <2 players

---

## 📚 Reference

See `PROJECT_SUMMARY.md` for complete project documentation including:
- Full WebSocket protocol reference
- Event data structures
- Game flow details
- Database schema

---

**Remember**: The backend is the source of truth for game logic. The frontend is a presentation layer that reacts to backend events.

