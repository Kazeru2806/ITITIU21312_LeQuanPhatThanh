import { create } from 'zustand';

interface DisplayStore {
  roomCode: string | null;
  gameState: 'lobby' | 'round_start' | 'round_end' | 'game_end';
  currentRound: number;
  totalRounds: number;
  players: Player[];
  currentQuestion: Question | null;
  timeLeft: number;
  leaderboard: LeaderboardEntry[];
  roundScores: Array<{
    player_id: string;
    is_correct: boolean;
    points: number;
    answer: string;
  }> | null;
  winner: LeaderboardEntry | null;
  
  setRoomCode: (code: string) => void;
  setGameState: (state: 'lobby' | 'round_start' | 'round_end' | 'game_end') => void;
  setRound: (round: number, total: number) => void;
  setPlayers: (players: Player[]) => void;
  setQuestion: (question: Question | null) => void;
  setTimeLeft: (time: number) => void;
  setLeaderboard: (leaderboard: LeaderboardEntry[]) => void;
  setRoundScores: (scores: Array<{ player_id: string; is_correct: boolean; points: number; answer: string }> | null) => void;
  setWinner: (winner: LeaderboardEntry | null) => void;
  reset: () => void;
}

interface Player {
  id: string;
  nickname: string;
  score: number;
  connected: boolean;
  is_host: boolean;
}

interface Question {
  id: string;
  text: string;
  options: Array<{ id: string; text: string }> | string[];
  correct: string;
  time_limit: number;
}

interface LeaderboardEntry {
  player_id: string;
  nickname: string;
  score: number;
}

export const useDisplayStore = create<DisplayStore>((set) => ({
  roomCode: null,
  gameState: 'lobby',
  currentRound: 0,
  totalRounds: 5,
  players: [],
  currentQuestion: null,
  timeLeft: 15,
  leaderboard: [],
  roundScores: null,
  winner: null,
  
  setRoomCode: (code) => set({ roomCode: code }),
  setGameState: (state) => set({ gameState: state }),
  setRound: (round, total) => set({ currentRound: round, totalRounds: total }),
  setPlayers: (players) => set({ players }),
  setQuestion: (question) => set({ currentQuestion: question }),
  setTimeLeft: (time) => set({ timeLeft: time }),
  setLeaderboard: (leaderboard) => set({ leaderboard }),
  setRoundScores: (scores) => set({ roundScores: scores }),
  setWinner: (winner) => set({ winner }),
  reset: () => set({
    roomCode: null,
    gameState: 'lobby',
    currentRound: 0,
    totalRounds: 5,
    players: [],
    currentQuestion: null,
    timeLeft: 15,
    leaderboard: [],
    roundScores: null,
    winner: null,
  }),
}));


