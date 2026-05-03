import { useEffect, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { useDisplayStore } from '../store/displayStore';
import { useDisplaySocket } from '../hooks/useDisplaySocket';
import { api } from '../lib/api';

export function LobbyPage() {
  const navigate = useNavigate();
  const roomCode = useDisplayStore((state) => state.roomCode);
  const players = useDisplayStore((state) => state.players);
  const setPlayers = useDisplayStore((state) => state.setPlayers);
  const setGameState = useDisplayStore((state) => state.setGameState);
  const setRound = useDisplayStore((state) => state.setRound);

  const [copied, setCopied] = useState(false);

  useEffect(() => {
    if (!roomCode) {
      navigate('/');
    }
  }, [roomCode, navigate]);

  useDisplaySocket({
    roomCode: roomCode || '',
    onGameState: (state) => {
      if (state.players) {
        setPlayers(state.players);
      }
      setGameState(state.state);
      if (state.state === 'round_start') {
        navigate('/game');
      }
    },
    onPlayerJoined: async (data) => {
      // Fetch players from API (source of truth) - fixes bug where 2nd player
      // join showed only 1 player due to WebSocket broadcast timing/ordering
      const code = useDisplayStore.getState().roomCode;
      if (code) {
        try {
          const res = await api.getPlayers(code);
          if (res.success && res.players) {
            setPlayers(res.players);
            return;
          }
        } catch {
          // Fall through to broadcast payload fallback
        }
      }
      // Fallback: use broadcast payload if API fails or no room code
      if (data.players && Array.isArray(data.players)) {
        setPlayers(data.players);
      }
    },
    onGameStarted: (data) => {
      setRound(data.round, data.total_rounds);
      setGameState('round_start');
      navigate('/game');
    },
  });

  const copyRoomCode = () => {
    if (roomCode) {
      navigator.clipboard.writeText(roomCode);
      setCopied(true);
      setTimeout(() => setCopied(false), 2000);
    }
  };

  return (
    <div className="min-h-screen flex items-center justify-center bg-gradient-to-br from-purple-50 via-pink-50 to-orange-50 p-4">
      <div className="bg-white rounded-3xl shadow-2xl p-12 max-w-5xl w-full border-4 border-purple-200">
        <h1 className="text-6xl font-black text-center mb-8 bg-gradient-to-r from-pink-500 via-purple-500 to-orange-500 bg-clip-text text-transparent">
          Lobby
        </h1>

        {/* Room Code Display */}
        <div className="text-center mb-12">
          <p className="text-xl text-gray-600 mb-4">Room code</p>
          <div className="flex items-center justify-center gap-4">
            <div className="text-8xl font-black text-purple-600 tracking-wider">
              {roomCode}
            </div>
            <button
              onClick={copyRoomCode}
              className="px-6 py-3 bg-purple-500 text-white rounded-xl hover:bg-purple-600 transition-colors"
            >
              {copied ? 'Copied!' : 'Copy'}
            </button>
          </div>
          <p className="text-gray-500 mt-4">Players enter this code to join</p>
        </div>

        {/* Players List */}
        <div className="mb-8">
          <h2 className="text-2xl font-bold mb-4 text-center">
            Players ({players.length})
          </h2>
          <div className="space-y-3">
            {players.length === 0 ? (
              <p className="text-center text-gray-500 py-8">
                Waiting for players to join...
              </p>
            ) : (
              players.map((player, index) => (
                <div
                  key={player.id}
                  className="flex items-center justify-between p-4 bg-gradient-to-r from-pink-50 to-purple-50 rounded-xl border-2 border-purple-200"
                >
                  <div className="flex items-center gap-4">
                    <div className="w-12 h-12 rounded-full bg-gradient-to-r from-pink-500 to-purple-500 flex items-center justify-center text-white font-bold text-xl">
                      {index + 1}
                    </div>
                    <div>
                      <p className="text-xl font-semibold">{player.nickname}</p>
                      {player.is_host && (
                        <span className="text-sm text-purple-600 font-semibold">
                          (Host)
                        </span>
                      )}
                    </div>
                  </div>
                  <div className={`w-3 h-3 rounded-full ${player.connected ? 'bg-green-500' : 'bg-gray-400'}`} />
                </div>
              ))
            )}
          </div>
        </div>

        {/* Waiting Message */}
        <div className="text-center">
          <p className="text-xl text-gray-600">
            {players.length === 0
              ? 'Waiting for players to join...'
              : players.length === 1
              ? 'Waiting for more players (or host can start now)'
              : 'Host can start the game at any time'}
          </p>
        </div>
      </div>
    </div>
  );
}


