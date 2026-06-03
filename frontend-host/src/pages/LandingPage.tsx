import { useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { api } from '../lib/api';
import { useDisplayStore } from '../store/displayStore';
import { PhoThePhoenix } from '../components/PhoThePhoenix';
import { HostPageShell, HostSubtitle, HostTitle } from '../components/HostPageShell';
import { Card } from '../components/ui/card';
import { Button } from '../components/ui/button';
import { getApiBaseUrl } from '../lib/backendConfig';

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

      setRoomCode(roomResponse.room.code);
      navigate('/lobby');
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to create room');
    } finally {
      setLoading(false);
    }
  };

  return (
    <HostPageShell>
      <div className="flex flex-col items-center justify-center min-h-screen px-4 py-8">
        <HostTitle>VN PARTY</HostTitle>
        <p
          className="text-center mb-6"
          style={{
            fontFamily: "'Bangers', cursive",
            fontSize: 'clamp(1.5rem, 5vw, 2.5rem)',
            color: '#FF9E3D',
            textShadow: '3px 3px 0px #FF6B9D',
          }}
        >
          Host Command Center
        </p>

        <div className="mb-8">
          <PhoThePhoenix className="w-40 h-48 md:w-52 md:h-60 drop-shadow-2xl" />
        </div>

        <HostSubtitle>
          Create a room, share the code, and run the game on the big screen.
        </HostSubtitle>

        <Card
          className="w-full max-w-xl p-8 bg-white/95 backdrop-blur shadow-2xl border-4 border-purple-500"
          style={{ borderRadius: '2rem' }}
        >
          {error && (
            <div className="p-4 mb-6 bg-red-50 border-2 border-red-300 rounded-xl text-red-700 font-semibold">
              {error}
            </div>
          )}

          <p className="text-sm font-bold text-gray-700 mb-3 text-center uppercase tracking-wider">
            Game mode
          </p>
          <div className="grid grid-cols-2 gap-3 mb-8">
            <button
              type="button"
              onClick={() => setMode('classic')}
              disabled={loading}
              className={`py-4 rounded-xl border-2 font-bold transition-all ${
                mode === 'classic'
                  ? 'border-purple-500 bg-purple-50 text-purple-700 scale-105'
                  : 'border-gray-200 bg-white text-gray-600 hover:border-purple-300'
              }`}
            >
              Classic Trivia
            </button>
            <button
              type="button"
              onClick={() => setMode('truth_collapse')}
              disabled={loading}
              className={`py-4 rounded-xl border-2 font-bold transition-all ${
                mode === 'truth_collapse'
                  ? 'border-pink-500 bg-pink-50 text-pink-700 scale-105'
                  : 'border-gray-200 bg-white text-gray-600 hover:border-pink-300'
              }`}
            >
              Truth Collapse
            </button>
          </div>

          <Button
            onClick={handleCreateRoom}
            disabled={loading}
            className="w-full py-7 rounded-2xl text-xl font-bold text-white border-[3px] border-[#2D1B3D] shadow-lg hover:scale-105 transition-transform disabled:opacity-50 disabled:hover:scale-100"
            style={{
              fontFamily: "'Fredoka', sans-serif",
              background: loading
                ? '#E5E5E5'
                : 'linear-gradient(135deg, #FF6B9D 0%, #9D4EDD 100%)',
            }}
          >
            {loading ? 'Creating room…' : `Create room (${mode === 'truth_collapse' ? 'Truth Collapse' : 'Classic'})`}
          </Button>

          <p className="text-center text-gray-500 mt-6 text-sm">
            Open player app at the same server, enter the room code to join.
          </p>
          {import.meta.env.DEV && (
            <p className="text-center text-xs text-gray-400 mt-2 break-all">
              API: {getApiBaseUrl()}
            </p>
          )}
        </Card>
      </div>
    </HostPageShell>
  );
}
