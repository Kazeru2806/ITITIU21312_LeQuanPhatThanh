import type { CreateRoomResponse, Room, Player } from '../types/game';

// Use dynamic host so it works when host and backend are on same network
function getApiBaseUrl(): string {
  const hostname = window.location.hostname || 'localhost';
  return `http://${hostname}:4000/api`;
}

const API_BASE_URL = getApiBaseUrl();

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

    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), 10000);

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
        throw new Error('Server timeout. Please make sure backend is running on port 4000.');
      }
      throw new Error('Failed to fetch. Please check backend server status.');
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


