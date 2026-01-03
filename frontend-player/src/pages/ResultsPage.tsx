import { useEffect, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { useGameStore } from '../store/gameStore';
import { useGameSocket } from '../hooks/useGameSocket';
import { PhoThePhoenix } from '../components/PhoThePhoenix';
import { LotusPattern, DragonPattern, LanternPattern, BambooPattern } from '../components/VietnamesePatterns';

export function ResultsPage() {
    const navigate = useNavigate();
    const [rematchVotes, setRematchVotes] = useState(0);
    const [totalPlayers, setTotalPlayers] = useState(0);
    const [hasVoted, setHasVoted] = useState(false);
    const [countdown, setCountdown] = useState(30);
    const [rematchExpired, setRematchExpired] = useState(false);

    const {
        players,
        roomCode,
        playerId,
        nickname,
        reset,
        setGameState,
        setRound,
    } = useGameStore();

    useEffect(() => {
        if (!playerId || !roomCode) {
            navigate('/');
        }
    }, [playerId, roomCode, navigate]);

    // Countdown timer - backend handles timeout, this is just for display
    useEffect(() => {
        const timer = setInterval(() => {
            setCountdown((prev) => {
                if (prev <= 1) {
                    clearInterval(timer);
                    setRematchExpired(true);
                    return 0;
                }
                return prev - 1;
            });
        }, 1000);

        return () => clearInterval(timer);
    }, []);

    const { connected, requestRematch, declineRematch } = useGameSocket({
        roomCode: roomCode || '',
        playerId: playerId || '',
        nickname: nickname || '',
        onRematchVoteUpdated: (data: any) => {
            console.log('Rematch vote updated:', data);
            setRematchVotes(data.vote_count);
            setTotalPlayers(data.total_players);
        },
        onGameStarted: () => {
            // Rematch started - navigate to game
            setTimeout(() => {
                navigate('/game');
            }, 1000);
        },
        onRematchStarting: () => {
            // Rematch approved - go to lobby
            console.log('Rematch approved, going to lobby...');
            setRematchExpired(true);
            setTimeout(() => {
                setGameState('lobby');
                setRound(0, 5);
                navigate('/lobby');
            }, 1000);
        },
        onRematchCancelled: (data: any) => {
            // Not enough players want rematch
            console.log('Rematch cancelled:', data);
            setRematchExpired(true);
            setTimeout(() => {
                if (data?.kick_to_home) {
                    // Kick to home page
                    reset();
                    navigate('/');
                } else {
                    // Go to lobby (legacy behavior)
                    setGameState('lobby');
                    setRound(0, 5);
                    navigate('/lobby');
                }
            }, 1000);
        },
    });

    // Sort players by score
    const sortedPlayers = [...players].sort((a, b) => b.score - a.score);
    const winner = sortedPlayers[0];
    const isWinner = winner?.id === playerId;
    const myPlayer = players.find(p => p.id === playerId);

    const handleRematch = async () => {
        if (hasVoted || rematchExpired) return;

        setHasVoted(true);
        try {
            await requestRematch();
        } catch (err) {
            console.error('Failed to request rematch:', err);
            setHasVoted(false);
        }
    };

    const handleGoHome = async () => {
        // Notify others that you're declining (only if you haven't voted)
        if (!rematchExpired && !hasVoted) {
            try {
                await declineRematch();
            } catch (err) {
                console.error('Failed to decline rematch:', err);
            }
        }
        reset();
        navigate('/');
    };

    if (!playerId) {
        return null;
    }

    return (
        <div className="min-h-screen relative overflow-hidden">
            {/* Decorative Background Patterns */}
            <div className="absolute inset-0 overflow-hidden pointer-events-none">
                <LotusPattern className="absolute top-10 left-10 w-24 h-24 animate-pulse" />
                <LotusPattern className="absolute bottom-20 right-20 w-32 h-32 animate-pulse" style={{ animationDelay: "1s" }} />
                <DragonPattern className="absolute top-1/4 right-10 w-48 h-32 opacity-60" />
                <DragonPattern className="absolute bottom-1/3 left-10 w-48 h-32 opacity-60" />
                <LanternPattern className="absolute top-1/3 left-1/4 w-16 h-24 animate-bounce" style={{ animationDuration: "3s" }} />
                <LanternPattern className="absolute bottom-1/4 right-1/3 w-16 h-24 animate-bounce" style={{ animationDuration: "3.5s" }} />
                <BambooPattern className="absolute top-0 right-0 w-20 h-40 opacity-30" />
                <BambooPattern className="absolute bottom-0 left-0 w-20 h-40 opacity-30" />
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

            {/* Main Content */}
            <div className="relative z-10 flex flex-col items-center justify-center min-h-screen px-4 py-8">
                {/* Centered Card */}
                <div className="bg-white/95 backdrop-blur-sm rounded-3xl shadow-2xl p-8 w-full max-w-2xl lg:max-w-none lg:w-[95%] lg:max-w-[1600px] relative z-10" style={{ borderRadius: "2rem", border: "4px solid #9D4EDD" }}>
                    {/* Trophy Animation */}
                    <div className="text-center mb-8">
                        <div className="mb-4 flex justify-center">
                            <PhoThePhoenix className="w-48 h-56 md:w-64 md:h-72 drop-shadow-2xl" />
                        </div>
                        <h1 className="mb-3" style={{
                            fontFamily: "'Bangers', cursive",
                            fontSize: "clamp(2.5rem, 8vw, 4rem)",
                            lineHeight: "1.1",
                            color: "#9D4EDD",
                            textShadow: "4px 4px 0px #FF6B9D, 8px 8px 0px #FF9E3D",
                            letterSpacing: "0.05em"
                        }}>
                            Trò chơi kết thúc!
                        </h1>
                    {isWinner ? (
                        <p className="text-2xl lg:text-4xl text-green-600 font-black uppercase tracking-wide">
                            Chúc mừng! Bạn đã chiến thắng!
                        </p>
                    ) : (
                        <p className="text-xl lg:text-3xl text-gray-700 font-bold">
                            Người chiến thắng: <span className="vietnamese-text-gradient text-2xl lg:text-4xl">{winner?.nickname}</span>
                        </p>
                    )}
                </div>

                    {/* Final Leaderboard */}
                    <div className="mb-8">
                        <h2 className="text-3xl font-black mb-6 text-center" style={{
                            fontFamily: "'Bangers', cursive",
                            color: "#FF9E3D",
                            textShadow: "3px 3px 0px #FF6B9D"
                        }}>
                            Bảng xếp hạng cuối cùng
                        </h2>

                    <div className="grid grid-cols-1 lg:grid-cols-2 gap-3 lg:gap-6">
                        {sortedPlayers.map((player, index) => (
                            <div
                                key={player.id}
                                className={`flex items-center justify-between p-5 lg:p-7 rounded-xl transition-all transform hover:scale-102 border-3 shadow-lg ${index === 0
                                        ? 'bg-gradient-to-r from-yellow-400 to-orange-500 text-white scale-105 border-yellow-300 vietnamese-glow'
                                        : index === 1
                                            ? 'bg-gradient-to-r from-gray-300 to-gray-400 text-gray-800 border-gray-400'
                                            : index === 2
                                                ? 'bg-gradient-to-r from-orange-300 to-orange-400 text-gray-800 border-orange-300'
                                                : 'bg-gradient-to-r from-purple-50 to-pink-50 text-gray-800 border-purple-200'
                                    }`}
                            >
                                <div className="flex items-center gap-4 lg:gap-6">
                                    <div className={`w-12 h-12 lg:w-16 lg:h-16 rounded-full flex items-center justify-center font-black text-xl lg:text-2xl ${index === 0
                                            ? 'bg-white text-orange-500'
                                            : index === 1
                                                ? 'bg-white text-gray-600'
                                                : index === 2
                                                    ? 'bg-white text-orange-400'
                                                    : 'bg-purple-200 text-purple-600'
                                        }`}>
                                        {index === 0 ? '1' : index === 1 ? '2' : index === 2 ? '3' : index + 1}
                                    </div>
                                    <div>
                                        <p className="font-black text-lg lg:text-2xl">
                                            {player.nickname}
                                            {player.id === playerId && (
                                                <span className="ml-2 text-sm lg:text-base font-semibold opacity-80">(Bạn)</span>
                                            )}
                                        </p>
                                    </div>
                                </div>
                                <div className="text-2xl lg:text-3xl font-black">
                                    {player.score} điểm
                                </div>
                            </div>
                        ))}
                    </div>
                </div>

                {/* Stats */}
                <div className="grid grid-cols-2 gap-4 lg:gap-6 mb-8 lg:mb-12">
                    <div className="bg-gradient-to-r from-purple-50 to-pink-50 p-5 lg:p-8 rounded-xl text-center border-2 border-purple-200 shadow-md">
                        <p className="text-sm lg:text-lg text-gray-700 mb-2 lg:mb-4 font-bold uppercase tracking-wide">Điểm của bạn</p>
                        <p className="text-4xl lg:text-6xl font-black vietnamese-text-gradient">
                            {myPlayer?.score || 0}
                        </p>
                    </div>
                    <div className="bg-gradient-to-r from-pink-50 to-orange-50 p-5 lg:p-8 rounded-xl text-center border-2 border-pink-200 shadow-md">
                        <p className="text-sm lg:text-lg text-gray-700 mb-2 lg:mb-4 font-bold uppercase tracking-wide">Xếp hạng</p>
                        <p className="text-4xl lg:text-6xl font-black vietnamese-text-gradient">
                            #{sortedPlayers.findIndex(p => p.id === playerId) + 1}
                        </p>
                    </div>
                </div>

                {/* Rematch Section */}
                {!rematchExpired && countdown > 0 && (
                    <div className="mb-6 lg:mb-10 p-5 lg:p-8 bg-gradient-to-r from-purple-50 to-pink-50 rounded-xl border-3 border-purple-300 shadow-lg">
                        <div className="flex items-center justify-between mb-4 lg:mb-6">
                            <div>
                                <p className="font-black text-gray-800 text-lg lg:text-2xl mb-1 lg:mb-2">Đồng ý chơi lại?</p>
                                <p className="text-sm lg:text-lg text-gray-700 font-semibold">
                                    {rematchVotes} / {totalPlayers || players.length} người đồng ý
                                </p>
                            </div>
                            <div className="text-3xl lg:text-5xl font-black vietnamese-text-gradient">
                                {countdown}s
                            </div>
                        </div>

                        {hasVoted ? (
                            <div className="text-center py-4 lg:py-6 bg-gradient-to-r from-green-100 to-emerald-100 rounded-xl text-green-700 font-black text-lg lg:text-2xl border-2 border-green-300">
                                Đã đồng ý! Đang chờ người chơi khác...
                            </div>
                        ) : (
                            <button
                                onClick={handleRematch}
                                className="w-full py-4 lg:py-6 rounded-xl font-black text-xl lg:text-3xl uppercase tracking-wide hover:shadow-2xl transform hover:scale-105 transition-all"
                                style={{
                                    fontFamily: "'Fredoka', sans-serif",
                                    background: "linear-gradient(135deg, #FF6B9D 0%, #9D4EDD 100%)",
                                    border: "3px solid #2D1B3D",
                                    color: "#FFFFFF"
                                }}
                            >
                                Đồng ý chơi lại
                            </button>
                        )}
                    </div>
                )}

                {rematchExpired && (
                    <div className="mb-6 lg:mb-10 p-5 lg:p-8 bg-gradient-to-r from-gray-100 to-gray-200 rounded-xl text-center border-2 border-gray-300">
                        <p className="text-gray-700 font-black text-lg lg:text-2xl">Hết thời gian chơi lại</p>
                    </div>
                )}

                {/* Actions */}
                <div className="space-y-3 lg:space-y-4">
                    {!rematchExpired && !hasVoted && (
                        <button
                            onClick={handleGoHome}
                            className="w-full bg-gradient-to-r from-gray-200 to-gray-300 text-gray-700 py-4 lg:py-6 rounded-xl font-black text-lg lg:text-2xl hover:shadow-lg transform hover:scale-105 transition-all border-2 border-gray-300"
                        >
                            Không chơi lại, về trang chủ
                        </button>
                    )}

                    {(rematchExpired || (hasVoted && rematchVotes < 2)) && (
                        <button
                            onClick={handleGoHome}
                            className="w-full bg-gradient-to-r from-gray-600 to-gray-700 text-white py-4 lg:py-6 rounded-xl font-black text-lg lg:text-3xl uppercase tracking-wide hover:shadow-2xl transform hover:scale-105 transition-all"
                        >
                            Về trang chủ
                        </button>
                    )}
                </div>

                    {/* Connection Status */}
                    <div className="mt-4 lg:mt-6 text-center">
                        <div className="flex items-center justify-center gap-2">
                            <div className={`w-3 h-3 rounded-full ${connected ? 'bg-green-500 animate-pulse' : 'bg-red-500'}`} />
                            <span className={`text-sm font-semibold ${connected ? 'text-green-600' : 'text-red-600'}`}>
                                {connected ? 'Đã kết nối' : 'Mất kết nối'}
                            </span>
                        </div>
                    </div>
                </div>
            </div>
        </div>
    );
}