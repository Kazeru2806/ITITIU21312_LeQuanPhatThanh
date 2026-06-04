import { useEffect, useRef, useState } from 'react';
import { Socket, Channel } from 'phoenix';
import type { Room, Question, LeaderboardEntry, TruthResume } from '../types/game';

import { getWsUrl } from '../lib/backendConfig';

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
    players?: Array<{
        id: string;
        nickname: string;
        score: number;
        connected: boolean;
        is_host: boolean;
    }>;
}

interface GameStartedData {
    round: number;
    total_rounds: number;
    timestamp: string;
    mode?: string;
    truth_theme?: { category?: string; category_label?: string | null };
}

interface DiscussionStartedData {
    round: number;
    discussion_seconds: number;
    mode?: string;
    question_id?: string;
    options?: string[];
    category?: string;
    category_label?: string;
    category_timeline?: string[];
    category_timeline_labels?: string[];
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
    mode?: string;
    message?: string;
    stats?: Array<{ player_id: string; tp: number; di: number; ps: number; charges: number }>;
}

interface RoundStartedData {
    round: number;
    total_rounds: number;
    mode?: string;
    discussion_seconds?: number;
    category?: string;
    category_label?: string;
    category_timeline_labels?: string[];
    option_ids?: string[];
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
    onDiscussionStarted?: (data: DiscussionStartedData) => void;
    onQuestionRevealed?: (question: Question) => void;
    onPlayerCommitted?: (data: PlayerCommittedData) => void;
    onAnswerRevealed?: (data: AnswerRevealedData) => void;
    onRoundScored?: (data: RoundScoredData) => void;
    onRoundStarted?: (data: RoundStartedData) => void;
    onGameEnded?: (data: GameEndedData) => void;
    onTruthStatsUpdated?: (data: { stats: Array<{ player_id: string; tp: number; di: number; ps: number; charges: number }> }) => void;
    onDistortionUsed?: (data: any) => void;
    onRematchVoteUpdated?: (data: any) => void;
    onRematchStarting?: () => void;
    onRematchCancelled?: (data?: any) => void;
    onTruthResultsProgress?: (data: {
        round: number;
        acked_count: number;
        total: number;
        acked_player_ids: string[];
    }) => void;
    onTruthResume?: (resume: TruthResume) => void;
    onPlayersSync?: (data: {
        players: PlayerJoinedData['players'];
        host_id?: string | null;
    }) => void;
    onHostChanged?: (data: { host_id: string; host_nickname: string }) => void;
    onRoomClosed?: (data: { message: string; redirect_seconds?: number; reason?: string }) => void;
}

