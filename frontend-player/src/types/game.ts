// Game state types
export type GameState = 
  | 'lobby' 
  | 'round_start' 
  | 'answering' 
  | 'commit_locked' 
  | 'revealing' 
  | 'scoring' 
  | 'round_end' 
  | 'game_end';

// Player data
export interface Player {
  id: string;
  nickname: string;
  score: number;
  connected: boolean;
  is_host: boolean;
}

// Room data
export interface Room {
  room_code: string;
  state: GameState;
  current_round: number;
  total_rounds: number;
  players: Player[];
  started_at?: string;
}

// Question data
export interface Question {
  id: string;
  text: string;
  options: string[];
  correct: string;
  time_limit: number;
}

// Answer commit
export interface AnswerCommit {
  answer: string;
  commit_hash: string;
  salt: string;
  committed_at: string;
}

// Score update
export interface ScoreUpdate {
  player_id: string;
  is_correct: boolean;
  points: number;
}

// Leaderboard entry
export interface LeaderboardEntry {
  player_id: string;
  nickname: string;
  score: number;
}

// WebSocket message types
export interface WebSocketMessage {
  topic: string;
  event: string;
  payload: any;
  ref?: number;
}

// API Response types
export interface ApiResponse<T> {
  success: boolean;
  data?: T;
  error?: string;
  errors?: Record<string, string[]>;
}

export interface CreateRoomResponse {
  room: {
    id: string;
    code: string;
    state: GameState;
    max_players: number;
    total_rounds: number;
  };
}

export interface JoinRoomResponse {
  player: {
    id: string;
    nickname: string;
    is_host: boolean;
    room_code: string;
  };
}