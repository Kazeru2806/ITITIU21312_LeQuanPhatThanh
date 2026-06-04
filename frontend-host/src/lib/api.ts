import type { CreateRoomResponse, Room, Player } from '../types/game';
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
          `Server timeout reaching ${this.baseUrl}. Check backend on port 4000 and open the app via http://192.168.64.2:5174 (not localhost).`
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
    mode?: 'classic' | 'truth_collapse';
  }): Promise<CreateRoomResponse> {
    return this.request<CreateRoomResponse>('/rooms', {
      method: 'POST',
      body: JSON.stringify(config || {}),
    });
  }

  async getRoom(roomCode: string): Promise<{ success: boolean; room: Room }> {
    return this.request<{ success: boolean; room: Room }>(`/rooms/${roomCode.toUpperCase()}`);
  }

  async getPlayers(roomCode: string): Promise<{ success: boolean; players: Player[] }> {
    return this.request<{ success: boolean; players: Player[] }>(
      `/rooms/${roomCode.toUpperCase()}/players`
    );
  }

  async closeRoom(roomCode: string): Promise<{ success: boolean; closed: boolean }> {
    return this.request<{ success: boolean; closed: boolean }>(
      `/rooms/${roomCode.toUpperCase()}/close`,
      { method: 'POST', body: '{}' }
    );
  }

  async getAudit(roomCode: string): Promise<{
    success: boolean;
    room_code: string;
    anchors: Array<{
      seq: number;
      event_hash: string;
      prev_chain_hash: string | null;
      chain_hash: string;
      tx_hash: string | null;
      status: string;
      inserted_at: string;
    }>;
  }> {
    return this.request(`/rooms/${roomCode.toUpperCase()}/audit`);
  }
}

export const api = new ApiClient();