export function useGameSocket({
    roomCode,
    playerId,
    nickname,
    onGameState,
    onPlayerJoined,
    onPlayerDisconnected,
    onGameStarted,
    onDiscussionStarted,
    onQuestionRevealed,
    onPlayerCommitted,
    onAnswerRevealed,
    onRoundScored,
    onRoundStarted,
    onGameEnded,
    onTruthStatsUpdated,
    onDistortionUsed,
    onRematchVoteUpdated,
    onRematchStarting,
    onRematchCancelled,
    onTruthResultsProgress,
    onTruthResume,
    onPlayersSync,
    onHostChanged,
    onRoomClosed,
}: UseGameSocketProps) {
    const [connected, setConnected] = useState(false);
    const [error, setError] = useState<string | null>(null);

    const socketRef = useRef<Socket | null>(null);
    const channelRef = useRef<Channel | null>(null);
    const truthProgressRef = useRef(onTruthResultsProgress);
    truthProgressRef.current = onTruthResultsProgress;
    const truthResumeRef = useRef(onTruthResume);
    truthResumeRef.current = onTruthResume;

    useEffect(() => {
        // Create socket connection
        const socket = new Socket(getWsUrl(), {
            params: {},
            reconnectAfterMs: (tries) => {
                return [1000, 2000, 5000, 10000][tries - 1] || 10000;
            },
        });

        socket.connect();
        socketRef.current = socket;

        // Join the game channel (normalize to uppercase for consistency with backend)
        const normalizedCode = (roomCode || '').toUpperCase().trim();
        const channel = socket.channel(`game:${normalizedCode}`, {
            nickname,
            player_id: playerId,
        });

        channelRef.current = channel;

        // Handle join response
        channel
            .join()
            .receive('ok', (response: Room & { current_question?: Question; truth_resume?: TruthResume | null }) => {
                console.log('✅ Joined game channel', response);
                setConnected(true);
                setError(null);
                if (onGameState) {
                    onGameState(response);
                }
                if (response.truth_resume && truthResumeRef.current) {
                    truthResumeRef.current(response.truth_resume);
                } else if (response.current_question && onQuestionRevealed) {
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

        channel.on('players_sync', (data: { players?: PlayerJoinedData['players']; host_id?: string }) => {
            if (onPlayersSync && data.players) onPlayersSync(data as { players: NonNullable<PlayerJoinedData['players']>; host_id?: string });
        });

        channel.on('player_left', (data: PlayerDisconnectedData) => {
            if (onPlayerDisconnected) onPlayerDisconnected(data);
            if (onPlayersSync && data.players) onPlayersSync({ players: data.players });
        });

        channel.on('host_changed', (data: { host_id: string; host_nickname: string }) => {
            if (onHostChanged) onHostChanged(data);
        });

        channel.on('room_closed', (data: { message: string; redirect_seconds?: number }) => {
            if (onRoomClosed) onRoomClosed(data);
        });

        channel.on('game_started', (data: GameStartedData) => {
            console.log('🎮 Game started:', data);
            if (onGameStarted) onGameStarted(data);
        });

        channel.on('discussion_started', (data: DiscussionStartedData) => {
            console.log('🗣 Discussion started:', data);
            if (onDiscussionStarted) onDiscussionStarted(data);
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

        channel.on('truth_stats_updated', (data: any) => {
            console.log('🧾 Truth stats updated:', data);
            if (onTruthStatsUpdated) onTruthStatsUpdated(data);
        });

        channel.on('distortion_used', (data: any) => {
            console.log('🧩 Distortion used:', data);
            if (onDistortionUsed) onDistortionUsed(data);
        });

        channel.on('round_started', (data: RoundStartedData) => {
            console.log('🔄 New round started:', data);
            if (onRoundStarted) onRoundStarted(data);
        });

        channel.on('truth_results_progress', (data: any) => {
            console.log('✓ Truth results ready:', data);
            truthProgressRef.current?.(data);
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

        const heartbeat = () => {
            const ch = channelRef.current;
            if (ch) ch.push('heartbeat', {});
        };

        const hbId = window.setInterval(heartbeat, 10_000);

        const onVis = () => {
            if (document.visibilityState === 'visible') heartbeat();
        };
        document.addEventListener('visibilitychange', onVis);

        return () => {
            window.clearInterval(hbId);
            document.removeEventListener('visibilitychange', onVis);
            channel.leave();
            socket.disconnect();
        };
        // eslint-disable-next-line react-hooks/exhaustive-deps
    }, [roomCode, playerId, nickname]);

    // Helper functions to send messages
    const pushWithTimestamp = (event: string, payload: Record<string, any> = {}) => {
        const channel = channelRef.current;
        if (!channel) return null;
        return channel.push(event, { ...payload, client_timestamp_ms: Date.now() });
    };

    const startGame = () => {
        return new Promise((resolve, reject) => {
            pushWithTimestamp('start_game', {})
                .receive('ok', resolve)
                .receive('error', reject);
        });
    };

    const requestQuestion = (round: number) => {
        return new Promise((resolve, reject) => {
            pushWithTimestamp('request_question', { round })
                .receive('ok', resolve)
                .receive('error', reject);
        });
    };

    const commitAnswer = (answer: string, questionId: string) => {
        return new Promise((resolve, reject) => {
            pushWithTimestamp('commit_answer', { answer, question_id: questionId })
                .receive('ok', resolve)
                .receive('error', reject);
        });
    };

    const submitPrediction = (optionId: string) => {
        return new Promise((resolve, reject) => {
            pushWithTimestamp('submit_prediction', { option_id: optionId })
                .receive('ok', resolve)
                .receive('error', reject);
        });
    };

    const useDistortion = (action: string, payload: Record<string, any> = {}) => {
        return new Promise((resolve, reject) => {
            pushWithTimestamp('use_distortion', { action, ...payload })
                .receive('ok', resolve)
                .receive('error', reject);
        });
    };

    const lockFakeOption = () => {
        return new Promise((resolve, reject) => {
            pushWithTimestamp('lock_fake_option', {})
                .receive('ok', resolve)
                .receive('error', reject);
        });
    };

    const setFakeOptionText = (fakeText: string) => {
        return new Promise((resolve, reject) => {
            pushWithTimestamp('set_fake_option_text', { fake_text: fakeText })
                .receive('ok', resolve)
                .receive('error', reject);
        });
    };

    const getState = () => {
        return new Promise((resolve, reject) => {
            pushWithTimestamp('get_state', {})
                .receive('ok', resolve)
                .receive('error', reject);
        });
    };

    const scoreRound = (correctAnswer: string, round: number) => {
        return new Promise((resolve, reject) => {
            pushWithTimestamp('score_round', { correct_answer: correctAnswer, round })
                .receive('ok', resolve)
                .receive('error', reject);
        });
    };

    const nextRound = () => {
        return new Promise((resolve, reject) => {
            pushWithTimestamp('next_round', {})
                .receive('ok', resolve)
                .receive('error', reject);
        });
    };

    const requestRematch = () => {
        return new Promise((resolve, reject) => {
            pushWithTimestamp('request_rematch', {})
                .receive('ok', resolve)
                .receive('error', reject);
        });
    };

    const declineRematch = () => {
        return new Promise((resolve, reject) => {
            pushWithTimestamp('decline_rematch', {})
                .receive('ok', resolve)
                .receive('error', reject);
        });
    };

    const truthResultsReady = () => {
        return new Promise((resolve, reject) => {
            pushWithTimestamp('truth_results_ready', {})
                .receive('ok', resolve)
                .receive('error', reject);
        });
    };

    const leaveRoom = () => {
        return new Promise<void>((resolve) => {
            const channel = channelRef.current;
            if (!channel) {
                resolve();
                return;
            }
            channel
                .push('leave_room', {})
                .receive('ok', () => {
                    channel.leave();
                    socketRef.current?.disconnect();
                    resolve();
                })
                .receive('error', () => {
                    channel.leave();
                    socketRef.current?.disconnect();
                    resolve();
                });
        });
    };

    const closeRoom = () => {
        return new Promise<void>((resolve) => {
            const channel = channelRef.current;
            if (!channel) {
                resolve();
                return;
            }
            channel
                .push('close_room', {})
                .receive('ok', () => {
                    channel.leave();
                    socketRef.current?.disconnect();
                    resolve();
                })
                .receive('error', () => {
                    channel.leave();
                    socketRef.current?.disconnect();
                    resolve();
                });
        });
    };

    return {
        connected,
        error,
        leaveRoom,
        closeRoom,
        startGame,
        requestQuestion,
        commitAnswer,
        submitPrediction,
        useDistortion,
        lockFakeOption,
        setFakeOptionText,
        getState,
        scoreRound,
        nextRound,
        requestRematch,
        declineRematch,
        truthResultsReady,
    };
}