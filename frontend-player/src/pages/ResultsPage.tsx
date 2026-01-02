import { useEffect, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { useGameStore } from '../store/gameStore';
import { useGameSocket } from '../hooks/useGameSocket';

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
        <div className="min-h-screen bg-gradient-to-br from-purple-600 via-pink-500 to-red-500 flex items-center justify-center p-4">
            <div className="bg-white rounded-3xl shadow-2xl p-8 w-full max-w-2xl">
                {/* Trophy Animation */}
                <div className="text-center mb-8">
                    <div className="text-8xl mb-4 animate-bounce">
                        🏆
                    </div>
                    <h1 className="text-4xl font-bold text-gray-800 mb-2">
                        Trò chơi kết thúc!
                    </h1>
                    {isWinner ? (
                        <p className="text-2xl text-green-600 font-semibold">
                            🎉 Chúc mừng! Bạn đã chiến thắng! 🎉
                        </p>
                    ) : (
                        <p className="text-xl text-gray-600">
                            Người chiến thắng: <strong>{winner?.nickname}</strong>
                        </p>
                    )}
                </div>

                {/* Final Leaderboard */}
                <div className="mb-8">
                    <h2 className="text-2xl font-bold text-gray-700 mb-4 text-center">
                        Bảng xếp hạng cuối cùng
                    </h2>

                    <div className="space-y-3">
                        {sortedPlayers.map((player, index) => (
                            <div
                                key={player.id}
                                className={`flex items-center justify-between p-4 rounded-xl transition-all ${index === 0
                                        ? 'bg-gradient-to-r from-yellow-400 to-orange-400 text-white scale-105'
                                        : index === 1
                                            ? 'bg-gradient-to-r from-gray-300 to-gray-400 text-gray-800'
                                            : index === 2
                                                ? 'bg-gradient-to-r from-orange-300 to-orange-400 text-gray-800'
                                                : 'bg-gray-100 text-gray-800'
                                    }`}
                            >
                                <div className="flex items-center gap-4">
                                    <div className="text-3xl font-bold">
                                        {index === 0 ? '🥇' : index === 1 ? '🥈' : index === 2 ? '🥉' : `#${index + 1}`}
                                    </div>
                                    <div>
                                        <p className="font-bold text-lg">
                                            {player.nickname}
                                            {player.id === playerId && (
                                                <span className="ml-2 text-sm">(Bạn)</span>
                                            )}
                                        </p>
                                    </div>
                                </div>
                                <div className="text-2xl font-bold">
                                    {player.score} điểm
                                </div>
                            </div>
                        ))}
                    </div>
                </div>

                {/* Stats */}
                <div className="grid grid-cols-2 gap-4 mb-8">
                    <div className="bg-blue-50 p-4 rounded-xl text-center">
                        <p className="text-sm text-gray-600 mb-1">Điểm của bạn</p>
                        <p className="text-3xl font-bold text-blue-600">
                            {myPlayer?.score || 0}
                        </p>
                    </div>
                    <div className="bg-green-50 p-4 rounded-xl text-center">
                        <p className="text-sm text-gray-600 mb-1">Xếp hạng</p>
                        <p className="text-3xl font-bold text-green-600">
                            #{sortedPlayers.findIndex(p => p.id === playerId) + 1}
                        </p>
                    </div>
                </div>

                {/* Rematch Section */}
                {!rematchExpired && countdown > 0 && (
                    <div className="mb-6 p-4 bg-purple-50 rounded-xl border-2 border-purple-200">
                        <div className="flex items-center justify-between mb-3">
                            <div>
                                <p className="font-semibold text-gray-800">Đồng ý chơi lại?</p>
                                <p className="text-sm text-gray-600">
                                    {rematchVotes} / {totalPlayers || players.length} người đồng ý
                                </p>
                            </div>
                            <div className="text-2xl font-bold text-purple-600">
                                {countdown}s
                            </div>
                        </div>

                        {hasVoted ? (
                            <div className="text-center py-2 bg-green-100 rounded-lg text-green-700 font-semibold">
                                ✓ Đã đồng ý! Đang chờ người chơi khác...
                            </div>
                        ) : (
                            <button
                                onClick={handleRematch}
                                className="w-full bg-gradient-to-r from-purple-500 to-pink-500 text-white py-3 rounded-xl font-bold hover:shadow-lg transform hover:scale-105 transition-all"
                            >
                                ↻ Đồng ý chơi lại
                            </button>
                        )}
                    </div>
                )}

                {rematchExpired && (
                    <div className="mb-6 p-4 bg-gray-100 rounded-xl text-center">
                        <p className="text-gray-600">⏰ Hết thời gian chơi lại</p>
                    </div>
                )}

                {/* Actions */}
                <div className="space-y-3">
                    {!rematchExpired && !hasVoted && (
                        <button
                            onClick={handleGoHome}
                            className="w-full bg-gray-200 text-gray-700 py-4 rounded-xl font-semibold hover:bg-gray-300 transition-colors"
                        >
                            🏠 Không chơi lại, về trang chủ
                        </button>
                    )}

                    {(rematchExpired || (hasVoted && rematchVotes < 2)) && (
                        <button
                            onClick={handleGoHome}
                            className="w-full bg-gradient-to-r from-gray-600 to-gray-700 text-white py-4 rounded-xl font-bold hover:shadow-lg transform hover:scale-105 transition-all"
                        >
                            🏠 Về trang chủ
                        </button>
                    )}
                </div>

                {/* Connection Status */}
                <div className="mt-4 text-center text-sm text-gray-500">
                    <div className="flex items-center justify-center gap-2">
                        <div className={`w-2 h-2 rounded-full ${connected ? 'bg-green-500' : 'bg-red-500'}`} />
                        <span>{connected ? 'Đã kết nối' : 'Mất kết nối'}</span>
                    </div>
                </div>
            </div>
        </div>
    );
}