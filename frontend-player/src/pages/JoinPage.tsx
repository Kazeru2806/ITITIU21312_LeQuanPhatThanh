import { useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { api } from '../lib/api';
import { useGameStore } from '../store/gameStore';

export function JoinPage() {
  const navigate = useNavigate();
  const setPlayerInfo = useGameStore((state) => state.setPlayerInfo);
  const setRoomCode = useGameStore((state) => state.setRoomCode);
  
  const [mode, setMode] = useState<'join' | 'create'>('join');
  const [roomCode, setRoomCodeInput] = useState('');
  const [nickname, setNickname] = useState('');
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const handleCreateRoom = async () => {
    if (!nickname.trim()) {
      setError('Vui lòng nhập tên của bạn');
      return;
    }

    setLoading(true);
    setError(null);

    try {
      // Create room
      const roomResponse = await api.createRoom({
        total_rounds: 5,
        max_players: 8,
      });

      const newRoomCode = roomResponse.room.code;

      // Join the room
      const joinResponse = await api.joinRoom(newRoomCode, nickname);

      // Update store
      setPlayerInfo(
        joinResponse.player.id,
        joinResponse.player.nickname,
        joinResponse.player.is_host
      );
      setRoomCode(newRoomCode);

      // Navigate to lobby
      navigate('/lobby');
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Không thể tạo phòng');
    } finally {
      setLoading(false);
    }
  };

  const handleJoinRoom = async () => {
    if (!nickname.trim()) {
      setError('Vui lòng nhập tên của bạn');
      return;
    }

    if (!roomCode.trim()) {
      setError('Vui lòng nhập mã phòng');
      return;
    }

    setLoading(true);
    setError(null);

    try {
      const response = await api.joinRoom(roomCode, nickname);

      // Update store
      setPlayerInfo(
        response.player.id,
        response.player.nickname,
        response.player.is_host
      );
      setRoomCode(roomCode.toUpperCase());

      // Navigate to lobby
      navigate('/lobby');
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Không thể tham gia phòng');
    } finally {
      setLoading(false);
    }
  };

  return (
    <div className="min-h-screen bg-gradient-to-br from-purple-600 via-pink-500 to-red-500 flex items-center justify-center p-4">
      <div className="bg-white rounded-3xl shadow-2xl p-8 w-full max-w-md">
        {/* Logo/Title */}
        <div className="text-center mb-8">
          <h1 className="text-4xl font-bold text-gray-800 mb-2">
            🎮 VN Party
          </h1>
          <p className="text-gray-600">Trò chơi trivia Việt Nam</p>
        </div>

        {/* Mode Toggle */}
        <div className="flex gap-2 mb-6 bg-gray-100 rounded-xl p-1">
          <button
            onClick={() => setMode('join')}
            className={`flex-1 py-3 rounded-lg font-semibold transition-all ${
              mode === 'join'
                ? 'bg-white text-purple-600 shadow-md'
                : 'text-gray-600 hover:text-gray-800'
            }`}
          >
            Tham gia
          </button>
          <button
            onClick={() => setMode('create')}
            className={`flex-1 py-3 rounded-lg font-semibold transition-all ${
              mode === 'create'
                ? 'bg-white text-purple-600 shadow-md'
                : 'text-gray-600 hover:text-gray-800'
            }`}
          >
            Tạo phòng
          </button>
        </div>

        {/* Error Message */}
        {error && (
          <div className="mb-4 p-4 bg-red-50 border border-red-200 rounded-lg text-red-700 text-sm">
            {error}
          </div>
        )}

        {/* Form */}
        <div className="space-y-4">
          {/* Nickname Input */}
          <div>
            <label className="block text-sm font-medium text-gray-700 mb-2">
              Tên của bạn
            </label>
            <input
              type="text"
              value={nickname}
              onChange={(e) => setNickname(e.target.value)}
              placeholder="Nhập tên..."
              maxLength={20}
              className="w-full px-4 py-3 border-2 border-gray-200 rounded-xl focus:border-purple-500 focus:outline-none transition-colors"
            />
          </div>

          {/* Room Code Input (only for join mode) */}
          {mode === 'join' && (
            <div>
              <label className="block text-sm font-medium text-gray-700 mb-2">
                Mã phòng
              </label>
              <input
                type="text"
                value={roomCode}
                onChange={(e) => setRoomCodeInput(e.target.value.toUpperCase())}
                placeholder="VD: ABC123"
                maxLength={6}
                className="w-full px-4 py-3 border-2 border-gray-200 rounded-xl focus:border-purple-500 focus:outline-none transition-colors uppercase text-center text-2xl font-bold tracking-wider"
              />
            </div>
          )}

          {/* Submit Button */}
          <button
            onClick={mode === 'create' ? handleCreateRoom : handleJoinRoom}
            disabled={loading}
            className="w-full bg-gradient-to-r from-purple-600 to-pink-500 text-white py-4 rounded-xl font-bold text-lg hover:shadow-lg transform hover:scale-105 transition-all disabled:opacity-50 disabled:cursor-not-allowed disabled:transform-none"
          >
            {loading ? (
              <span className="flex items-center justify-center gap-2">
                <svg className="animate-spin h-5 w-5" viewBox="0 0 24 24">
                  <circle
                    className="opacity-25"
                    cx="12"
                    cy="12"
                    r="10"
                    stroke="currentColor"
                    strokeWidth="4"
                    fill="none"
                  />
                  <path
                    className="opacity-75"
                    fill="currentColor"
                    d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"
                  />
                </svg>
                Đang xử lý...
              </span>
            ) : mode === 'create' ? (
              '🎉 Tạo phòng mới'
            ) : (
              '🚀 Tham gia phòng'
            )}
          </button>
        </div>

        {/* Info */}
        <div className="mt-6 text-center text-sm text-gray-500">
          {mode === 'create' ? (
            <p>Bạn sẽ là chủ phòng và có thể bắt đầu trò chơi</p>
          ) : (
            <p>Nhập mã phòng từ chủ phòng để tham gia</p>
          )}
        </div>
      </div>
    </div>
  );
}