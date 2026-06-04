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
  status?: 'online' | 'absent';
}

/** Server snapshot for Truth Collapse mid-game reconnect (refresh / rejoin). */
export interface TruthResume {
  round: number;
  phase: string;
  message?: string;
  discussion_seconds?: number;
  question_id?: string;
  category?: string;
  category_label?: string;
  category_timeline?: string[];
  category_timeline_labels?: string[];
  options?: string[];
  shuffle_preview?: string[];
  time_left?: number;
  phase_ends_at_ms?: number;
  results_seconds?: number;
  current_question?: {
    id: string;
    options: string[];
    time_limit: number;
    shuffle_targets?: string[];
  };
  /** Host display only — full question for reconnect during answering. */
  display_question?: Record<string, unknown>;
  /** Host display only — same shape as display:round_scored payload. */
  display_round_scored?: Record<string, unknown>;
  stats?: Array<{ player_id: string; tp: number; di: number; ps: number; charges: number }>;
  mode?: string;
}

// Room data
export interface Room {
  room_code: string;
  state: GameState;
  current_round: number;
  total_rounds: number;
  players: Player[];
  started_at?: string;
  mode?: 'classic' | 'truth_collapse';
  truth_resume?: TruthResume | null;
}

// Question data
export interface Question {
  id: string;
  text?: string;
  options: string[];
  correct?: string;
  time_limit: number;
  shuffle_targets?: string[];
  remove_targets?: Record<string, string[]>;
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