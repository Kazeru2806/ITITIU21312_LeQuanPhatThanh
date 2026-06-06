import { useEffect } from 'react';
import { useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { useDisplayStore } from '../store/displayStore';
import { useDisplaySocket } from '../hooks/useDisplaySocket';
import { api } from '../lib/api';
import { PhoThePhoenix } from '../components/PhoThePhoenix';
import { HostPageShell, HostTitle } from '../components/HostPageShell';
import { Button } from '../components/ui/button';

export function ResultsPage() {
  const navigate = useNavigate();
  const roomCode = useDisplayStore((state) => state.roomCode);
  const leaderboard = useDisplayStore((state) => state.leaderboard);
  const winner = useDisplayStore((state) => state.winner);
  const reset = useDisplayStore((state) => state.reset);
  const setGameState = useDisplayStore((state) => state.setGameState);
  const setPlayers = useDisplayStore((state) => state.setPlayers);
  const [audit, setAudit] = useState<
    Array<{
      seq: number;
      chain_hash: string;
      tx_hash: string | null;
      status: string;
    }>
  >([]);

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
        // optional
      }
    };
    loadAudit();
  }, [roomCode]);

  useEffect(() => {
    if (!roomCode) navigate('/');
  }, [roomCode, navigate]);

  useDisplaySocket({
    roomCode: roomCode || '',
    onGameState: (state) => {
      setGameState(state.state);
      if (state.players) setPlayers(state.players);
      if (state.state === 'lobby') navigate('/lobby');
    },
    onPlayerJoined: (data) => {
      if (data.players) setPlayers(data.players);
    },
    onPlayerDisconnected: (data) => {
      if (data.players) setPlayers(data.players);
    },
    onRematchApproved: () => {
      setGameState('lobby');
      navigate('/lobby', { replace: true });
    },
    onRoomResetToLobby: (data) => {
      if (data?.players) setPlayers(data.players);
      setGameState('lobby');
      navigate('/lobby', { replace: true });
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

  if (!roomCode) return null;

  return (
    <HostPageShell>
      <div className="flex flex-col items-center min-h-screen px-4 py-8">
        <div
          className="bg-white/95 backdrop-blur rounded-3xl shadow-2xl p-8 lg:p-12 w-full max-w-4xl border-4 border-purple-500"
          style={{ borderRadius: '2rem' }}
        >
          <div className="flex justify-center mb-6">
            <PhoThePhoenix className="w-32 h-40 drop-shadow-xl" />
          </div>

          {winner && (
            <div className="text-center mb-10">
              <HostTitle>Nhà Vô Địch</HostTitle>
              <p className="text-4xl font-black text-purple-600 mt-2">{winner.nickname}</p>
              <p className="text-xl text-gray-600 mt-1">{winner.score} điểm</p>
            </div>
          )}

          <h2
            className="text-3xl font-black text-center mb-6"
            style={{ fontFamily: "'Bangers', cursive", color: '#FF9E3D' }}
          >
            Bảng Xếp Hạng Cuối
          </h2>

          <div className="space-y-3 mb-10">
            {leaderboard.map((entry, index) => (
              <div
                key={entry.player_id}
                className={`p-5 rounded-xl border-2 flex items-center justify-between ${
                  index === 0
                    ? 'bg-gradient-to-r from-yellow-50 to-orange-50 border-yellow-400'
                    : 'bg-gradient-to-r from-purple-50 to-pink-50 border-purple-200'
                }`}
              >
                <div className="flex items-center gap-4">
                  <span className="text-2xl font-black text-purple-600 w-8">{index + 1}</span>
                  <span className="text-xl font-bold">{entry.nickname}</span>
                </div>
                <span className="text-2xl font-black text-purple-600">{entry.score}</span>
              </div>
            ))}
          </div>

          {audit.length > 0 && (
            <div className="mb-10 rounded-2xl border-2 border-purple-200 bg-purple-50/50 p-6">
              <h3 className="text-xl font-black text-purple-700 mb-3">Lịch sử kiểm tra blockchain</h3>
              <div className="space-y-2 max-h-48 overflow-auto text-sm">
                {audit.slice(-8).reverse().map((a) => (
                  <div key={`${a.seq}-${a.chain_hash}`} className="bg-white rounded-lg p-2 border border-purple-100">
                    <span className="font-bold text-purple-700">#{a.seq}</span> · {a.status}
                  </div>
                ))}
              </div>
            </div>
          )}

          <div className="text-center">
            <Button
              onClick={handleNewGame}
              className="px-10 py-6 text-xl font-bold text-white border-[3px] border-[#2D1B3D] rounded-2xl"
              style={{ background: 'linear-gradient(135deg, #FF6B9D 0%, #9D4EDD 100%)' }}
            >
              Tạo phòng mới
            </Button>
          </div>
        </div>
      </div>
    </HostPageShell>
  );
}
