import type { CreateRoomResponse, Room } from '../types/game';

// Ensure the API base URL always ends with /api
const getApiBaseUrl = () => {
  const envUrl = import.meta.env.VITE_API_URL || 'http://localhost:4000';
  const base = envUrl.replace(/\/$/, '');
  return `${base}/api`;
};

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
}

export const api = new ApiClient();


