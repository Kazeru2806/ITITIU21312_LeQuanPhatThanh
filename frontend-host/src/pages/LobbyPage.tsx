import { useEffect, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { useDisplayStore } from '../store/displayStore';
import { useDisplaySocket } from '../hooks/useDisplaySocket';

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
    onPlayerJoined: (data) => {
      if (data.players) {
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
    <div className="min-h-screen flex items-center justify-center bg-gradient-to-br from-pink-100 via-purple-100 to-orange-100 p-4">
      <div className="bg-white rounded-3xl shadow-2xl p-12 max-w-4xl w-full">
        <h1 className="text-5xl font-bold text-center mb-8 bg-gradient-to-r from-pink-500 via-purple-500 to-orange-500 bg-clip-text text-transparent">
          Phòng chờ
        </h1>

        {/* Room Code Display */}
        <div className="text-center mb-12">
          <p className="text-xl text-gray-600 mb-4">Mã phòng</p>
          <div className="flex items-center justify-center gap-4">
            <div className="text-8xl font-black text-purple-600 tracking-wider">
              {roomCode}
            </div>
            <button
              onClick={copyRoomCode}
              className="px-6 py-3 bg-purple-500 text-white rounded-xl hover:bg-purple-600 transition-colors"
            >
              {copied ? 'Đã sao chép!' : 'Sao chép'}
            </button>
          </div>
          <p className="text-gray-500 mt-4">
            Người chơi nhập mã này để tham gia
          </p>
        </div>

        {/* Players List */}
        <div className="mb-8">
          <h2 className="text-2xl font-bold mb-4 text-center">
            Người chơi ({players.length})
          </h2>
          <div className="space-y-3">
            {players.length === 0 ? (
              <p className="text-center text-gray-500 py-8">
                Đang chờ người chơi tham gia...
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
                          (Chủ phòng)
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
              ? 'Đang chờ người chơi tham gia...'
              : players.length === 1
              ? 'Chờ thêm người chơi hoặc người chơi đầu tiên bắt đầu trò chơi'
              : 'Người chơi đầu tiên có thể bắt đầu trò chơi'}
          </p>
        </div>
      </div>
    </div>
  );
}

