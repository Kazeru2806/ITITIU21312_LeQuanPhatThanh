import { useEffect, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { useGameStore } from '../store/gameStore';
import { useGameSocket } from '../hooks/useGameSocket';

export function GamePage() {
    const navigate = useNavigate();
    const [timeLeft, setTimeLeft] = useState(15);
    const [showResult, setShowResult] = useState(false);
    const [isCorrect, setIsCorrect] = useState(false);

    const {
        playerId,
        roomCode,
        nickname,
        currentRound,
        totalRounds,
        currentQuestion,
        selectedAnswer,
        hasCommitted,
        players,
        setQuestion,
        setSelectedAnswer,
        setHasCommitted,
        setRound,
        updatePlayer,
    } = useGameStore();

    useEffect(() => {
        if (!playerId || !roomCode || !nickname) {
            navigate('/');
        }
    }, [playerId, roomCode, nickname, navigate]);

    const { commitAnswer } = useGameSocket({
        roomCode: roomCode || '',
        playerId: playerId || '',
        nickname: nickname || '',
        onGameStarted: (data) => {
            console.log('🎮 Game started in GamePage:', data);
            setRound(data.round, data.total_rounds);
            setQuestion(null);
            setShowResult(false);
            setHasCommitted(false);
            setSelectedAnswer(null);
        },
        onQuestionRevealed: (question) => {
            console.log('❓ Question revealed:', question);
            setQuestion(question);
            setTimeLeft(question.time_limit);
            setShowResult(false);
            setIsCorrect(false);
        },
        onPlayerCommitted: (data) => {
            console.log('Player committed:', data);
        },
        onRoundScored: (data) => {
            const myScore = data.scores.find(s => s.player_id === playerId);
            if (myScore) {
                setIsCorrect(myScore.is_correct);
                setShowResult(true);
            }

            // Update all player scores from leaderboard
            if (data.leaderboard && Array.isArray(data.leaderboard)) {
                // Update each player's score in the store
                data.leaderboard.forEach(leaderboardEntry => {
                    const player = players.find(p => p.id === leaderboardEntry.player_id);
                    if (player) {
                        updatePlayer(leaderboardEntry.player_id, { score: leaderboardEntry.score });
                    }
                });
            }

            // Update the correct answer if provided
            if (data.correct_answer && currentQuestion) {
                setQuestion({
                    ...currentQuestion,
                    correct: data.correct_answer
                });
            }
        },
        onRoundStarted: (data) => {
            setRound(data.round, data.total_rounds);
            setQuestion(null);
            setShowResult(false);
            setHasCommitted(false);
            setSelectedAnswer(null);
        },
        onGameEnded: () => {
            console.log('🎉 Game ended! Navigating to results...');
            // Small delay to let players see final scores
            setTimeout(() => {
                navigate('/results');
            }, 2000);
        },
    });

    // Timer countdown
    useEffect(() => {
        if (!currentQuestion || hasCommitted) return;

        const timer = setInterval(() => {
            setTimeLeft((prev) => {
                if (prev <= 1) {
                    clearInterval(timer);
                    return 0;
                }
                return prev - 1;
            });
        }, 1000);

        return () => clearInterval(timer);
    }, [currentQuestion, hasCommitted]);

    // Questions are now automatically requested by the server

    const handleSelectAnswer = (answer: string) => {
        if (hasCommitted || timeLeft === 0) return;
        setSelectedAnswer(answer);
    };

    const handleSubmit = async () => {
        if (!selectedAnswer || !currentQuestion) return;

        try {
            await commitAnswer(selectedAnswer, currentQuestion.id);
            setHasCommitted(true);
        } catch (err) {
            console.error('Failed to commit answer:', err);
        }
    };

    // Rounds now advance automatically - no manual controls needed

    if (!playerId || !roomCode) {
        return null;
    }

    return (
        <div className="min-h-screen bg-gradient-to-br from-indigo-600 via-purple-600 to-pink-600 flex flex-col p-4">
            {/* Header */}
            <div className="flex justify-between items-center mb-6">
                <div className="bg-white/20 backdrop-blur-sm px-4 py-2 rounded-full text-white font-semibold">
                    Vòng {currentRound}/{totalRounds}
                </div>
                <div className="bg-white/20 backdrop-blur-sm px-4 py-2 rounded-full text-white font-semibold">
                    {nickname}
                </div>
            </div>

            {/* Main Content */}
            <div className="flex-1 flex items-center justify-center">
                {!currentQuestion ? (
                    <div className="text-center text-white">
                        <div className="text-6xl mb-4">⏳</div>
                        <h2 className="text-2xl font-bold">Đang chuẩn bị câu hỏi...</h2>
                    </div>
                ) : (
                    <div className="w-full max-w-4xl">
                        {/* Question Card */}
                        <div className="bg-white rounded-3xl shadow-2xl p-8 mb-6">
                            {/* Timer */}
                            <div className="flex justify-center mb-6">
                                <div className={`w-20 h-20 rounded-full flex items-center justify-center text-3xl font-bold transition-colors ${timeLeft > 10 ? 'bg-green-100 text-green-600' :
                                        timeLeft > 5 ? 'bg-yellow-100 text-yellow-600' :
                                            'bg-red-100 text-red-600 animate-pulse'
                                    }`}>
                                    {timeLeft}
                                </div>
                            </div>

                            {/* Question Text */}
                            <h2 className="text-2xl font-bold text-center text-gray-800 mb-8">
                                {currentQuestion.text}
                            </h2>

                            {/* Answer Options */}
                            <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
                                {currentQuestion.options.map((option, index) => (
                                    <button
                                        key={index}
                                        onClick={() => handleSelectAnswer(option)}
                                        disabled={hasCommitted || timeLeft === 0}
                                        className={`p-6 rounded-2xl font-semibold text-lg transition-all transform hover:scale-105 ${selectedAnswer === option
                                                ? 'bg-gradient-to-r from-purple-500 to-pink-500 text-white shadow-lg scale-105'
                                                : 'bg-gray-100 text-gray-800 hover:bg-gray-200'
                                            } ${(hasCommitted || timeLeft === 0) && 'opacity-50 cursor-not-allowed hover:scale-100'
                                            } ${showResult && option === currentQuestion.correct
                                                ? 'ring-4 ring-green-400 bg-green-100'
                                                : ''
                                            }`}
                                    >
                                        {option}
                                    </button>
                                ))}
                            </div>

                            {/* Submit Button */}
                            {!hasCommitted && timeLeft > 0 && (
                                <button
                                    onClick={handleSubmit}
                                    disabled={!selectedAnswer}
                                    className="w-full mt-6 bg-gradient-to-r from-green-500 to-emerald-500 text-white py-4 rounded-xl font-bold text-lg hover:shadow-lg transform hover:scale-105 transition-all disabled:opacity-50 disabled:cursor-not-allowed disabled:transform-none"
                                >
                                    {selectedAnswer ? '✓ Xác nhận đáp án' : '⏳ Chọn đáp án'}
                                </button>
                            )}

                            {/* Committed Status */}
                            {hasCommitted && !showResult && (
                                <div className="mt-6 text-center p-4 bg-blue-50 rounded-xl">
                                    <p className="text-blue-700 font-semibold">
                                        ✓ Đã gửi đáp án! Đang chờ người chơi khác...
                                    </p>
                                </div>
                            )}

                            {/* Result */}
                            {showResult && (
                                <div className={`mt-6 text-center p-6 rounded-xl ${isCorrect
                                        ? 'bg-green-50 border-2 border-green-400'
                                        : 'bg-red-50 border-2 border-red-400'
                                    }`}>
                                    <div className="text-4xl mb-2">{isCorrect ? '🎉' : '😢'}</div>
                                    <p className={`text-xl font-bold ${isCorrect ? 'text-green-700' : 'text-red-700'
                                        }`}>
                                        {isCorrect ? 'Chính xác! +100 điểm' : 'Sai rồi!'}
                                    </p>
                                    <p className="text-sm text-gray-600 mt-2">
                                        Đáp án đúng: <strong>{currentQuestion.correct}</strong>
                                    </p>
                                </div>
                            )}
                        </div>

                        {/* Auto-advance message */}
                        {showResult && (
                            <div className="text-center mt-4 p-4 bg-blue-50 rounded-xl">
                                <p className="text-blue-700 font-semibold">
                                    {currentRound < totalRounds 
                                        ? '⏳ Đang chuyển sang câu hỏi tiếp theo...' 
                                        : '🎉 Trò chơi kết thúc! Đang chuyển đến kết quả...'}
                                </p>
                            </div>
                        )}
                    </div>
                )}
            </div>
        </div>
    );
}