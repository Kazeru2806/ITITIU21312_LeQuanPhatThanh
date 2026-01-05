import { useEffect, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { useDisplayStore } from '../store/displayStore';
import { useDisplaySocket } from '../hooks/useDisplaySocket';

export function GameDisplayPage() {
  const navigate = useNavigate();
  const roomCode = useDisplayStore((state) => state.roomCode);
  const currentRound = useDisplayStore((state) => state.currentRound);
  const totalRounds = useDisplayStore((state) => state.totalRounds);
  const currentQuestion = useDisplayStore((state) => state.currentQuestion);
  const players = useDisplayStore((state) => state.players);
  const timeLeft = useDisplayStore((state) => state.timeLeft);
  const roundScores = useDisplayStore((state) => state.roundScores);
  const leaderboard = useDisplayStore((state) => state.leaderboard);
  
  const setQuestion = useDisplayStore((state) => state.setQuestion);
  const setTimeLeft = useDisplayStore((state) => state.setTimeLeft);
  const setRound = useDisplayStore((state) => state.setRound);
  const setPlayers = useDisplayStore((state) => state.setPlayers);
  const setRoundScores = useDisplayStore((state) => state.setRoundScores);
  const setLeaderboard = useDisplayStore((state) => state.setLeaderboard);
  const setGameState = useDisplayStore((state) => state.setGameState);
  const setWinner = useDisplayStore((state) => state.setWinner);

  const [localTimeLeft, setLocalTimeLeft] = useState(15);
  const [committedPlayers, setCommittedPlayers] = useState<Set<string>>(new Set());

  useEffect(() => {
    if (!roomCode) {
      navigate('/');
    }
  }, [roomCode, navigate]);

  // Timer countdown
  useEffect(() => {
    if (!currentQuestion) return;

    setLocalTimeLeft(timeLeft);
    const timer = setInterval(() => {
      setLocalTimeLeft((prev) => {
        if (prev <= 1) {
          clearInterval(timer);
          return 0;
        }
        return prev - 1;
      });
    }, 1000);

    return () => clearInterval(timer);
  }, [currentQuestion, timeLeft]);

  useDisplaySocket({
    roomCode: roomCode || '',
    onGameState: (state) => {
      if (state.players) setPlayers(state.players);
      setGameState(state.state);
      if (state.current_round && state.total_rounds) {
        setRound(state.current_round, state.total_rounds);
      }
      if (state.current_question) {
        setQuestion(state.current_question);
        setTimeLeft(state.current_question.time_limit);
      }
    },
    onPlayerJoined: (data) => {
      if (data.players) setPlayers(data.players);
    },
    onQuestionRevealed: (question) => {
      setQuestion(question);
      setTimeLeft(question.time_limit);
      setLocalTimeLeft(question.time_limit);
      setCommittedPlayers(new Set());
      setRoundScores(null);
    },
    onPlayerCommitted: (data) => {
      setCommittedPlayers((prev) => new Set([...prev, data.player_id]));
    },
    onRoundScored: (data) => {
      setRoundScores(data.scores);
      setLeaderboard(data.leaderboard);
      setTimeLeft(0);
      setLocalTimeLeft(0);
    },
    onRoundStarted: (data) => {
      setRound(data.round, data.total_rounds);
      setRoundScores(null);
      setCommittedPlayers(new Set());
    },
    onGameEnded: (data) => {
      setLeaderboard(data.final_scores);
      if (data.winner) setWinner(data.winner);
      setGameState('game_end');
      setTimeout(() => navigate('/results'), 2000);
    },
  });

  if (!roomCode) return null;

  const getPlayerName = (playerId: string) => {
    return players.find(p => p.id === playerId)?.nickname || 'Unknown';
  };

  const getOptionText = (optionId: string) => {
    if (!currentQuestion) return optionId;
    if (Array.isArray(currentQuestion.options)) {
      const option = currentQuestion.options.find((opt: any) => 
        typeof opt === 'object' ? opt.id === optionId : opt === optionId
      );
      return typeof option === 'object' ? option.text : option;
    }
    return optionId;
  };

  return (
    <div className="min-h-screen bg-gradient-to-br from-pink-100 via-purple-100 to-orange-100 p-4 lg:p-8">
      <div className="max-w-7xl mx-auto">
        {/* Header */}
        <div className="flex justify-between items-center mb-6">
          <div className="bg-white px-8 py-4 rounded-full text-purple-700 font-black text-2xl shadow-lg border-4 border-purple-300">
            Vòng {currentRound}/{totalRounds}
          </div>
          <div className="bg-white px-8 py-4 rounded-full text-pink-700 font-black text-xl shadow-lg border-4 border-pink-300">
            {roomCode}
          </div>
        </div>

        {/* Main Content */}
        {!currentQuestion ? (
          <div className="bg-white rounded-3xl shadow-2xl p-16 text-center">
            <h2 className="text-5xl font-black mb-4 text-purple-600">Đang chuẩn bị câu hỏi...</h2>
            <p className="text-2xl text-gray-600">Vui lòng chờ...</p>
          </div>
        ) : roundScores ? (
          /* Round Results */
          <div className="bg-white rounded-3xl shadow-2xl p-12">
            <h2 className="text-5xl font-black text-center mb-8 text-purple-600">Kết quả vòng {currentRound}</h2>
            
            <div className="mb-8">
              <p className="text-3xl font-bold text-center mb-4">
                Đáp án đúng: <span className="text-green-600">{currentQuestion.correct}</span>
              </p>
              <p className="text-xl text-center text-gray-600 mb-8">
                {getOptionText(currentQuestion.correct)}
              </p>
            </div>

            <div className="space-y-4 mb-8">
              {roundScores.map((score) => (
                <div
                  key={score.player_id}
                  className={`p-6 rounded-xl border-4 ${
                    score.is_correct
                      ? 'bg-green-50 border-green-400'
                      : 'bg-red-50 border-red-400'
                  }`}
                >
                  <div className="flex items-center justify-between">
                    <div className="flex items-center gap-4">
                      <div className={`w-12 h-12 rounded-full flex items-center justify-center text-white font-bold text-xl ${
                        score.is_correct ? 'bg-green-500' : 'bg-red-500'
                      }`}>
                        {score.is_correct ? '✓' : '✗'}
                      </div>
                      <div>
                        <p className="text-2xl font-bold">{getPlayerName(score.player_id)}</p>
                        <p className="text-lg text-gray-600">
                          Đã chọn: {score.answer} - {getOptionText(score.answer)}
                        </p>
                      </div>
                    </div>
                    <div className="text-right">
                      <p className="text-2xl font-bold text-purple-600">+{score.points} điểm</p>
                    </div>
                  </div>
                </div>
              ))}
            </div>

            {/* Leaderboard */}
            <div className="bg-gradient-to-r from-purple-50 to-pink-50 rounded-xl p-6 border-4 border-purple-300">
              <h3 className="text-3xl font-bold mb-4 text-center">Bảng xếp hạng</h3>
              <div className="space-y-2">
                {leaderboard.map((entry, index) => (
                  <div key={entry.player_id} className="flex items-center justify-between p-4 bg-white rounded-lg">
                    <div className="flex items-center gap-4">
                      <div className="w-10 h-10 rounded-full bg-gradient-to-r from-pink-500 to-purple-500 flex items-center justify-center text-white font-bold">
                        {index + 1}
                      </div>
                      <p className="text-xl font-semibold">{entry.nickname}</p>
                    </div>
                    <p className="text-2xl font-bold text-purple-600">{entry.score} điểm</p>
                  </div>
                ))}
              </div>
            </div>
          </div>
        ) : (
          /* Question Display */
          <div className="bg-white rounded-3xl shadow-2xl p-12 border-4 border-purple-300">
            {/* Timer */}
            <div className="flex justify-center mb-8">
              <div className={`w-32 h-32 rounded-full flex items-center justify-center text-6xl font-black transition-all shadow-lg border-4 ${
                localTimeLeft > 10
                  ? 'bg-gradient-to-br from-green-400 to-emerald-500 text-white border-green-300'
                  : localTimeLeft > 5
                  ? 'bg-gradient-to-br from-yellow-400 to-orange-500 text-white border-yellow-300'
                  : 'bg-gradient-to-br from-red-400 to-pink-500 text-white border-red-300 animate-pulse'
              }`}>
                {localTimeLeft}
              </div>
            </div>

            {/* Question Text */}
            <div className="text-center mb-12">
              <h2 className="text-5xl lg:text-6xl font-black mb-6 text-purple-600" style={{ fontFamily: "'Bangers', cursive" }}>
                {currentQuestion.text}
              </h2>
            </div>

            {/* Answer Options */}
            <div className="grid grid-cols-2 gap-6 mb-8">
              {currentQuestion.options.map((option, index) => {
                const optionId = typeof option === 'object' ? option.id : ['A', 'B', 'C', 'D'][index];
                const optionText = typeof option === 'object' ? option.text : option;
                const isCorrect = optionId === currentQuestion.correct;
                
                return (
                  <div
                    key={optionId}
                    className={`p-8 rounded-2xl border-4 text-center transition-all ${
                      isCorrect && roundScores
                        ? 'bg-green-100 border-green-500 scale-105'
                        : 'bg-gradient-to-br from-purple-50 to-pink-50 border-purple-300 hover:scale-105'
                    }`}
                  >
                    <div className="text-4xl font-black text-purple-600 mb-2">{optionId}</div>
                    <div className="text-2xl font-semibold">{optionText}</div>
                  </div>
                );
              })}
            </div>

            {/* Player Status */}
            <div className="bg-gradient-to-r from-purple-50 to-pink-50 rounded-xl p-6 border-4 border-purple-300">
              <h3 className="text-2xl font-bold mb-4 text-center">
                Trạng thái người chơi ({committedPlayers.size}/{players.length})
              </h3>
              <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
                {players.map((player) => (
                  <div
                    key={player.id}
                    className={`p-4 rounded-lg text-center ${
                      committedPlayers.has(player.id)
                        ? 'bg-green-100 border-2 border-green-500'
                        : 'bg-gray-100 border-2 border-gray-300'
                    }`}
                  >
                    <p className="font-semibold">{player.nickname}</p>
                    <p className="text-sm">
                      {committedPlayers.has(player.id) ? '✓ Đã trả lời' : '⏳ Đang chờ...'}
                    </p>
                  </div>
                ))}
              </div>
            </div>
          </div>
        )}
      </div>
    </div>
  );
}

