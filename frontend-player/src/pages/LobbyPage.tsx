import { useEffect, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { useGameStore } from '../store/gameStore';
import { useGameSocket } from '../hooks/useGameSocket';

export function LobbyPage() {
    const navigate = useNavigate();
    const [copied, setCopied] = useState(false);

    const {
        playerId,
        nickname,
        isHost,
        roomCode,
        players,
        setPlayers,
        addPlayer,
        removePlayer,
        setRound,
        setGameState,
    } = useGameStore();

    // Redirect if not properly joined
    useEffect(() => {
        if (!playerId || !roomCode || !nickname) {
            navigate('/');
        }
    }, [playerId, roomCode, nickname, navigate]);

    const { connected, error, startGame } = useGameSocket({
        roomCode: roomCode || '',
        playerId: playerId || '',
        nickname: nickname || '',
        onGameState: (state) => {
            setPlayers(state.players);
            setRound(state.current_round, state.total_rounds);
            setGameState(state.state);
        },
        onPlayerJoined: (data) => {
            console.log('Player joined:', data);
            // Update player list from broadcast
            if (data.players && Array.isArray(data.players)) {
                setPlayers(data.players);
            }
        },
        onPlayerDisconnected: (data) => {
            removePlayer(data.player_id);
        },
        onGameStarted: (data) => {
            setRound(data.round, data.total_rounds);
            setGameState('round_start');
            navigate('/game');
        },
    });

    const handleStartGame = async () => {
        try {
            await startGame();
        } catch (err) {
            console.error('Failed to start game:', err);
        }
    };

    const handleCopyCode = () => {
        if (roomCode) {
            navigator.clipboard.writeText(roomCode);
            setCopied(true);
            setTimeout(() => setCopied(false), 2000);
        }
    };

    if (!playerId || !roomCode) {
        return null;
    }

    return (
        <div className="min-h-screen bg-gradient-to-br from-blue-600 via-purple-500 to-pink-500 flex items-center justify-center p-4">
            <div className="bg-white rounded-3xl shadow-2xl p-8 w-full max-w-2xl">
                {/* Header */}
                <div className="text-center mb-8">
                    <h1 className="text-3xl font-bold text-gray-800 mb-4">
                        🎮 Phòng chờ
                    </h1>

                    {/* Room Code */}
                    <div className="inline-flex items-center gap-3 bg-gradient-to-r from-purple-100 to-pink-100 px-6 py-3 rounded-2xl">
                        <span className="text-sm font-medium text-gray-600">Mã phòng:</span>
                        <span className="text-3xl font-bold text-purple-600 tracking-wider">
                            {roomCode}
                        </span>
                        <button
                            onClick={handleCopyCode}
                            className="ml-2 p-2 hover:bg-white rounded-lg transition-colors"
                            title="Copy mã phòng"
                        >
                            {copied ? '✓' : '📋'}
                        </button>
                    </div>

                    {copied && (
                        <p className="text-sm text-green-600 mt-2">Đã copy mã phòng!</p>
                    )}
                </div>

                {/* Connection Status */}
                <div className="mb-6 flex items-center justify-center gap-2">
                    <div className={`w-3 h-3 rounded-full ${connected ? 'bg-green-500 animate-pulse' : 'bg-red-500'}`} />
                    <span className="text-sm text-gray-600">
                        {connected ? 'Đã kết nối' : 'Đang kết nối...'}
                    </span>
                </div>

                {error && (
                    <div className="mb-6 p-4 bg-red-50 border border-red-200 rounded-lg text-red-700 text-sm">
                        {error}
                    </div>
                )}

                {/* Players List */}
                <div className="mb-8">
                    <h2 className="text-xl font-semibold text-gray-700 mb-4">
                        Người chơi ({players.length}/8)
                    </h2>

                    <div className="space-y-2">
                        {players.map((player) => (
                            <div
                                key={player.id}
                                className={`flex items-center justify-between p-4 rounded-xl transition-all ${player.connected
                                        ? 'bg-gradient-to-r from-purple-50 to-pink-50'
                                        : 'bg-gray-100 opacity-60'
                                    }`}
                            >
                                <div className="flex items-center gap-3">
                                    <div className={`w-10 h-10 rounded-full flex items-center justify-center text-xl ${player.is_host
                                            ? 'bg-gradient-to-br from-yellow-400 to-orange-400'
                                            : 'bg-gradient-to-br from-blue-400 to-purple-400'
                                        }`}>
                                        {player.is_host ? '👑' : '🎮'}
                                    </div>
                                    <div>
                                        <p className="font-semibold text-gray-800">
                                            {player.nickname}
                                            {player.id === playerId && (
                                                <span className="ml-2 text-xs text-purple-600">(Bạn)</span>
                                            )}
                                        </p>
                                        {player.is_host && (
                                            <p className="text-xs text-gray-500">Chủ phòng</p>
                                        )}
                                    </div>
                                </div>

                                <div className={`w-2 h-2 rounded-full ${player.connected ? 'bg-green-500' : 'bg-gray-400'
                                    }`} />
                            </div>
                        ))}
                    </div>
                </div>

                {/* Start Game Button (Host Only) */}
                {isHost && (
                    <button
                        onClick={handleStartGame}
                        disabled={players.length < 2 || !connected}
                        className="w-full bg-gradient-to-r from-green-500 to-emerald-500 text-white py-4 rounded-xl font-bold text-lg hover:shadow-lg transform hover:scale-105 transition-all disabled:opacity-50 disabled:cursor-not-allowed disabled:transform-none"
                    >
                        {players.length < 2
                            ? '⏳ Cần ít nhất 2 người chơi'
                            : '🚀 Bắt đầu trò chơi'}
                    </button>
                )}

                {/* Waiting Message (Non-Host) */}
                {!isHost && (
                    <div className="text-center py-4 px-6 bg-blue-50 rounded-xl">
                        <p className="text-gray-700">
                            ⏳ Đang chờ chủ phòng bắt đầu trò chơi...
                        </p>
                    </div>
                )}

                {/* Info */}
                <div className="mt-6 text-center text-sm text-gray-500">
                    <p>Chia sẻ mã phòng với bạn bè để họ tham gia!</p>
                </div>
            </div>
        </div>
    );
}