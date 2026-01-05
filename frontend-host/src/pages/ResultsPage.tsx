import { useEffect } from 'react';
import { useNavigate } from 'react-router-dom';
import { useDisplayStore } from '../store/displayStore';
import { useDisplaySocket } from '../hooks/useDisplaySocket';

export function ResultsPage() {
  const navigate = useNavigate();
  const roomCode = useDisplayStore((state) => state.roomCode);
  const leaderboard = useDisplayStore((state) => state.leaderboard);
  const winner = useDisplayStore((state) => state.winner);
  const reset = useDisplayStore((state) => state.reset);
  const setGameState = useDisplayStore((state) => state.setGameState);
  const setPlayers = useDisplayStore((state) => state.setPlayers);

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
  });

  const handleNewGame = () => {
    reset();
    navigate('/');
  };

  return (
    <div className="min-h-screen bg-gradient-to-br from-pink-100 via-purple-100 to-orange-100 p-4 lg:p-8">
      <div className="max-w-6xl mx-auto">
        <div className="bg-white rounded-3xl shadow-2xl p-12 border-4 border-purple-300">
          {/* Winner Celebration */}
          {winner && (
            <div className="text-center mb-12">
              <h1 className="text-7xl font-black mb-4 bg-gradient-to-r from-pink-500 via-purple-500 to-orange-500 bg-clip-text text-transparent">
                🎉 CHÚC MỪNG! 🎉
              </h1>
              <h2 className="text-5xl font-bold text-purple-600 mb-2">
                {winner.nickname}
              </h2>
              <p className="text-3xl text-gray-600">
                Người chiến thắng với {winner.score} điểm!
              </p>
            </div>
          )}

          {/* Final Leaderboard */}
          <div className="mb-12">
            <h2 className="text-4xl font-bold text-center mb-8 text-purple-600">
              Bảng xếp hạng cuối cùng
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
                            <p className="text-lg text-yellow-600 font-semibold">Người chiến thắng!</p>
                          )}
                        </div>
                      </div>
                      <div className="text-right">
                        <p className="text-4xl font-black text-purple-600">{entry.score}</p>
                        <p className="text-lg text-gray-600">điểm</p>
                      </div>
                    </div>
                  </div>
                );
              })}
            </div>
          </div>

          {/* Action Buttons */}
          <div className="text-center">
            <button
              onClick={handleNewGame}
              className="px-12 py-6 bg-gradient-to-r from-pink-500 via-purple-500 to-orange-500 text-white text-2xl font-bold rounded-2xl shadow-lg hover:shadow-xl transition-all duration-300 hover:scale-105"
            >
              Tạo phòng mới
            </button>
          </div>

          <p className="text-center text-gray-600 mt-6 text-xl">
            Cảm ơn bạn đã chơi VN Party!
          </p>
        </div>
      </div>
    </div>
  );
}


