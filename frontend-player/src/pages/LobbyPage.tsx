import { useEffect, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { useGameStore } from '../store/gameStore';
import { useGameSocket } from '../hooks/useGameSocket';
import { api } from '../lib/api';
import { PhoThePhoenix } from '../components/PhoThePhoenix';
import { copyText } from '../lib/clipboard';
import { LotusPattern, DragonPattern, LanternPattern, BambooPattern } from '../components/VietnamesePatterns';

export function LobbyPage() {
    const navigate = useNavigate();
    const [copied, setCopied] = useState(false);
    const [startError, setStartError] = useState<string | null>(null);
    const [storeHydrated, setStoreHydrated] = useState(() => useGameStore.persist.hasHydrated());

    const {
        playerId,
        nickname,
        isHost,
        roomCode,
        players,
        setPlayers,
        removePlayer,
        setRound,
        setGameState,
        setMode,
        setPlayerInfo,
        reset,
    } = useGameStore();

    useEffect(() => {
        if (useGameStore.persist.hasHydrated()) setStoreHydrated(true);
        return useGameStore.persist.onFinishHydration(() => setStoreHydrated(true));
    }, []);

    // Redirect if not properly joined
    useEffect(() => {
        if (!storeHydrated) return;
        if (!playerId || !roomCode || !nickname) {
            navigate('/');
        }
    }, [storeHydrated, playerId, roomCode, nickname, navigate]);

    const { connected, error, startGame, leaveRoom } = useGameSocket({
        roomCode: roomCode || '',
        playerId: playerId || '',
        nickname: nickname || '',
        onGameState: (state) => {
            if (state.players) setPlayers(state.players);
            setRound(state.current_round, state.total_rounds);
            setGameState(state.state);
            if (state.mode) setMode(state.mode);
            const tr = state.truth_resume;
            if (
                state.state === 'round_start' &&
                state.mode === 'truth_collapse' &&
                tr &&
                (tr.phase === 'discussion' || tr.phase === 'answering' || tr.phase === 'results')
            ) {
                navigate('/game');
            }
        },
        onPlayerJoined: async (data) => {
            console.log('Player joined:', data);
            // Fetch players from API (source of truth) - fixes bug where 2nd player
            // join showed only 1 player due to WebSocket broadcast timing/ordering
            const code = useGameStore.getState().roomCode;
            if (code) {
                try {
                    const res = await api.getPlayers(code);
                    if (res.success && res.players) {
                        setPlayers(res.players);
                        return;
                    }
                } catch {
                    // Fall through to broadcast payload fallback
                }
            }
            // Fallback: use broadcast payload if API fails or no room code
            if (data.players && Array.isArray(data.players)) {
                setPlayers(data.players);
            }
        },
        onPlayerDisconnected: (data) => {
            if (data.players && Array.isArray(data.players)) {
                setPlayers(data.players);
            } else {
                removePlayer(data.player_id);
            }
        },
        onGameStarted: (data) => {
            setRound(data.round, data.total_rounds);
            setGameState('round_start');
            navigate('/game');
        },
        onPlayersSync: (data) => {
            if (data.players) {
                setPlayers(data.players);
                const me = data.players.find((p) => p.id === playerId);
                if (me && playerId && nickname) {
                    setPlayerInfo(playerId, nickname, me.is_host);
                }
            }
        },
        onRoomClosed: () => {
            reset();
            navigate('/');
        },
        onHostChanged: (data) => {
            const list = useGameStore.getState().players;
            if (list.length) {
                setPlayers(
                    list.map((p) => ({
                        ...p,
                        is_host: p.id === data.host_id,
                    }))
                );
            }
            if (playerId && nickname) {
                setPlayerInfo(playerId, nickname, data.host_id === playerId);
            }
        },
    });

    const handleStartGame = async () => {
        try {
            setStartError(null);
            await startGame();
        } catch (err) {
            console.error('Failed to start game:', err);
            const reason =
                typeof err === 'object' && err !== null
                    ? (err as any).reason || (err as any).message
                    : null;
            setStartError(reason || (err instanceof Error ? err.message : 'Could not start the game'));
        }
    };

    const handleCopyCode = async () => {
        if (roomCode) {
            const ok = await copyText(roomCode);
            if (ok) {
                setCopied(true);
                setTimeout(() => setCopied(false), 2000);
            }
        }
    };

    const handleReturnMain = async () => {
        try {
            await leaveRoom();
        } catch {
            // ignore
        }
        reset();
        navigate('/');
    };

    if (!storeHydrated || !playerId || !roomCode) {
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
                    {/* Header */}
                    <div className="text-center mb-8">
                        <div className="flex justify-center mb-4">
                            <PhoThePhoenix className="w-32 h-40 drop-shadow-2xl" />
                        </div>
                        <h1 className="mb-4" style={{ 
                            fontFamily: "'Bangers', cursive",
                            fontSize: "clamp(2.5rem, 8vw, 4rem)",
                            lineHeight: "1.1",
                            color: "#9D4EDD",
                            textShadow: "4px 4px 0px #FF6B9D, 8px 8px 0px #FF9E3D",
                            letterSpacing: "0.05em"
                        }}>
                            Waiting room
                        </h1>

                        {/* Room Code */}
                        <div className="inline-flex items-center gap-4 bg-gradient-to-r from-purple-100 to-pink-100 px-8 py-4 rounded-2xl border-2 border-purple-200 shadow-lg mb-4">
                            <span className="text-sm font-bold text-gray-700 uppercase tracking-wide">Room code:</span>
                            <span className="text-4xl font-black tracking-widest" style={{
                                color: "#9D4EDD",
                                textShadow: "2px 2px 0px #FF6B9D"
                            }}>
                                {roomCode}
                            </span>
                            <button
                                onClick={handleCopyCode}
                                className="ml-2 px-4 py-2 bg-white hover:bg-purple-50 rounded-xl transition-all transform hover:scale-110 border-2 border-purple-200 font-bold text-purple-600"
                                title="Copy room code"
                            >
                                {copied ? 'Copied!' : 'Copy'}
                            </button>
                        </div>

                    {copied && (
                        <p className="text-sm text-green-600 mt-3 font-semibold">Room code copied to clipboard.</p>
                    )}
                </div>

                {/* Connection Status */}
                <div className="mb-6 flex items-center justify-center gap-3">
                    <div className={`w-4 h-4 rounded-full ${connected ? 'bg-green-500 animate-pulse vietnamese-glow' : 'bg-red-500'}`} />
                    <span className={`text-sm font-semibold ${connected ? 'text-green-600' : 'text-red-600'}`}>
                        {connected ? 'Connected' : 'Connecting…'}
                    </span>
                </div>

                <div className="mb-6 text-center">
                    <button
                        type="button"
                        onClick={handleReturnMain}
                        className="px-5 py-2 rounded-xl border-2 border-purple-200 bg-white text-purple-700 font-bold hover:bg-purple-50"
                    >
                        Return to main screen
                    </button>
                </div>

                {error && (
                    <div className="mb-6 p-4 bg-red-50 border border-red-200 rounded-lg text-red-700 text-sm">
                        {error}
                    </div>
                )}

                {startError && (
                    <div className="mb-6 p-4 bg-red-50 border border-red-200 rounded-lg text-red-700 text-sm">
                        {startError}
                    </div>
                )}

                    {/* Players List */}
                    <div className="mb-8">
                        <h2 className="text-2xl font-black mb-6 text-center" style={{
                            fontFamily: "'Bangers', cursive",
                            color: "#FF9E3D",
                            textShadow: "3px 3px 0px #FF6B9D"
                        }}>
                            Players ({players.filter((p) => p.connected).length}/{players.length} online)
                        </h2>

                        <div className="grid grid-cols-1 md:grid-cols-2 gap-3">
                        {players.map((player) => (
                            <div
                                key={player.id}
                                className={`flex items-center justify-between p-5 lg:p-6 rounded-xl transition-all transform hover:scale-102 border-2 ${player.connected
                                        ? player.is_host
                                            ? 'bg-gradient-to-r from-yellow-50 to-orange-50 border-orange-300 shadow-md'
                                            : 'bg-gradient-to-r from-purple-50 to-pink-50 border-purple-200'
                                        : 'bg-gray-100 opacity-60 border-gray-300'
                                    }`}
                            >
                                <div className="flex items-center gap-4 lg:gap-5">
                                    <div className={`w-14 h-14 lg:w-16 lg:h-16 rounded-full flex items-center justify-center font-black text-xl lg:text-2xl shadow-lg ${player.is_host
                                            ? 'bg-gradient-to-br from-yellow-400 to-orange-500 text-white'
                                            : 'bg-gradient-to-br from-purple-400 to-pink-500 text-white'
                                        }`}>
                                        {player.is_host ? 'H' : player.nickname.charAt(0).toUpperCase()}
                                    </div>
                                    <div>
                                        <p className="font-bold text-lg lg:text-xl text-gray-800">
                                            {player.nickname}
                                            {player.id === playerId && (
                                                <span className="ml-2 text-sm lg:text-base font-semibold text-purple-600">(You)</span>
                                            )}
                                        </p>
                                        <div className="flex gap-2 flex-wrap">
                                            {player.is_host && (
                                                <p className="text-xs lg:text-sm font-semibold text-orange-600 uppercase tracking-wide">Host</p>
                                            )}
                                            <p className={`text-xs lg:text-sm font-semibold uppercase ${player.connected ? 'text-green-600' : 'text-gray-500'}`}>
                                                {player.connected ? 'Online' : 'Absent'}
                                            </p>
                                        </div>
                                    </div>
                                </div>

                                <div className={`w-3 h-3 lg:w-4 lg:h-4 rounded-full ${player.connected ? 'bg-green-500 animate-pulse' : 'bg-gray-400'
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
                            className="w-full py-6 rounded-2xl shadow-lg hover:shadow-xl transition-all duration-300 hover:scale-105 disabled:opacity-50 disabled:cursor-not-allowed disabled:hover:scale-100"
                            style={{
                                fontSize: "1.5rem",
                                fontFamily: "'Fredoka', sans-serif",
                                background: (players.length >= 2 && connected)
                                    ? "linear-gradient(135deg, #FF6B9D 0%, #9D4EDD 100%)"
                                    : "#E5E5E5",
                                border: "3px solid #2D1B3D",
                                color: (players.length >= 2 && connected) ? "#FFFFFF" : "#999999"
                            }}
                        >
                            {players.length < 2
                                ? `Need at least 2 players (${players.length}/2)`
                                : 'Start game'}
                        </button>
                    )}

                    {/* Waiting Message (Non-Host) */}
                    {!isHost && (
                        <div className="text-center py-5 px-6 bg-gradient-to-r from-purple-50 to-pink-50 rounded-xl border-2 border-purple-200">
                            <p className="text-gray-700 font-bold text-lg">
                                Waiting for the host to start the game…
                            </p>
                        </div>
                    )}

                    {/* Info */}
                    <div className="mt-6 text-center">
                        <p className="text-gray-600 font-medium">Share the room code with friends so they can join.</p>
                    </div>
                </div>
            </div>
        </div>
    );
}