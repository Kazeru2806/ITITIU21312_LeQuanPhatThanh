import { useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { api } from '../lib/api';
import { useDisplayStore } from '../store/displayStore';

export function LandingPage() {
  const navigate = useNavigate();
  const setRoomCode = useDisplayStore((state) => state.setRoomCode);
  
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [mode, setMode] = useState<'classic' | 'truth_collapse'>('classic');

  const handleCreateRoom = async () => {
    setLoading(true);
    setError(null);

    try {
      const roomResponse = await api.createRoom({
        total_rounds: mode === 'truth_collapse' ? 8 : 5,
        max_players: 8,
        mode,
      });

      const newRoomCode = roomResponse.room.code;
      setRoomCode(newRoomCode);
      navigate('/lobby');
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to create room');
    } finally {
      setLoading(false);
    }
  };

  return (
    <div className="min-h-screen flex items-center justify-center bg-gradient-to-br from-purple-50 via-pink-50 to-orange-50 px-4">
      <div className="bg-white rounded-3xl shadow-2xl p-12 max-w-3xl w-full border-4 border-purple-200">
        <h1 className="text-7xl font-black text-center mb-3 bg-gradient-to-r from-pink-500 via-purple-500 to-orange-500 bg-clip-text text-transparent">
          VN PARTY
        </h1>
        <p className="text-2xl text-center text-gray-700 mb-2 font-bold">
          Host Screen
        </p>
        <p className="text-center text-gray-500 mb-8">
          Create room, control flow, monitor fairness and blockchain audit trail.
        </p>
        
        {error && (
          <div className="p-4 bg-red-50 border-2 border-red-300 rounded-xl text-red-700 font-semibold mb-6">
            {error}
          </div>
        )}

        <div className="mb-7">
          <p className="text-sm font-semibold text-gray-700 mb-3 text-center uppercase tracking-wider">Game mode</p>
          <div className="grid grid-cols-2 gap-3">
            <button
              type="button"
              onClick={() => setMode('classic')}
              disabled={loading}
              className={`py-3 rounded-xl border-2 font-semibold transition-colors ${
                mode === 'classic'
                  ? 'border-purple-500 bg-purple-50 text-purple-700'
                  : 'border-gray-200 bg-white text-gray-600 hover:border-purple-300'
              }`}
            >
              Classic Trivia
            </button>
            <button
              type="button"
              onClick={() => setMode('truth_collapse')}
              disabled={loading}
              className={`py-3 rounded-xl border-2 font-semibold transition-colors ${
                mode === 'truth_collapse'
                  ? 'border-pink-500 bg-pink-50 text-pink-700'
                  : 'border-gray-200 bg-white text-gray-600 hover:border-pink-300'
              }`}
            >
              Truth Collapse
            </button>
          </div>
        </div>

        <button
          onClick={handleCreateRoom}
          disabled={loading}
          className="w-full py-6 rounded-2xl shadow-lg hover:shadow-xl transition-all duration-300 hover:scale-105 disabled:opacity-50 disabled:cursor-not-allowed text-2xl font-bold text-white bg-gradient-to-r from-pink-500 via-purple-500 to-orange-500"
        >
          {loading ? 'Creating room...' : `CREATE ROOM (${mode === 'truth_collapse' ? 'TRUTH COLLAPSE' : 'CLASSIC'})`}
        </button>

        <p className="text-center text-gray-600 mt-6">Share room code with players to start.</p>
      </div>
    </div>
  );
}


