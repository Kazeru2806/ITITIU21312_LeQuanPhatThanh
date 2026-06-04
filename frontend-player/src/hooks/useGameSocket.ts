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
    final_scores?: LeaderboardEntry[];
    winner?: LeaderboardEntry;
    message?: string;
    forced?: boolean;
    room_closed?: boolean;
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
    onTruthDiscussionProgress?: (data: {
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
    onTruthDiscussionProgress,
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
    const cbRef = useRef<UseGameSocketProps>({ roomCode, playerId, nickname });
    cbRef.current = {
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
        onTruthDiscussionProgress,
        onTruthResume,
        onPlayersSync,
        onHostChanged,
        onRoomClosed,
    };

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
                const c = cbRef.current;
                if (c.onGameState) c.onGameState(response);
                if (response.truth_resume && truthResumeRef.current) {
                    truthResumeRef.current(response.truth_resume);
                } else if (response.current_question && c.onQuestionRevealed) {
                    console.log('❓ Received current question on join:', response.current_question);
                    c.onQuestionRevealed(response.current_question);
                }
            })
            .receive('error', (response: { reason?: string }) => {
                console.error('❌ Failed to join channel', response);
                setError(response.reason || 'Failed to join game');
                setConnected(false);
            });

        // Listen to events
        channel.on('player_joined', (data: PlayerJoinedData) => {
            cbRef.current.onPlayerJoined?.(data);
        });

        channel.on('player_disconnected', (data: PlayerDisconnectedData) => {
            cbRef.current.onPlayerDisconnected?.(data);
        });

        channel.on('players_sync', (data: { players?: PlayerJoinedData['players']; host_id?: string }) => {
            if (data.players) cbRef.current.onPlayersSync?.({ players: data.players, host_id: data.host_id });
        });

        channel.on('player_left', (data: PlayerDisconnectedData) => {
            cbRef.current.onPlayerDisconnected?.(data);
            if (data.players) cbRef.current.onPlayersSync?.({ players: data.players });
        });

        channel.on('host_changed', (data: { host_id: string; host_nickname: string }) => {
            cbRef.current.onHostChanged?.(data);
        });

        channel.on('room_closed', (data: { message: string; redirect_seconds?: number }) => {
            cbRef.current.onRoomClosed?.(data);
        });

        channel.on('game_started', (data: GameStartedData) => {
            cbRef.current.onGameStarted?.(data);
        });

        channel.on('discussion_started', (data: DiscussionStartedData) => {
            cbRef.current.onDiscussionStarted?.(data);
        });

        channel.on('question_revealed', (data: Question) => {
            cbRef.current.onQuestionRevealed?.(data);
        });

        channel.on('player_committed', (data: PlayerCommittedData) => {
            cbRef.current.onPlayerCommitted?.(data);
        });

        channel.on('answer_revealed', (data: AnswerRevealedData) => {
            cbRef.current.onAnswerRevealed?.(data);
        });

        channel.on('round_scored', (data: RoundScoredData) => {
            cbRef.current.onRoundScored?.(data);
        });

        channel.on('truth_stats_updated', (data: any) => {
            cbRef.current.onTruthStatsUpdated?.(data);
        });

        channel.on('distortion_used', (data: any) => {
            cbRef.current.onDistortionUsed?.(data);
        });

        channel.on('round_started', (data: RoundStartedData) => {
            cbRef.current.onRoundStarted?.(data);
        });

        channel.on('game_state', (data: Room & { truth_resume?: TruthResume }) => {
            cbRef.current.onGameState?.(data);
            if (data.truth_resume && truthResumeRef.current) {
                truthResumeRef.current(data.truth_resume);
            }
        });

        channel.on('truth_results_progress', (data: any) => {
            truthProgressRef.current?.(data);
        });

        channel.on('truth_discussion_progress', (data: any) => {
            cbRef.current.onTruthDiscussionProgress?.(data);
        });

        channel.on('game_ended', (data: GameEndedData) => {
            cbRef.current.onGameEnded?.(data);
        });

        channel.on('rematch_vote_updated', (data: any) => {
            cbRef.current.onRematchVoteUpdated?.(data);
        });

        channel.on('rematch_starting', () => {
            cbRef.current.onRematchStarting?.();
        });

        channel.on('rematch_approved', () => {
            cbRef.current.onRematchStarting?.();
        });

        channel.on('rematch_cancelled', (data: any) => {
            cbRef.current.onRematchCancelled?.(data);
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

    const phoenixError = (err: { reason?: string }) =>
        new Error(err?.reason || 'Request failed');

    const pushWithTimestamp = (event: string, payload: Record<string, any> = {}) => {
        const channel = channelRef.current;
        if (!channel) {
            return {
                receive: () => ({
                    receive: (_status: string, _cb: unknown) => ({
                        receive: () => ({
                            receive: () => ({}),
                        }),
                    }),
                }),
            };
        }
        return channel.push(event, { ...payload, client_timestamp_ms: Date.now() });
    };

    const pushAsync = (event: string, payload: Record<string, any> = {}) =>
        new Promise((resolve, reject) => {
            const channel = channelRef.current;
            if (!channel) {
                reject(new Error('Not connected to game server'));
                return;
            }
            channel
                .push(event, { ...payload, client_timestamp_ms: Date.now() })
                .receive('ok', resolve)
                .receive('error', (err: { reason?: string }) => reject(phoenixError(err)));
        });

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

    const useDistortion = (action: string, payload: Record<string, any> = {}) =>
        pushAsync('use_distortion', { action, ...payload });

    const lockFakeOption = () => {
        return new Promise((resolve, reject) => {
            pushWithTimestamp('lock_fake_option', {})
                .receive('ok', resolve)
                .receive('error', reject);
        });
    };

    const setFakeOptionText = (fakeText: string) =>
        pushAsync('set_fake_option_text', { fake_text: fakeText });

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

    const truthResultsReady = (payload: Record<string, unknown> = {}) =>
        pushAsync('truth_results_ready', payload);

    const truthDiscussionReady = (payload: Record<string, unknown> = {}) =>
        pushAsync('truth_discussion_ready', payload);

    const leaveRoom = () => {
        return new Promise<void>((resolve) => {
            const channel = channelRef.current;
            if (!channel) {
                resolve();
                return;
            }
            let settled = false;
            const finish = () => {
                if (settled) return;
                settled = true;
                channel.leave();
                socketRef.current?.disconnect();
                resolve();
            };
            window.setTimeout(finish, 3000);
            channel
                .push('leave_room', {})
                .receive('ok', finish)
                .receive('error', finish);
        });
    };

    const closeRoom = () => {
        return new Promise<void>((resolve) => {
            const channel = channelRef.current;
            if (!channel) {
                resolve();
                return;
            }
            let settled = false;
            const finish = () => {
                if (settled) return;
                settled = true;
                channel.leave();
                socketRef.current?.disconnect();
                resolve();
            };
            window.setTimeout(finish, 3000);
            channel
                .push('close_room', {})
                .receive('ok', finish)
                .receive('error', finish);
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
        truthDiscussionReady,
    };
}