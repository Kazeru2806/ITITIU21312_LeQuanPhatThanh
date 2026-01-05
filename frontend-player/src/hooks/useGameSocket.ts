import { useEffect, useRef, useState } from 'react';
import { Socket, Channel } from 'phoenix';
import type { Room, Question, LeaderboardEntry } from '../types/game';

// Determine WebSocket URL so it works on both desktop and mobile.
// We intentionally ignore VITE_WS_URL here to avoid stale IPs.
const hostname = window.location.hostname || 'localhost';
const WS_URL = `ws://${hostname}:4000/socket`;

// Event data types
interface PlayerJoinedData {
    player_id: string;
    nickname: string;
    timestamp: string;
    players?: Array<{
        id: string;
        nickname: string;
        score: number;
        connected: boolean;
        is_host: boolean;
    }>;
}

interface PlayerDisconnectedData {
    player_id: string;
    nickname?: string;
}

interface GameStartedData {
    round: number;
    total_rounds: number;
    timestamp: string;
}

interface PlayerCommittedData {
    player_id: string;
    timestamp: string;
}

interface AnswerRevealedData {
    player_id: string;
    answer: string;
    is_valid: boolean;
    timestamp: string;
}

interface RoundScoredData {
    round: number;
    scores: Array<{
        player_id: string;
        is_correct: boolean;
        points: number;
    }>;
    leaderboard: LeaderboardEntry[];
    correct_answer?: string;
}

interface RoundStartedData {
    round: number;
    total_rounds: number;
}

interface GameEndedData {
    final_scores: LeaderboardEntry[];
    winner?: LeaderboardEntry;
}

interface UseGameSocketProps {
    roomCode: string;
    playerId: string;
    nickname: string;
    onGameState?: (state: Room) => void;
    onPlayerJoined?: (data: PlayerJoinedData) => void;
    onPlayerDisconnected?: (data: PlayerDisconnectedData) => void;
    onGameStarted?: (data: GameStartedData) => void;
    onQuestionRevealed?: (question: Question) => void;
    onPlayerCommitted?: (data: PlayerCommittedData) => void;
    onAnswerRevealed?: (data: AnswerRevealedData) => void;
    onRoundScored?: (data: RoundScoredData) => void;
    onRoundStarted?: (data: RoundStartedData) => void;
    onGameEnded?: (data: GameEndedData) => void;
    onRematchVoteUpdated?: (data: any) => void;
    onRematchStarting?: () => void;
    onRematchCancelled?: (data?: any) => void;
}

