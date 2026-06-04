import type { CreateRoomResponse, JoinRoomResponse, Room } from '../types/game';
import { getApiBaseUrl } from './backendConfig';

class ApiClient {
  private get baseUrl() {
    return getApiBaseUrl();
  }

  private async request<T>(endpoint: string, options: RequestInit = {}): Promise<T> {
    const url = `${this.baseUrl}${endpoint}`;

    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), 30000);

    let response: Response;
    try {
      response = await fetch(url, {
        ...options,
        signal: controller.signal,
        headers: {
          'Content-Type': 'application/json',
          ...options.headers,
        },
      });
    } catch (err) {
      if ((err as Error).name === 'AbortError') {
        throw new Error(
          `Server timeout reaching ${this.baseUrl}. Check backend on port 4000 and open http://192.168.64.2:5173 (not localhost).`
        );
      }
      throw new Error(`Failed to reach ${this.baseUrl}. Is the backend running?`);
    } finally {
      clearTimeout(timeout);
    }

    if (!response.ok) {
      const error = await response.json().catch(() => ({ error: 'Request failed' }));
      throw new Error(error.error || `HTTP ${response.status}`);
    }

    return response.json();
  }

  async createRoom(config?: {
    total_rounds?: number;
    max_players?: number;
  }): Promise<CreateRoomResponse> {
    return this.request<CreateRoomResponse>('/rooms', {
      method: 'POST',
      body: JSON.stringify(config || {}),
    });
  }

  async getRoom(roomCode: string): Promise<{ success: boolean; room: Room }> {
    return this.request<{ success: boolean; room: Room }>(`/rooms/${roomCode.toUpperCase()}`);
  }

  async joinRoom(
    roomCode: string,
    nickname: string,
    playerId?: string | null
  ): Promise<JoinRoomResponse> {
    const body: { nickname: string; player_id?: string } = { nickname };
    if (playerId) body.player_id = playerId;

    return this.request<JoinRoomResponse>(`/rooms/${roomCode.toUpperCase()}/join`, {
      method: 'POST',
      body: JSON.stringify(body),
    });
  }

  async getPlayers(roomCode: string): Promise<{ success: boolean; players: any[] }> {
    return this.request<{ success: boolean; players: any[] }>(
      `/rooms/${roomCode.toUpperCase()}/players`
    );
  }

  async closeRoom(roomCode: string): Promise<{ success: boolean; closed: boolean }> {
    return this.request<{ success: boolean; closed: boolean }>(
      `/rooms/${roomCode.toUpperCase()}/close`,
      { method: 'POST', body: '{}' }
    );
  }
}

export const api = new ApiClient();
