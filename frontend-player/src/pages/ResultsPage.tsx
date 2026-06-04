import { useEffect, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { useGameStore } from '../store/gameStore';
import { useGameSocket } from '../hooks/useGameSocket';
import { api } from '../lib/api';
import { PhoThePhoenix } from '../components/PhoThePhoenix';
import { LotusPattern, DragonPattern, LanternPattern, BambooPattern } from '../components/VietnamesePatterns';

export function ResultsPage() {
    const navigate = useNavigate();
    const [rematchVotes, setRematchVotes] = useState(0);
    const [declinedCount, setDeclinedCount] = useState(0);
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
        setPlayers,
        setGameState,
        setRound,
    } = useGameStore();

    useEffect(() => {
        if (!playerId || !roomCode) {
            navigate('/');
        }
    }, [playerId, roomCode, navigate]);

    useEffect(() => {
        if (!roomCode) return;
        let cancelled = false;
        const poll = async () => {
            try {
                const res = await api.getRoom(roomCode);
                if (!cancelled && res.success && res.room?.state === 'lobby') {
                    setGameState('lobby');
                    setRound(0, res.room.total_rounds ?? 5);
                    navigate('/lobby');
                }
            } catch {
                // ignore
            }
        };
        poll();
        const id = window.setInterval(poll, 2500);
        return () => {
            cancelled = true;
            window.clearInterval(id);
        };
    }, [roomCode, navigate, setGameState, setRound]);

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
        onGameState: (state: any) => {
            if (state.state === 'lobby') {
                if (state.players) setPlayers(state.players);
                setGameState('lobby');
                setRound(state.current_round ?? 0, state.total_rounds ?? 5);
                navigate('/lobby');
            }
        },
        onRematchVoteUpdated: (data: any) => {
            console.log('Rematch vote updated:', data);
            setRematchVotes(data.vote_count ?? 0);
            setDeclinedCount(data.declined_count ?? 0);
            setTotalPlayers(data.total_players ?? players.length);
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

    // Players don't see scores/results - only "look at screen" message

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
                    {/* Game Over Message - Players don't see results */}
                    <div className="text-center mb-12">
                        <div className="mb-8 flex justify-center">
                            <PhoThePhoenix className="w-48 h-56 md:w-64 md:h-72 drop-shadow-2xl" />
                        </div>
                        <h1 className="mb-6" style={{
                            fontFamily: "'Bangers', cursive",
                            fontSize: "clamp(3rem, 8vw, 5rem)",
                            lineHeight: "1.1",
                            color: "#9D4EDD",
                            textShadow: "4px 4px 0px #FF6B9D, 8px 8px 0px #FF9E3D",
                            letterSpacing: "0.05em"
                        }}>
                            Trò chơi kết thúc!
                        </h1>
                        <div className="bg-gradient-to-r from-purple-100 to-pink-100 p-8 lg:p-12 rounded-2xl border-4 border-purple-300 shadow-xl">
                            <p className="text-3xl lg:text-5xl font-black text-purple-700 mb-4">
                                Nhìn lên màn hình
                            </p>
                            <p className="text-xl lg:text-3xl text-gray-700 font-semibold">
                                để xem kết quả và người chiến thắng!
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
                                    {rematchVotes} / {totalPlayers || players.length} đồng ý
                                    {declinedCount > 0 ? ` · ${declinedCount} từ chối` : ''}
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