export function useGameSocket({
    roomCode,
    playerId,
    nickname,
    onGameState,
    onPlayerJoined,
    onPlayerDisconnected,
    onGameStarted,
    onQuestionRevealed,
    onPlayerCommitted,
    onAnswerRevealed,
    onRoundScored,
    onRoundStarted,
    onGameEnded,
    onRematchVoteUpdated,
    onRematchStarting,
    onRematchCancelled,
}: UseGameSocketProps) {
    const [connected, setConnected] = useState(false);
    const [error, setError] = useState<string | null>(null);

    const socketRef = useRef<Socket | null>(null);
    const channelRef = useRef<Channel | null>(null);

    useEffect(() => {
        // Create socket connection
        const socket = new Socket(WS_URL, {
            params: {},
            reconnectAfterMs: (tries) => {
                return [1000, 2000, 5000, 10000][tries - 1] || 10000;
            },
        });

        socket.connect();
        socketRef.current = socket;

        // Join the game channel
        const channel = socket.channel(`game:${roomCode}`, {
            nickname,
            player_id: playerId,
        });

        channelRef.current = channel;

        // Handle join response
        channel
            .join()
            .receive('ok', (response: Room & { current_question?: Question }) => {
                console.log('✅ Joined game channel', response);
                setConnected(true);
                setError(null);
                if (onGameState) {
                    onGameState(response);
                }
                // If there's a current question (game in progress), trigger the handler
                if (response.current_question && onQuestionRevealed) {
                    console.log('❓ Received current question on join:', response.current_question);
                    onQuestionRevealed(response.current_question);
                }
            })
            .receive('error', (response: { reason?: string }) => {
                console.error('❌ Failed to join channel', response);
                setError(response.reason || 'Failed to join game');
                setConnected(false);
            });

        // Listen to events
        channel.on('player_joined', (data: PlayerJoinedData) => {
            console.log('👤 Player joined:', data);
            if (onPlayerJoined) onPlayerJoined(data);
        });

        channel.on('player_disconnected', (data: PlayerDisconnectedData) => {
            console.log('👤 Player disconnected:', data);
            if (onPlayerDisconnected) onPlayerDisconnected(data);
        });

        channel.on('game_started', (data: GameStartedData) => {
            console.log('🎮 Game started:', data);
            if (onGameStarted) onGameStarted(data);
        });

        channel.on('question_revealed', (data: Question) => {
            console.log('❓ Question revealed:', data);
            if (onQuestionRevealed) onQuestionRevealed(data);
        });

        channel.on('player_committed', (data: PlayerCommittedData) => {
            console.log('✅ Player committed answer:', data);
            if (onPlayerCommitted) onPlayerCommitted(data);
        });

        channel.on('answer_revealed', (data: AnswerRevealedData) => {
            console.log('🔓 Answer revealed:', data);
            if (onAnswerRevealed) onAnswerRevealed(data);
        });

        channel.on('round_scored', (data: RoundScoredData) => {
            console.log('🏆 Round scored:', data);
            if (onRoundScored) onRoundScored(data);
        });

        channel.on('round_started', (data: RoundStartedData) => {
            console.log('🔄 New round started:', data);
            if (onRoundStarted) onRoundStarted(data);
        });

        channel.on('game_ended', (data: GameEndedData) => {
            console.log('🎉 Game ended:', data);
            if (onGameEnded) onGameEnded(data);
        });

        channel.on('rematch_vote_updated', (data: any) => {
            console.log('🔄 Rematch vote updated:', data);
            if (onRematchVoteUpdated) onRematchVoteUpdated(data);
        });

        channel.on('rematch_starting', () => {
            console.log('🎮 Rematch starting!');
            if (onRematchStarting) onRematchStarting();
        });

        channel.on('rematch_approved', (data: any) => {
            console.log('✅ Rematch approved!', data);
            if (onRematchStarting) onRematchStarting();
        });

        channel.on('rematch_cancelled', (data: any) => {
            console.log('❌ Rematch cancelled!', data);
            if (onRematchCancelled) onRematchCancelled(data);
        });

        // Cleanup on unmount
        return () => {
            channel.leave();
            socket.disconnect();
        };
        // eslint-disable-next-line react-hooks/exhaustive-deps
    }, [roomCode, playerId, nickname]); // Only reconnect if these core values change

    // Helper functions to send messages
    const startGame = () => {
        return new Promise((resolve, reject) => {
            channelRef.current
                ?.push('start_game', {})
                .receive('ok', resolve)
                .receive('error', reject);
        });
    };

    const requestQuestion = (round: number) => {
        return new Promise((resolve, reject) => {
            channelRef.current
                ?.push('request_question', { round })
                .receive('ok', resolve)
                .receive('error', reject);
        });
    };

    const commitAnswer = (answer: string, questionId: string) => {
        return new Promise((resolve, reject) => {
            channelRef.current
                ?.push('commit_answer', { answer, question_id: questionId })
                .receive('ok', resolve)
                .receive('error', reject);
        });
    };

    const getState = () => {
        return new Promise((resolve, reject) => {
            channelRef.current
                ?.push('get_state', {})
                .receive('ok', resolve)
                .receive('error', reject);
        });
    };

    const scoreRound = (correctAnswer: string, round: number) => {
        return new Promise((resolve, reject) => {
            channelRef.current
                ?.push('score_round', { correct_answer: correctAnswer, round })
                .receive('ok', resolve)
                .receive('error', reject);
        });
    };

    const nextRound = () => {
        return new Promise((resolve, reject) => {
            channelRef.current
                ?.push('next_round', {})
                .receive('ok', resolve)
                .receive('error', reject);
        });
    };

    const requestRematch = () => {
        return new Promise((resolve, reject) => {
            channelRef.current
                ?.push('request_rematch', {})
                .receive('ok', resolve)
                .receive('error', reject);
        });
    };

    const declineRematch = () => {
        return new Promise((resolve, reject) => {
            channelRef.current
                ?.push('decline_rematch', {})
                .receive('ok', resolve)
                .receive('error', reject);
        });
    };

    return {
        connected,
        error,
        startGame,
        requestQuestion,
        commitAnswer,
        getState,
        scoreRound,
        nextRound,
        requestRematch,
        declineRematch,
    };
}