import { useEffect, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { useDisplayStore } from '../store/displayStore';
import { useDisplaySocket } from '../hooks/useDisplaySocket';
import { api } from '../lib/api';
import { copyText } from '../lib/clipboard';
import { PhoThePhoenix } from '../components/PhoThePhoenix';
import { HostPageShell, HostTitle } from '../components/HostPageShell';

const MAX_PLAYERS = 8;

export function LobbyPage() {
  const navigate = useNavigate();
  const roomCode = useDisplayStore((state) => state.roomCode);
  const players = useDisplayStore((state) => state.players);
  const setPlayers = useDisplayStore((state) => state.setPlayers);
  const setGameState = useDisplayStore((state) => state.setGameState);
  const setRound = useDisplayStore((state) => state.setRound);
  const setLeaderboard = useDisplayStore((state) => state.setLeaderboard);
  const setWinner = useDisplayStore((state) => state.setWinner);
  const reset = useDisplayStore((state) => state.reset);

  const [copied, setCopied] = useState(false);
  const [copyError, setCopyError] = useState<string | null>(null);
  const onlineCount = players.filter((p) => p.connected).length;

  const refreshPlayers = async () => {
    const code = useDisplayStore.getState().roomCode;
    if (!code) return;
    try {
      const res = await api.getPlayers(code);
      if (res.success && res.players) setPlayers(res.players);
    } catch {
      // ignore poll errors
    }
  };

  useEffect(() => {
    if (!roomCode) {
      navigate('/');
    }
  }, [roomCode, navigate]);

  useEffect(() => {
    if (!roomCode) return;
    refreshPlayers();
    const id = window.setInterval(refreshPlayers, 4000);
    return () => window.clearInterval(id);
  }, [roomCode]);

  const { connected, closeRoom } = useDisplaySocket({
    roomCode: roomCode || '',
    onGameState: (state) => {
      if (state.players) setPlayers(state.players);
      setGameState(state.state);
      if (state.state === 'round_start') {
        navigate('/game');
      }
    },
    onPlayersSync: (data) => {
      if (data.players) setPlayers(data.players);
    },
    onPlayerJoined: async (data) => {
      if (data.players?.length) {
        setPlayers(data.players);
        return;
      }
      await refreshPlayers();
    },
    onPlayerDisconnected: async (data) => {
      if (data.players?.length) {
        setPlayers(data.players);
        return;
      }
      await refreshPlayers();
    },
    onGameStarted: (data) => {
      setRound(data.round, data.total_rounds);
      setGameState('round_start');
      navigate('/game');
    },
    onGameEnded: (data) => {
      if (data.final_scores) setLeaderboard(data.final_scores);
      if (data.winner) setWinner(data.winner);
      setGameState('game_end');
      navigate('/results');
    },
    onRoomClosed: () => {
      reset();
      navigate('/');
    },
  });

  const handleCopyCode = async () => {
    if (!roomCode) return;
    setCopyError(null);
    const ok = await copyText(roomCode);
    if (ok) {
      setCopied(true);
      setTimeout(() => setCopied(false), 2000);
    } else {
      setCopyError('Could not copy automatically. Select the code and press Cmd+C.');
    }
  };

  const handleReturnHome = async () => {
    try {
      await closeRoom();
    } catch {
      // still leave
    }
    reset();
    navigate('/');
  };

  if (!roomCode) return null;

  return (
    <HostPageShell>
      <div className="flex flex-col items-center justify-center min-h-screen px-4 py-8">
        <div
          className="bg-white/95 backdrop-blur-sm rounded-3xl shadow-2xl p-8 w-full max-w-3xl border-4 border-purple-500"
          style={{ borderRadius: '2rem' }}
        >
          <div className="text-center mb-8">
            <div className="flex justify-center mb-4">
              <PhoThePhoenix className="w-28 h-36 drop-shadow-xl" />
            </div>
            <HostTitle>Host Lobby</HostTitle>
            <p className="text-gray-600 font-medium mt-2">
              Share this code so players can join from their phones.
            </p>
          </div>

          <div className="flex flex-col sm:flex-row items-center justify-center gap-4 mb-6">
            <div className="inline-flex items-center gap-4 bg-gradient-to-r from-purple-100 to-pink-100 px-8 py-4 rounded-2xl border-2 border-purple-200 shadow-lg">
              <span className="text-sm font-bold text-gray-700 uppercase tracking-wide">Room code</span>
              <span
                className="text-4xl sm:text-5xl font-black tracking-widest select-all"
                style={{ color: '#9D4EDD', textShadow: '2px 2px 0px #FF6B9D' }}
              >
                {roomCode}
              </span>
            </div>
            <button
              type="button"
              onClick={handleCopyCode}
              className="px-6 py-4 bg-white hover:bg-purple-50 rounded-xl transition-all hover:scale-105 border-2 border-purple-300 font-bold text-purple-700 shadow-md"
            >
              {copied ? 'Copied!' : 'Copy code'}
            </button>
          </div>

          {copied && (
            <p className="text-center text-sm text-green-600 font-semibold mb-4">
              Room code copied to clipboard.
            </p>
          )}
          {copyError && (
            <p className="text-center text-sm text-red-600 font-semibold mb-4">{copyError}</p>
          )}

          <div className="mb-6 flex items-center justify-center gap-3">
            <div className={`w-4 h-4 rounded-full ${connected ? 'bg-green-500 animate-pulse' : 'bg-red-500'}`} />
            <span className={`text-sm font-semibold ${connected ? 'text-green-600' : 'text-red-600'}`}>
              {connected ? 'Display connected' : 'Connecting display…'}
            </span>
          </div>

          <h2
            className="text-2xl font-black mb-4 text-center"
            style={{
              fontFamily: "'Bangers', cursive",
              color: '#FF9E3D',
              textShadow: '2px 2px 0px #FF6B9D',
            }}
          >
            Players ({onlineCount}/{MAX_PLAYERS} online · {players.length} seats)
          </h2>

          <div className="space-y-3 mb-8 max-h-80 overflow-y-auto">
            {players.length === 0 ? (
              <p className="text-center text-gray-500 py-8 font-medium">Waiting for players to join…</p>
            ) : (
              players.map((player) => (
                <div
                  key={player.id}
                  className={`flex items-center justify-between p-4 rounded-xl border-2 ${
                    player.is_host
                      ? 'bg-gradient-to-r from-yellow-50 to-orange-50 border-orange-300'
                      : 'bg-gradient-to-r from-purple-50 to-pink-50 border-purple-200'
                  } ${!player.connected ? 'opacity-70' : ''}`}
                >
                  <div className="flex items-center gap-4">
                    <div
                      className={`w-12 h-12 rounded-full flex items-center justify-center text-white font-black text-lg ${
                        player.is_host
                          ? 'bg-gradient-to-br from-yellow-400 to-orange-500'
                          : 'bg-gradient-to-br from-purple-400 to-pink-500'
                      }`}
                    >
                      {player.is_host ? 'H' : player.nickname.charAt(0).toUpperCase()}
                    </div>
                    <div>
                      <p className="text-lg font-bold text-gray-800">{player.nickname}</p>
                      <div className="flex gap-2 flex-wrap">
                        {player.is_host && (
                          <p className="text-xs font-semibold text-orange-600 uppercase">Host</p>
                        )}
                        <p
                          className={`text-xs font-semibold uppercase ${
                            player.connected ? 'text-green-600' : 'text-gray-500'
                          }`}
                        >
                          {player.connected ? 'Online' : 'Absent'}
                        </p>
                      </div>
                    </div>
                  </div>
                  <div
                    className={`w-3 h-3 rounded-full ${player.connected ? 'bg-green-500' : 'bg-gray-400'}`}
                    title={player.connected ? 'Connected' : 'Disconnected'}
                  />
                </div>
              ))
            )}
          </div>

          <div className="text-center py-4 px-6 bg-gradient-to-r from-purple-50 to-pink-50 rounded-xl border-2 border-purple-200 mb-6">
            <p className="text-gray-700 font-bold">
              {onlineCount === 0
                ? 'Waiting for players…'
                : 'A connected player with the host badge can start the game from their phone.'}
            </p>
          </div>

          <div className="flex justify-center">
            <button
              type="button"
              onClick={handleReturnHome}
              className="px-6 py-3 rounded-xl border-2 border-gray-300 font-bold text-gray-700 hover:bg-gray-50"
            >
              Return to main screen
            </button>
          </div>
        </div>
      </div>
    </HostPageShell>
  );
}
