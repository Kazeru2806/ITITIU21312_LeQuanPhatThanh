import { useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { api } from '../lib/api';
import { useDisplayStore } from '../store/displayStore';

export function LandingPage() {
  const navigate = useNavigate();
  const setRoomCode = useDisplayStore((state) => state.setRoomCode);
  
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const handleCreateRoom = async () => {
    setLoading(true);
    setError(null);

    try {
      const roomResponse = await api.createRoom({
        total_rounds: 5,
        max_players: 8,
      });

      const newRoomCode = roomResponse.room.code;
      setRoomCode(newRoomCode);
      navigate('/lobby');
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Không thể tạo phòng');
    } finally {
      setLoading(false);
    }
  };

  return (
    <div className="min-h-screen flex items-center justify-center bg-gradient-to-br from-pink-100 via-purple-100 to-orange-100">
      <div className="bg-white rounded-3xl shadow-2xl p-12 max-w-2xl w-full mx-4">
        <h1 className="text-6xl font-bold text-center mb-8 bg-gradient-to-r from-pink-500 via-purple-500 to-orange-500 bg-clip-text text-transparent">
          VN PARTY
        </h1>
        <p className="text-2xl text-center text-gray-700 mb-8">
          Host Screen
        </p>
        
        {error && (
          <div className="p-4 bg-red-50 border-2 border-red-300 rounded-xl text-red-700 font-semibold mb-6">
            {error}
          </div>
        )}

        <button
          onClick={handleCreateRoom}
          disabled={loading}
          className="w-full py-6 rounded-2xl shadow-lg hover:shadow-xl transition-all duration-300 hover:scale-105 disabled:opacity-50 disabled:cursor-not-allowed text-2xl font-bold text-white bg-gradient-to-r from-pink-500 via-purple-500 to-orange-500"
        >
          {loading ? 'Đang tạo phòng...' : 'TẠO PHÒNG MỚI'}
        </button>

        <p className="text-center text-gray-600 mt-6">
          Tạo phòng và hiển thị mã phòng cho người chơi
        </p>
      </div>
    </div>
  );
}

