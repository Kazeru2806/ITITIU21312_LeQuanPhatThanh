export interface Room {
  id: string;
  code: string;
  state: 'lobby' | 'round_start' | 'round_end' | 'game_end';
  current_round: number;
  total_rounds: number;
  max_players: number;
  started_at?: string;
  players?: Player[];
  mode?: 'classic' | 'truth_collapse';
}

export interface Player {
  id: string;
  nickname: string;
  score: number;
  connected: boolean;
  is_host: boolean;
}

export interface Question {
  id: string;
  text: string;
  options: Array<{ id: string; text: string }> | string[];
  correct: string | string[];
  time_limit: number;
}

export interface LeaderboardEntry {
  player_id: string;
  nickname: string;
  score: number;
  final_score?: number;
  tp?: number;
  di?: number;
  ps?: number;
}

export interface CreateRoomResponse {
  success: boolean;
  room: Room;
}


