import { useEffect, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { useGameStore } from '../store/gameStore';
import { useGameSocket } from '../hooks/useGameSocket';
import { PhoThePhoenix } from '../components/PhoThePhoenix';
import { LotusPattern, DragonPattern, LanternPattern, BambooPattern } from '../components/VietnamesePatterns';

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
        <div className="min-h-screen relative overflow-hidden flex flex-col p-4 lg:p-6">
            {/* Decorative Background Patterns */}
            <div className="absolute inset-0 overflow-hidden pointer-events-none">
                <LotusPattern className="absolute top-10 left-10 w-20 h-20 animate-pulse" />
                <LotusPattern className="absolute bottom-20 right-20 w-28 h-28 animate-pulse" style={{ animationDelay: "1s" }} />
                <DragonPattern className="absolute top-1/4 right-10 w-40 h-24 opacity-60" />
                <DragonPattern className="absolute bottom-1/3 left-10 w-40 h-24 opacity-60" />
                <LanternPattern className="absolute top-1/3 left-1/4 w-14 h-20 animate-bounce" style={{ animationDuration: "3s" }} />
                <LanternPattern className="absolute bottom-1/4 right-1/3 w-14 h-20 animate-bounce" style={{ animationDuration: "3.5s" }} />
                <BambooPattern className="absolute top-0 right-0 w-16 h-32 opacity-30" />
                <BambooPattern className="absolute bottom-0 left-0 w-16 h-32 opacity-30" />
            </div>

            {/* Animated Background Blobs */}
            <div className="fixed inset-0 pointer-events-none overflow-hidden -z-10">
                <div 
                    className="absolute rounded-full blur-3xl opacity-20 animate-pulse"
                    style={{
                        width: "400px",
                        height: "400px",
                        background: "radial-gradient(circle, #FF6B9D 0%, transparent 70%)",
                        top: "10%",
                        left: "-10%",
                        animationDuration: "4s"
                    }}
                />
                <div 
                    className="absolute rounded-full blur-3xl opacity-20 animate-pulse"
                    style={{
                        width: "500px",
                        height: "500px",
                        background: "radial-gradient(circle, #9D4EDD 0%, transparent 70%)",
                        bottom: "-10%",
                        right: "-10%",
                        animationDuration: "5s",
                        animationDelay: "1s"
                    }}
                />
                <div 
                    className="absolute rounded-full blur-3xl opacity-20 animate-pulse"
                    style={{
                        width: "350px",
                        height: "350px",
                        background: "radial-gradient(circle, #FF9E3D 0%, transparent 70%)",
                        top: "50%",
                        left: "50%",
                        transform: "translate(-50%, -50%)",
                        animationDuration: "6s",
                        animationDelay: "2s"
                    }}
                />
            </div>

            {/* Header */}
            <div className="flex justify-between items-center mb-6 relative z-10">
                <div className="bg-white/90 backdrop-blur-sm px-6 py-3 lg:px-8 lg:py-4 rounded-full text-purple-700 font-black text-lg lg:text-xl shadow-lg border-2 border-purple-200">
                    Vòng {currentRound}/{totalRounds}
                </div>
                <div className="bg-white/90 backdrop-blur-sm px-6 py-3 lg:px-8 lg:py-4 rounded-full text-pink-700 font-black text-lg lg:text-xl shadow-lg border-2 border-pink-200">
                    {nickname}
                </div>
            </div>

            {/* Main Content */}
            <div className="flex-1 flex items-center justify-center relative z-10">
                {!currentQuestion ? (
                    <div className="text-center text-white">
                        <div className="mb-6 flex justify-center">
                            <PhoThePhoenix className="w-48 h-56 md:w-64 md:h-72 drop-shadow-2xl" />
                        </div>
                        <h2 className="text-3xl lg:text-4xl font-black mb-2" style={{ fontFamily: "'Bangers', cursive" }}>Đang chuẩn bị câu hỏi...</h2>
                        <p className="text-xl lg:text-2xl font-semibold opacity-90">Phở đang suy nghĩ...</p>
                    </div>
                ) : (
                    <div className="w-full max-w-4xl lg:max-w-none lg:w-[95%] lg:max-w-[1600px]">
                        {/* Question Card */}
                        <div className="bg-white/95 backdrop-blur-sm rounded-3xl shadow-2xl p-8 lg:p-12 mb-6" style={{ borderRadius: "2rem", border: "4px solid #9D4EDD" }}>
                                {/* Timer */}
                                <div className="flex justify-center mb-6 lg:mb-8">
                                    <div className={`w-24 h-24 lg:w-32 lg:h-32 rounded-full flex items-center justify-center text-4xl lg:text-5xl font-black transition-all shadow-lg border-4 ${timeLeft > 10 ? 'bg-gradient-to-br from-green-400 to-emerald-500 text-white border-green-300' :
                                            timeLeft > 5 ? 'bg-gradient-to-br from-yellow-400 to-orange-500 text-white border-yellow-300' :
                                                'bg-gradient-to-br from-red-400 to-pink-500 text-white border-red-300 animate-pulse vietnamese-glow'
                                        }`}>
                                        {timeLeft}
                                    </div>
                                </div>

                                {/* Question Text */}
                                <div className="text-center mb-8 lg:mb-10">
                                    <div className="inline-block mb-4 lg:mb-6">
                                        <PhoThePhoenix className="w-24 h-28 drop-shadow-lg" />
                                    </div>
                                    <h2 className="text-3xl lg:text-4xl font-black mb-2 lg:mb-4" style={{
                                        fontFamily: "'Bangers', cursive",
                                        color: "#9D4EDD",
                                        textShadow: "3px 3px 0px #FF6B9D"
                                    }}>
                                        {currentQuestion.text}
                                    </h2>
                                </div>

                                {/* Answer Options */}
                                <div className="grid grid-cols-1 md:grid-cols-2 gap-4 lg:gap-6">
                                {currentQuestion.options.map((option, index) => (
                                    <button
                                        key={index}
                                        onClick={() => handleSelectAnswer(option)}
                                        disabled={hasCommitted || timeLeft === 0}
                                        className={`p-6 rounded-2xl font-black text-lg transition-all transform hover:scale-105 border-3 ${selectedAnswer === option
                                                ? 'vietnamese-accent text-white shadow-2xl scale-105 border-transparent vietnamese-glow'
                                                : 'bg-gradient-to-r from-purple-50 to-pink-50 text-gray-800 hover:from-purple-100 hover:to-pink-100 border-purple-200'
                                            } ${(hasCommitted || timeLeft === 0) && 'opacity-50 cursor-not-allowed hover:scale-100'
                                            } ${showResult && option === currentQuestion.correct
                                                ? 'ring-4 ring-green-400 bg-gradient-to-r from-green-100 to-emerald-100 border-green-400'
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
                                    className="w-full mt-6 lg:mt-8 py-5 lg:py-7 rounded-xl font-black text-xl lg:text-3xl uppercase tracking-wide hover:shadow-2xl transform hover:scale-105 transition-all disabled:opacity-50 disabled:cursor-not-allowed disabled:transform-none"
                                    style={{
                                        fontFamily: "'Fredoka', sans-serif",
                                        background: selectedAnswer ? "linear-gradient(135deg, #FF6B9D 0%, #9D4EDD 100%)" : "#E5E5E5",
                                        border: "3px solid #2D1B3D",
                                        color: selectedAnswer ? "#FFFFFF" : "#999999"
                                    }}
                                >
                                    {selectedAnswer ? 'Xác nhận đáp án' : 'Chọn đáp án'}
                                </button>
                            )}

                            {/* Committed Status */}
                            {hasCommitted && !showResult && (
                                <div className="mt-6 text-center p-5 lg:p-8 bg-gradient-to-r from-purple-50 to-pink-50 rounded-xl border-2 border-purple-200">
                                    <p className="text-purple-700 font-black text-lg lg:text-2xl">
                                        Đã gửi đáp án! Đang chờ người chơi khác...
                                    </p>
                                </div>
                            )}

                            {/* Result */}
                            {showResult && (
                                <div className={`mt-6 text-center p-6 lg:p-10 rounded-xl border-3 shadow-lg ${isCorrect
                                        ? 'bg-gradient-to-r from-green-50 to-emerald-50 border-green-400'
                                        : 'bg-gradient-to-r from-red-50 to-pink-50 border-red-400'
                                    }`}>
                                    <p className={`text-2xl lg:text-4xl font-black mb-2 lg:mb-4 ${isCorrect ? 'text-green-700' : 'text-red-700'
                                        }`}>
                                        {isCorrect ? 'Chính xác! +100 điểm' : 'Sai rồi!'}
                                    </p>
                                    <p className="text-base lg:text-xl text-gray-700 mt-2 lg:mt-4 font-semibold">
                                        Đáp án đúng: <span className="font-black text-lg lg:text-2xl">{currentQuestion.correct}</span>
                                    </p>
                                </div>
                            )}
                        </div>

                        {/* Auto-advance message */}
                        {showResult && (
                            <div className="text-center mt-4 p-5 lg:p-8 bg-gradient-to-r from-purple-50 to-pink-50 rounded-xl border-2 border-purple-200">
                                <p className="text-purple-700 font-black text-lg lg:text-2xl">
                                    {currentRound < totalRounds 
                                        ? 'Đang chuyển sang câu hỏi tiếp theo...' 
                                        : 'Trò chơi kết thúc! Đang chuyển đến kết quả...'}
                                </p>
                            </div>
                        )}
                    </div>
                )}
            </div>
        </div>
    );
}