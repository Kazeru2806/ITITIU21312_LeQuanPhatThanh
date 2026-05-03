import { useEffect } from 'react';
import { useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { useDisplayStore } from '../store/displayStore';
import { useDisplaySocket } from '../hooks/useDisplaySocket';
import { api } from '../lib/api';

export function ResultsPage() {
  const navigate = useNavigate();
  const roomCode = useDisplayStore((state) => state.roomCode);
  const leaderboard = useDisplayStore((state) => state.leaderboard);
  const winner = useDisplayStore((state) => state.winner);
  const reset = useDisplayStore((state) => state.reset);
  const setGameState = useDisplayStore((state) => state.setGameState);
  const setPlayers = useDisplayStore((state) => state.setPlayers);
  const [audit, setAudit] = useState<Array<{
    seq: number;
    chain_hash: string;
    tx_hash: string | null;
    status: string;
  }>>([]);

  useEffect(() => {
    const loadAudit = async () => {
      if (!roomCode) return;
      try {
        const res = await api.getAudit(roomCode);
        if (res.success) {
          setAudit(
            (res.anchors || []).map((a) => ({
              seq: a.seq,
              chain_hash: a.chain_hash,
              tx_hash: a.tx_hash,
              status: a.status,
            }))
          );
        }
      } catch {
        // Keep results usable even if audit API temporarily fails.
      }
    };

    loadAudit();
  }, [roomCode]);

  useEffect(() => {
    if (!roomCode) {
      navigate('/');
    }
  }, [roomCode, navigate]);

  useDisplaySocket({
    roomCode: roomCode || '',
    onGameState: (state) => {
      setGameState(state.state);
      if (state.players) setPlayers(state.players);
      if (state.state === 'lobby') {
        navigate('/lobby');
      }
    },
    onPlayerJoined: (data) => {
      if (data.players) setPlayers(data.players);
    },
    onRematchApproved: () => {
      setGameState('lobby');
      navigate('/lobby');
    },
    onRematchCancelled: (data) => {
      if (data?.kick_to_home) {
        reset();
        navigate('/');
      } else {
        setGameState('lobby');
        navigate('/lobby');
      }
    },
  });

  const handleNewGame = () => {
    reset();
    navigate('/');
  };

  return (
    <div className="min-h-screen bg-gradient-to-br from-purple-50 via-pink-50 to-orange-50 p-4 lg:p-8">
      <div className="max-w-6xl mx-auto">
        <div className="bg-white rounded-3xl shadow-2xl p-12 border-4 border-purple-200">
          {/* Winner Celebration */}
          {winner && (
            <div className="text-center mb-12">
              <h1 className="text-7xl font-black mb-4 bg-gradient-to-r from-pink-500 via-purple-500 to-orange-500 bg-clip-text text-transparent">
                WINNER
              </h1>
              <h2 className="text-5xl font-bold text-purple-600 mb-2">
                {winner.nickname}
              </h2>
              <p className="text-3xl text-gray-600">
                Champion with {winner.score} points
              </p>
            </div>
          )}

          {/* Final Leaderboard */}
          <div className="mb-12">
            <h2 className="text-4xl font-bold text-center mb-8 text-purple-600">
              Final Leaderboard
            </h2>
            <div className="space-y-4">
              {leaderboard.map((entry, index) => {
                const isWinner = index === 0;
                return (
                  <div
                    key={entry.player_id}
                    className={`p-6 rounded-xl border-4 ${
                      isWinner
                        ? 'bg-gradient-to-r from-yellow-100 to-orange-100 border-yellow-400 scale-105'
                        : 'bg-gradient-to-r from-purple-50 to-pink-50 border-purple-300'
                    }`}
                  >
                    <div className="flex items-center justify-between">
                      <div className="flex items-center gap-6">
                        <div
                          className={`w-16 h-16 rounded-full flex items-center justify-center text-white font-black text-2xl ${
                            isWinner
                              ? 'bg-gradient-to-r from-yellow-400 to-orange-500'
                              : 'bg-gradient-to-r from-pink-500 to-purple-500'
                          }`}
                        >
                          {index === 0 ? '👑' : index + 1}
                        </div>
                        <div>
                          <p className="text-3xl font-bold">{entry.nickname}</p>
                          {isWinner && (
                            <p className="text-lg text-yellow-600 font-semibold">Winner</p>
                          )}
                        </div>
                      </div>
                      <div className="text-right">
                        <p className="text-4xl font-black text-purple-600">{entry.score}</p>
                        <p className="text-lg text-gray-600">points</p>
                      </div>
                    </div>
                  </div>
                );
              })}
            </div>
          </div>

          {/* Blockchain Audit Trail */}
          <div className="mb-10 bg-gradient-to-r from-purple-50 to-pink-50 rounded-2xl p-6 border-2 border-purple-200">
            <h3 className="text-2xl font-black text-purple-700 mb-3">Blockchain Audit Trail</h3>
            <p className="text-gray-600 mb-4">
              Every game event is hash-chained and anchored. Use transaction hashes as tamper-proof fairness evidence.
            </p>
            {audit.length === 0 ? (
              <p className="text-gray-500">No anchors available yet.</p>
            ) : (
              <div className="space-y-2 max-h-80 overflow-auto pr-1">
                {audit.slice(-12).reverse().map((a) => (
                  <div key={`${a.seq}-${a.chain_hash}`} className="bg-white rounded-xl border border-purple-100 p-3">
                    <div className="flex items-center justify-between gap-4">
                      <p className="font-bold text-purple-700">Event #{a.seq}</p>
                      <span className={`text-xs font-bold px-2 py-1 rounded-full ${
                        a.status === 'anchored'
                          ? 'bg-green-100 text-green-700'
                          : a.status === 'failed'
                          ? 'bg-red-100 text-red-700'
                          : 'bg-yellow-100 text-yellow-700'
                      }`}>
                        {a.status}
                      </span>
                    </div>
                    <p className="text-xs text-gray-500 mt-1 break-all">Chain hash: {a.chain_hash}</p>
                    {a.tx_hash ? <p className="text-xs text-gray-500 break-all">Tx hash: {a.tx_hash}</p> : null}
                  </div>
                ))}
              </div>
            )}
          </div>

          {/* Action Buttons */}
          <div className="text-center">
            <button
              onClick={handleNewGame}
              className="px-12 py-6 bg-gradient-to-r from-pink-500 via-purple-500 to-orange-500 text-white text-2xl font-bold rounded-2xl shadow-lg hover:shadow-xl transition-all duration-300 hover:scale-105"
            >
              Create New Room
            </button>
          </div>

          <p className="text-center text-gray-600 mt-6 text-xl">
            Thanks for hosting VN Party.
          </p>
        </div>
      </div>
    </div>
  );
}


