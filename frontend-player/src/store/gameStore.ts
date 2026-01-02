import { create } from 'zustand';
import type { GameState, Player, Question, LeaderboardEntry } from '../types/game';

interface GameStore {
  // Player info
  playerId: string | null;
  nickname: string | null;
  isHost: boolean;
  
  // Room info
  roomCode: string | null;
  gameState: GameState;
  currentRound: number;
  totalRounds: number;
  
  // Players
  players: Player[];
  
  // Current question
  currentQuestion: Question | null;
  selectedAnswer: string | null;
  hasCommitted: boolean;
  
  // Scores
  leaderboard: LeaderboardEntry[];
  
  // Actions
  setPlayerInfo: (playerId: string, nickname: string, isHost: boolean) => void;
  setRoomCode: (code: string) => void;
  setGameState: (state: GameState) => void;
  setRound: (round: number, total: number) => void;
  setPlayers: (players: Player[]) => void;
  addPlayer: (player: Player) => void;
  removePlayer: (playerId: string) => void;
  updatePlayer: (playerId: string, updates: Partial<Player>) => void;
  setQuestion: (question: Question | null) => void;
  setSelectedAnswer: (answer: string | null) => void;
  setHasCommitted: (committed: boolean) => void;
  setLeaderboard: (leaderboard: LeaderboardEntry[]) => void;
  reset: () => void;
}

export const useGameStore = create<GameStore>((set) => ({
  // Initial state
  playerId: null,
  nickname: null,
  isHost: false,
  roomCode: null,
  gameState: 'lobby',
  currentRound: 0,
  totalRounds: 5,
  players: [],
  currentQuestion: null,
  selectedAnswer: null,
  hasCommitted: false,
  leaderboard: [],
  
  // Actions
  setPlayerInfo: (playerId, nickname, isHost) =>
    set({ playerId, nickname, isHost }),
  
  setRoomCode: (code) =>
    set({ roomCode: code }),
  
  setGameState: (state) =>
    set({ gameState: state }),
  
  setRound: (round, total) =>
    set({ currentRound: round, totalRounds: total }),
  
  setPlayers: (players) =>
    set({ players }),
  
  addPlayer: (player) =>
    set((state) => ({
      players: [...state.players.filter(p => p.id !== player.id), player]
    })),
  
  removePlayer: (playerId) =>
    set((state) => ({
      players: state.players.filter(p => p.id !== playerId)
    })),
  
  updatePlayer: (playerId, updates) =>
    set((state) => ({
      players: state.players.map(p =>
        p.id === playerId ? { ...p, ...updates } : p
      )
    })),
  
  setQuestion: (question) =>
    set({ currentQuestion: question, selectedAnswer: null, hasCommitted: false }),
  
  setSelectedAnswer: (answer) =>
    set({ selectedAnswer: answer }),
  
  setHasCommitted: (committed) =>
    set({ hasCommitted: committed }),
  
  setLeaderboard: (leaderboard) =>
    set({ leaderboard }),
  
  reset: () =>
    set({
      playerId: null,
      nickname: null,
      isHost: false,
      roomCode: null,
      gameState: 'lobby',
      currentRound: 0,
      totalRounds: 5,
      players: [],
      currentQuestion: null,
      selectedAnswer: null,
      hasCommitted: false,
      leaderboard: [],
    }),
}));