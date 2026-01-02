import type { CreateRoomResponse, JoinRoomResponse, Room } from '../types/game';

const API_BASE_URL = import.meta.env.VITE_API_URL || 'http://localhost:4000/api';

class ApiClient {
  private baseUrl: string;

  constructor(baseUrl: string = API_BASE_URL) {
    this.baseUrl = baseUrl;
  }

  private async request<T>(
    endpoint: string,
    options: RequestInit = {}
  ): Promise<T> {
    const url = `${this.baseUrl}${endpoint}`;
    
    const response = await fetch(url, {
      ...options,
      headers: {
        'Content-Type': 'application/json',
        ...options.headers,
      },
    });

    if (!response.ok) {
      const error = await response.json().catch(() => ({ error: 'Request failed' }));
      throw new Error(error.error || `HTTP ${response.status}`);
    }

    return response.json();
  }

  // Create a new room
  async createRoom(config?: {
    total_rounds?: number;
    max_players?: number;
  }): Promise<CreateRoomResponse> {
    return this.request<CreateRoomResponse>('/rooms', {
      method: 'POST',
      body: JSON.stringify(config || {}),
    });
  }

  // Get room information
  async getRoom(roomCode: string): Promise<{ success: boolean; room: Room }> {
    return this.request<{ success: boolean; room: Room }>(`/rooms/${roomCode.toUpperCase()}`);
  }

  // Join a room
  async joinRoom(
    roomCode: string,
    nickname: string
  ): Promise<JoinRoomResponse> {
    return this.request<JoinRoomResponse>(`/rooms/${roomCode.toUpperCase()}/join`, {
      method: 'POST',
      body: JSON.stringify({ nickname }),
    });
  }

  // Get players in a room
  async getPlayers(roomCode: string): Promise<{ success: boolean; players: any[] }> {
    return this.request<{ success: boolean; players: any[] }>(
      `/rooms/${roomCode.toUpperCase()}/players`
    );
  }
}

export const api = new ApiClient();