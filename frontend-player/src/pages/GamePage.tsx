import { useEffect, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { useGameStore } from '../store/gameStore';
import { useGameSocket } from '../hooks/useGameSocket';
import type { TruthResume } from '../types/game';
import { api } from '../lib/api';
import { usePhaseTimer } from '../lib/usePhaseTimer';
import { RoomClosedBanner } from '../components/RoomClosedBanner';
import { PhoThePhoenix } from '../components/PhoThePhoenix';
import { LotusPattern, DragonPattern, LanternPattern, BambooPattern } from '../components/VietnamesePatterns';

export function GamePage() {
    const navigate = useNavigate();
    const [storeHydrated, setStoreHydrated] = useState(() => useGameStore.persist.hasHydrated());
    const [phaseEndsAtMs, setPhaseEndsAtMs] = useState<number | null>(null);
    const [roomClosed, setRoomClosed] = useState<{ message: string; redirect_seconds?: number } | null>(null);
    const [committedIds, setCommittedIds] = useState<Set<string>>(new Set());
    const [showResult, setShowResult] = useState(false);
    const [phase, setPhase] = useState<'transition' | 'discussion' | 'answering' | 'results'>('discussion');
    const [prediction, setPrediction] = useState<string | null>(null);
    const [truthStats, setTruthStats] = useState<Array<{ player_id: string; tp: number; di: number; ps: number; charges: number }> | null>(null);
    const [pendingDistortion, setPendingDistortion] = useState<'remove_option' | 'swap_category' | 'force_blind' | 'inject_fake_option' | null>(null);
    const [distortionToast, setDistortionToast] = useState<string | null>(null);
    const [distortionTarget, setDistortionTarget] = useState<string>('');
    const [fakeOptionText, setFakeOptionText] = useState('');
    const [distortionLocked, setDistortionLocked] = useState(false);
    const [fakeLockConfirmed, setFakeLockConfirmed] = useState(false);
    const [fakePreview, setFakePreview] = useState<any | null>(null);
    const [shuffleOrder, setShuffleOrder] = useState<string[] | null>(null);
    const [discussionMeta, setDiscussionMeta] = useState<{
        categoryLabel?: string;
        timelineLabels?: string[];
        optionIds?: string[];
    } | null>(null);
    const [resultsReadySent, setResultsReadySent] = useState(false);
    const [resultsReadyProgress, setResultsReadyProgress] = useState<{ acked: number; total: number } | null>(null);

    const {
        playerId,
        roomCode,
        nickname,
        currentRound,
        totalRounds,
        mode,
        currentQuestion,
        selectedAnswer,
        hasCommitted,
        players,
        reset,
        setQuestion,
        setSelectedAnswer,
        setHasCommitted,
        setRound,
        setMode,
        setGameState,
    } = useGameStore();

    const timeLeft = usePhaseTimer(
        phase === 'answering' ? phaseEndsAtMs : null,
        currentQuestion?.time_limit ?? 15
    );
    const discussionLeft = usePhaseTimer(phase === 'discussion' ? phaseEndsAtMs : null, 15);

    // Keep the players list in sync when selecting distortions on results screen.
    useEffect(() => {
        if (mode !== 'truth_collapse') return;
        if (phase !== 'results') return;
        if (!roomCode) return;

        let cancelled = false;
        (async () => {
            try {
                const res = await api.getPlayers(roomCode);
                if (!cancelled && res.success && res.players) {
                    useGameStore.getState().setPlayers(res.players as any);
                }
            } catch {
                // ignore
            }
        })();

        return () => {
            cancelled = true;
        };
    }, [mode, phase, roomCode]);

    const normalizeDiscussionOptionIds = (ids?: string[]) => {
        const cleaned = (ids || []).filter(Boolean);
        if (currentRound <= 1) return cleaned.length >= 4 ? cleaned : ['A', 'B', 'C', 'D'];
        return cleaned.length > 0 ? cleaned : ['A', 'B', 'C', 'D'];
    };

    useEffect(() => {
        if (useGameStore.persist.hasHydrated()) setStoreHydrated(true);
        return useGameStore.persist.onFinishHydration(() => setStoreHydrated(true));
    }, []);

    useEffect(() => {
        if (!storeHydrated) return;
        if (!playerId || !roomCode || !nickname) {
            navigate('/');
        }
    }, [storeHydrated, playerId, roomCode, nickname, navigate]);

    const applyTruthResume = (resume: TruthResume) => {
        if (resume.phase === 'transition') {
            setPhase('transition');
            setQuestion(null);
            setShowResult(false);
            setResultsReadySent(false);
            setResultsReadyProgress(null);
            return;
        }
        if (resume.phase === 'discussion') {
            setPhase('discussion');
            setQuestion(null);
            setShowResult(false);
            setHasCommitted(false);
            setSelectedAnswer(null);
            setPrediction(null);
            setShuffleOrder(null);
            setPhaseEndsAtMs(
                resume.phase_ends_at_ms ??
                    Date.now() + (resume.discussion_seconds ?? 15) * 1000
            );
            setDiscussionMeta({
                categoryLabel: resume.category_label,
                timelineLabels: resume.category_timeline_labels,
                optionIds: normalizeDiscussionOptionIds(resume.options),
            });
            setResultsReadySent(false);
            setResultsReadyProgress(null);
            setPendingDistortion(null);
            setDistortionLocked(false);
            setDistortionTarget('');
            setFakeOptionText('');
            setFakeLockConfirmed(false);
            setFakePreview(null);
            return;
        }
        if (resume.phase === 'answering' && resume.current_question) {
            const cq = resume.current_question;
            const removeMap = (cq as any).remove_targets as Record<string, string[]> | undefined;
            const blocked = new Set((playerId && removeMap?.[playerId]) || []);
            const optIds = (cq.options || []).filter((o) => !blocked.has(o));
            const q = {
                id: cq.id,
                options: optIds,
                time_limit: cq.time_limit,
                shuffle_targets: cq.shuffle_targets,
            };
            setQuestion(q);
            setPhaseEndsAtMs(
                resume.phase_ends_at_ms ?? Date.now() + (resume.time_left ?? cq.time_limit) * 1000
            );
            setShowResult(false);
            setPhase('answering');
            setResultsReadySent(false);
            setResultsReadyProgress(null);
            setPendingDistortion(null);
            setDistortionLocked(false);
            setDistortionTarget('');
            setFakeOptionText('');
            setFakeLockConfirmed(false);
            setFakePreview(null);

            const pid = useGameStore.getState().playerId;
            const targets = cq.shuffle_targets;
            const base = optIds.length ? optIds : ['A', 'B', 'C', 'D'];
            if (targets?.length && pid && targets.includes(pid)) {
                setShuffleOrder([...base].sort(() => Math.random() - 0.5));
            } else {
                setShuffleOrder(null);
            }
            return;
        }
        if (resume.phase === 'results') {
            setPhase('results');
            setShowResult(true);
            if (resume.stats?.length) setTruthStats(resume.stats);
            setResultsReadySent(false);
            const connected = useGameStore.getState().players.filter((p) => p.connected).length;
            setResultsReadyProgress({ acked: 0, total: connected || useGameStore.getState().players.length || 0 });
        }
    };

    const { commitAnswer, submitPrediction, useDistortion, truthResultsReady, lockFakeOption, setFakeOptionText: submitFakeOptionTextApi, leaveRoom } = useGameSocket({
        roomCode: roomCode || '',
        playerId: playerId || '',
        nickname: nickname || '',
        onGameState: (state: any) => {
            if (state.mode) setMode(state.mode);
            if (state.state) setGameState(state.state);
            if (state.current_round != null && state.total_rounds != null) {
                setRound(state.current_round, state.total_rounds);
            }
            if (state.players) {
                useGameStore.getState().setPlayers(state.players);
            }
            if (state.truth_resume) {
                applyTruthResume(state.truth_resume);
            }
        },
        onTruthResume: applyTruthResume,
        onGameStarted: (data) => {
            console.log('🎮 Game started in GamePage:', data);
            if (data.mode) setMode(data.mode as any);
            setRound(data.round, data.total_rounds);
            setQuestion(null);
            setShowResult(false);
            setHasCommitted(false);
            setSelectedAnswer(null);
            setPhase('discussion');
            setResultsReadySent(false);
            setResultsReadyProgress(null);
            setPendingDistortion(null);
            setDistortionLocked(false);
            setDistortionTarget('');
            setFakeOptionText('');
            setFakeLockConfirmed(false);
            setFakePreview(null);
            if (data.mode === 'truth_collapse') {
                setPhaseEndsAtMs(Date.now() + 15 * 1000);
                if (data.truth_theme?.category_label) {
                    setDiscussionMeta({
                        categoryLabel: data.truth_theme.category_label,
                        timelineLabels: [],
                        optionIds: normalizeDiscussionOptionIds(['A', 'B', 'C', 'D']),
                    });
                } else {
                    setDiscussionMeta({
                        categoryLabel: undefined,
                        timelineLabels: [],
                        optionIds: normalizeDiscussionOptionIds(['A', 'B', 'C', 'D']),
                    });
                }
            } else {
                setDiscussionMeta(null);
            }
        },
        onDiscussionStarted: (data) => {
            if (data.mode) setMode(data.mode as any);
            setPhase('discussion');
            setQuestion(null);
            setShowResult(false);
            setHasCommitted(false);
            setSelectedAnswer(null);
            setPrediction(null);
            setShuffleOrder(null);
            setPhaseEndsAtMs(
                (data as { phase_ends_at_ms?: number }).phase_ends_at_ms ??
                    Date.now() + (data.discussion_seconds ?? 15) * 1000
            );
            setDiscussionMeta({
                categoryLabel: data.category_label,
                timelineLabels: data.category_timeline_labels,
                optionIds: normalizeDiscussionOptionIds(data.options),
            });
            setPendingDistortion(null);
            setDistortionLocked(false);
            setDistortionTarget('');
            setFakeOptionText('');
            setFakeLockConfirmed(false);
            setFakePreview(null);
        },
        onQuestionRevealed: (question) => {
            console.log('❓ Question revealed:', question);
            const removeMap = (question as any).remove_targets as Record<string, string[]> | undefined;
            const pid = useGameStore.getState().playerId;
            const blocked = new Set((pid && removeMap?.[pid]) || []);
            const rawOpts = (question.options as any[]) || [];
            const filteredOpts = rawOpts.filter((o) => {
                const id = typeof o === 'string' ? o : o?.id;
                return !blocked.has(id);
            });

            const q = { ...question, options: filteredOpts };
            setQuestion(q);
            setPhaseEndsAtMs(
                (question as { phase_ends_at_ms?: number }).phase_ends_at_ms ??
                    Date.now() + q.time_limit * 1000
            );
            setShowResult(false);
            setPhase('answering');

            const targets = (question as any).shuffle_targets as string[] | undefined;
            const ids = filteredOpts.map((o) => (typeof o === 'string' ? o : o?.id)).filter(Boolean);
            const base = ids.length ? ids : ['A', 'B', 'C', 'D'];

            if (targets?.length && pid && targets.includes(pid)) {
                setShuffleOrder([...base].sort(() => Math.random() - 0.5));
            } else {
                setShuffleOrder(null);
            }
        },
        onPlayerCommitted: (data) => {
            setCommittedIds((prev) => new Set(prev).add(data.player_id));
        },
        onPlayersSync: (data) => {
            if (data.players) useGameStore.getState().setPlayers(data.players as any);
            const me = data.players?.find((p) => p.id === playerId);
            if (me && playerId && nickname) {
                useGameStore.getState().setPlayerInfo(playerId, nickname, me.is_host);
            }
        },
        onHostChanged: (data) => {
            const list = useGameStore.getState().players;
            if (list.length) {
                useGameStore.getState().setPlayers(
                    list.map((p) => ({ ...p, is_host: p.id === data.host_id }))
                );
            }
            if (playerId && nickname) {
                useGameStore.getState().setPlayerInfo(playerId, nickname, data.host_id === playerId);
            }
        },
        onPlayerDisconnected: (data) => {
            if (data.players?.length) useGameStore.getState().setPlayers(data.players as any);
        },
        onRoomClosed: (data) => {
            setRoomClosed({
                message: data.message || 'The host screen closed. This room has ended.',
                redirect_seconds: data.redirect_seconds ?? 30,
            });
        },
        onRoundScored: (data) => {
            console.log('Round scored (player view):', data);
            setShowResult(true);
            setPhase('results');
            if (data?.stats) setTruthStats(data.stats);
            setPendingDistortion(null);
            setDistortionLocked(false);
            setDistortionTarget('');
            setFakeOptionText('');
            setResultsReadySent(false);
            setResultsReadyProgress(null);
            setCommittedIds(new Set());
        },
        onRoundStarted: (data: any) => {
            console.log('Round started:', data);
            setRound(data.round, data.total_rounds);
            setShowResult(false);
            setHasCommitted(false);
            setSelectedAnswer(null);
            setPhase('discussion');
            setQuestion(null);
            setResultsReadySent(false);
            setResultsReadyProgress(null);
            setPendingDistortion(null);
            setDistortionLocked(false);
            setDistortionTarget('');
            setFakeOptionText('');
            setFakeLockConfirmed(false);
            setFakePreview(null);
            if (data.mode === 'truth_collapse') {
                setPhaseEndsAtMs(
                (data as { phase_ends_at_ms?: number }).phase_ends_at_ms ??
                    Date.now() + (data.discussion_seconds ?? 15) * 1000
            );
                if (data.category_label) {
                    setDiscussionMeta({
                        categoryLabel: data.category_label,
                        timelineLabels: data.category_timeline_labels ?? [],
                        optionIds: normalizeDiscussionOptionIds(data.option_ids),
                    });
                }
            }
        },
        onTruthResultsProgress: (data) => {
            setResultsReadyProgress({ acked: data.acked_count, total: data.total });
        },
        onGameEnded: () => {
            console.log('🎉 Game ended! Navigating to results...');
            // Small delay to let players see final scores
            setTimeout(() => {
                navigate('/results');
            }, 2000);
        },
    });

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

    const handleReturnMain = async () => {
        try {
            await leaveRoom();
        } catch {
            // still navigate home
        }
        reset();
        navigate('/');
    };

    const myTruth = truthStats?.find((s) => s.player_id === playerId) || null;
    const myCharges = myTruth?.charges ?? 0;

    const handleSubmitPrediction = async (opt: string) => {
        try {
            setPrediction(opt);
            await submitPrediction(opt);
        } catch (err) {
            console.error('Failed to submit prediction:', err);
        }
    };

    const handleTruthResultsReady = async () => {
        try {
            if (!distortionLocked && pendingDistortion) {
                if (pendingDistortion === 'remove_option' && !distortionTarget) {
                    setDistortionToast('Choose a target player for Remove option.');
                    return;
                }
                if (pendingDistortion === 'inject_fake_option' && !fakeLockConfirmed) {
                    setDistortionToast('Confirm fake-option lock first.');
                    return;
                }

                if (pendingDistortion === 'inject_fake_option' && fakeOptionText.trim().length < 3) {
                    setDistortionToast('Type fake option text (at least 3 chars).');
                    return;
                }

                if (pendingDistortion === 'inject_fake_option') {
                    await submitFakeOptionTextApi(fakeOptionText);
                } else {
                    const payload: Record<string, any> =
                        pendingDistortion === 'remove_option'
                            ? { target_player_id: distortionTarget }
                            : {};
                    await useDistortion(pendingDistortion, payload);
                }
                setDistortionLocked(true);
            }

            await truthResultsReady();
            setResultsReadySent(true);
        } catch (e) {
            console.error('truth_results_ready failed', e);
        }
    };

    const handleToggleDistortion = (action: 'remove_option' | 'swap_category' | 'force_blind' | 'inject_fake_option') => {
        if (distortionLocked) return;

        if (pendingDistortion === action) {
            if (action === 'inject_fake_option' && fakeLockConfirmed) {
                // No return after confirming fake lock.
                return;
            }
            setPendingDistortion(null);
            setDistortionTarget('');
            setFakeOptionText('');
            setFakeLockConfirmed(false);
            setFakePreview(null);
            return;
        }

        setPendingDistortion(action);
        setDistortionTarget('');
        setFakeOptionText('');
        setFakeLockConfirmed(false);
        setFakePreview(null);
    };

    const handleConfirmFakeLock = async () => {
        try {
            const res: any = await lockFakeOption();
            setFakeLockConfirmed(true);
            setFakePreview(res?.preview_question || null);
            setDistortionToast('Fake lock confirmed. Enter your sabotaged answer.');
            window.setTimeout(() => {
                setDistortionToast(null);
            }, 2200);
        } catch (err) {
            const reason =
                typeof err === 'object' && err !== null ? (err as any).reason || (err as any).message : null;
            setDistortionToast(reason || 'Failed to confirm fake lock.');
        }
    };

    // Rounds now advance automatically - no manual controls needed

    if (!storeHydrated) {
        return (
            <div className="min-h-screen flex items-center justify-center bg-gradient-to-b from-purple-50 to-pink-50">
                <p className="text-purple-700 font-bold text-lg">Restoring session…</p>
            </div>
        );
    }

    if (!playerId || !roomCode) {
        return null;
    }

    const predictOptions =
        discussionMeta?.optionIds?.length ? discussionMeta.optionIds : ['A', 'B', 'C', 'D'];

    if (mode === 'truth_collapse' && phase === 'transition') {
        return (
            <div className="min-h-screen relative overflow-hidden flex flex-col items-center justify-center p-6">
                <PhoThePhoenix className="w-28 h-32 drop-shadow-lg mb-4" />
                <h2
                    className="text-3xl font-black text-center mb-2"
                    style={{ fontFamily: "'Bangers', cursive", color: '#9D4EDD' }}
                >
                    Next round
                </h2>
                <p className="text-center text-gray-600 font-semibold max-w-md">
                    Syncing with the room… The discussion phase will appear in a moment.
                </p>
            </div>
        );
    }

    if (mode === 'truth_collapse' && phase === 'discussion') {
        return (
            <div className="min-h-screen relative overflow-hidden flex flex-col p-4 lg:p-6">
                <div className="absolute inset-0 overflow-hidden pointer-events-none">
                    <LotusPattern className="absolute top-10 left-10 w-20 h-20 animate-pulse" />
                    <DragonPattern className="absolute bottom-1/3 left-10 w-40 h-24 opacity-60" />
                </div>
                <div className="fixed inset-0 pointer-events-none overflow-hidden -z-10">
                    <div
                        className="absolute rounded-full blur-3xl opacity-20 animate-pulse"
                        style={{
                            width: '400px',
                            height: '400px',
                            background: 'radial-gradient(circle, #FF6B9D 0%, transparent 70%)',
                            top: '10%',
                            left: '-10%',
                            animationDuration: '4s',
                        }}
                    />
                </div>
                <div className="flex items-center mb-6 relative z-10 gap-4">
                    <div className="bg-white/90 backdrop-blur-sm px-6 py-3 rounded-full text-purple-700 font-black text-lg border-2 border-purple-200">
                        Round {currentRound}/{totalRounds}
                    </div>
                    <div className="bg-white/90 backdrop-blur-sm px-6 py-3 rounded-full text-pink-700 font-black text-lg border-2 border-pink-200 mx-auto">
                        {nickname}
                    </div>
                    <button
                        type="button"
                        onClick={handleReturnMain}
                        className="px-4 py-2 rounded-xl border-2 border-purple-200 bg-white text-purple-700 font-bold hover:bg-purple-50"
                    >
                        Return to main screen
                    </button>
                </div>
                <div className="flex-1 flex items-center justify-center relative z-10">
                    <div
                        className="w-full max-w-lg bg-white/95 backdrop-blur-sm rounded-3xl shadow-2xl p-8 border-4 border-purple-200"
                        style={{ borderRadius: '2rem' }}
                    >
                        <div className="flex justify-center mb-4">
                            <PhoThePhoenix className="w-32 h-36 drop-shadow-lg" />
                        </div>
                        <h2
                            className="text-3xl font-black text-center mb-2"
                            style={{ fontFamily: "'Bangers', cursive", color: '#9D4EDD' }}
                        >
                            Discussion phase
                        </h2>
                        <p className="text-center text-gray-600 font-semibold mb-2">
                            Timer: <span className="text-pink-600 font-black">{discussionLeft}s</span>
                        </p>
                        <p className="text-center text-gray-600 text-sm mb-6">
                            Watch the host screen for the full question. Lock in a prediction below.
                        </p>
                        <div className="mb-6 p-4 rounded-xl border-2 border-purple-100 bg-gradient-to-r from-purple-50 to-pink-50 min-h-[120px]">
                            <p className="text-xs font-black text-purple-600 uppercase tracking-widest">Theme</p>
                            <p className="text-2xl font-black text-pink-700">
                                {discussionMeta?.categoryLabel ?? 'Loading theme…'}
                            </p>
                            {discussionMeta?.timelineLabels && discussionMeta.timelineLabels.length > 1 ? (
                                <p className="text-sm text-gray-700 mt-2">
                                    <span className="font-bold text-purple-700">After swaps: </span>
                                    {discussionMeta.timelineLabels.join(' → ')}
                                </p>
                            ) : (
                                <p className="text-sm text-gray-600 mt-2">
                                    The category stays put each round until someone uses Swap Category.
                                </p>
                            )}
                        </div>
                        <p className="text-center font-bold text-purple-800 mb-3">
                            Which option will be picked the most?
                        </p>
                        <div
                            className={`grid gap-3 ${
                                predictOptions.length <= 2 ? 'grid-cols-2' : predictOptions.length === 3 ? 'grid-cols-3' : 'grid-cols-2 sm:grid-cols-4'
                            }`}
                        >
                            {predictOptions.map((opt) => (
                                <button
                                    key={opt}
                                    type="button"
                                    onClick={() => handleSubmitPrediction(opt)}
                                    className={`py-3 rounded-xl border-2 font-black ${
                                        prediction === opt
                                            ? 'bg-purple-600 text-white border-purple-600'
                                            : 'bg-white text-purple-700 border-purple-200 hover:border-purple-400'
                                    }`}
                                >
                                    {opt}
                                </button>
                            ))}
                        </div>
                    </div>
                </div>
            </div>
        );
    }

    return (
        <div className="min-h-screen relative overflow-hidden flex flex-col p-4 lg:p-6">
            {roomClosed && (
                <RoomClosedBanner
                    message={roomClosed.message}
                    redirectSeconds={roomClosed.redirect_seconds}
                />
            )}
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
            <div className="flex items-center mb-6 relative z-10 gap-4">
                <div className="bg-white/90 backdrop-blur-sm px-6 py-3 lg:px-8 lg:py-4 rounded-full text-purple-700 font-black text-lg lg:text-xl shadow-lg border-2 border-purple-200">
                    Round {currentRound}/{totalRounds}
                </div>
                <div className="bg-white/90 backdrop-blur-sm px-6 py-3 lg:px-8 lg:py-4 rounded-full text-pink-700 font-black text-lg lg:text-xl shadow-lg border-2 border-pink-200 mx-auto">
                    {nickname}
                </div>
                <button
                    type="button"
                    onClick={handleReturnMain}
                    className="px-4 py-2 rounded-xl border-2 border-purple-200 bg-white text-purple-700 font-bold hover:bg-purple-50"
                >
                    Return to main screen
                </button>
            </div>

            {players.length > 0 && (
                <div className="mb-4 relative z-10 max-w-4xl mx-auto w-full px-2">
                    <div className="grid grid-cols-2 sm:grid-cols-3 md:grid-cols-4 gap-2">
                        {players.map((p) => {
                            const committed = committedIds.has(p.id);
                            const status = !p.connected
                                ? 'Disconnected'
                                : committed
                                  ? 'Answered'
                                  : 'Playing';
                            return (
                                <div
                                    key={p.id}
                                    className={`px-3 py-2 rounded-lg border-2 text-sm font-bold ${
                                        !p.connected
                                            ? 'bg-gray-100 border-gray-300 text-gray-500'
                                            : committed
                                              ? 'bg-green-50 border-green-300 text-green-800'
                                              : 'bg-purple-50 border-purple-200 text-purple-800'
                                    }`}
                                >
                                    {p.nickname}
                                    <span className="block text-xs font-semibold opacity-80">{status}</span>
                                </div>
                            );
                        })}
                    </div>
                </div>
            )}

            {/* Main Content */}
            <div className="flex-1 flex items-center justify-center relative z-10">
                {!currentQuestion ? (
                    <div className="text-center text-white">
                        <div className="mb-6 flex justify-center">
                            <PhoThePhoenix className="w-48 h-56 md:w-64 md:h-72 drop-shadow-2xl" />
                        </div>
                        <h2 className="text-3xl lg:text-4xl font-black mb-2" style={{ fontFamily: "'Bangers', cursive" }}>Preparing question...</h2>
                        <p className="text-xl lg:text-2xl font-semibold opacity-90">Pho is thinking...</p>
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

                                {/* Player Instructions - NO QUESTION TEXT */}
                                <div className="text-center mb-8 lg:mb-10">
                                    <div className="inline-block mb-4 lg:mb-6">
                                        <PhoThePhoenix className="w-24 h-28 drop-shadow-lg" />
                                    </div>
                                    <h2 className="text-3xl lg:text-4xl font-black mb-2 lg:mb-4" style={{
                                        fontFamily: "'Bangers', cursive",
                                        color: "#9D4EDD",
                                        textShadow: "3px 3px 0px #FF6B9D"
                                    }}>
                                        {mode === 'truth_collapse' && phase === 'discussion' ? 'Discussion Phase' : 'Pick your answer'}
                                    </h2>
                                    <p className="text-xl lg:text-2xl text-gray-600 font-semibold">
                                        Look at the host screen for the question
                                    </p>
                                </div>

                                {mode === 'truth_collapse' && phase === 'discussion' && (
                                    <div className="mb-6 p-6 rounded-xl border-2 border-purple-200 bg-gradient-to-r from-purple-50 to-pink-50 text-center">
                                        <p className="text-2xl font-black text-purple-700 mb-2">Discussion: {discussionLeft}s</p>
                                        <p className="text-gray-700 font-semibold mb-4">Make a prediction: which option will be most picked?</p>
                                        <div className="grid grid-cols-4 gap-3">
                                            {['A', 'B', 'C', 'D'].map((opt) => (
                                                <button
                                                    key={opt}
                                                    onClick={() => handleSubmitPrediction(opt)}
                                                    className={`py-3 rounded-xl border-2 font-black ${
                                                        prediction === opt
                                                            ? 'bg-purple-600 text-white border-purple-600'
                                                            : 'bg-white text-purple-700 border-purple-200 hover:border-purple-400'
                                                    }`}
                                                >
                                                    {opt}
                                                </button>
                                            ))}
                                        </div>
                                    </div>
                                )}

                                {/* Answer Options */}
                                <div className="grid grid-cols-1 md:grid-cols-2 gap-4 lg:gap-6">
                                {(() => {
                                    const base = (currentQuestion.options as any[]).map((option) =>
                                        typeof option === 'string' ? option : (option as any).id || option
                                    );
                                    const order = (mode === 'truth_collapse' && shuffleOrder) ? shuffleOrder : base;
                                    const isShuffledView = mode === 'truth_collapse' && !!shuffleOrder;

                                    return order.map((optionId, index) => (
                                        <button
                                            key={`${optionId}-${index}`}
                                            onClick={() => handleSelectAnswer(optionId)}
                                            disabled={mode === 'truth_collapse' ? (phase !== 'answering' || hasCommitted || timeLeft === 0) : (hasCommitted || timeLeft === 0)}
                                            className={`p-6 rounded-2xl font-black text-lg transition-all transform hover:scale-105 border-3 ${
                                                mode === 'truth_collapse' && shuffleOrder
                                                    ? 'truth-option-shuffle-once'
                                                    : ''
                                            } ${selectedAnswer === optionId
                                                    ? 'vietnamese-accent text-white shadow-2xl scale-105 border-transparent vietnamese-glow'
                                                    : 'bg-gradient-to-r from-purple-50 to-pink-50 text-gray-800 hover:from-purple-100 hover:to-pink-100 border-purple-200'
                                                } ${(hasCommitted || timeLeft === 0) && 'opacity-50 cursor-not-allowed hover:scale-100'}`}
                                        >
                                            {isShuffledView ? (
                                                <div className="flex flex-col items-center">
                                                    <span className="font-black">Shuffled choice {index + 1}</span>
                                                    <span className="text-xs opacity-80">This answer has been shuffled</span>
                                                </div>
                                            ) : (
                                                optionId
                                            )}
                                        </button>
                                    ));
                                })()}
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
                                    {selectedAnswer ? 'Lock in answer' : 'Choose an answer'}
                                </button>
                            )}

                            {/* Committed Status */}
                            {hasCommitted && !showResult && (
                                <div className="mt-6 text-center p-5 lg:p-8 bg-gradient-to-r from-purple-50 to-pink-50 rounded-xl border-2 border-purple-200">
                                    <p className="text-purple-700 font-black text-lg lg:text-2xl">
                                        Answer submitted! Waiting for others...
                                    </p>
                                </div>
                            )}

                            {/* Result - Show "Look at screen" instead of actual results */}
                            {showResult && (
                                <div className="mt-6 text-center p-6 lg:p-10 rounded-xl border-3 shadow-lg bg-gradient-to-r from-purple-50 to-pink-50 border-purple-400">
                                    <p className="text-2xl lg:text-4xl font-black mb-2 lg:mb-4 text-purple-700">
                                        Answer submitted!
                                    </p>
                                    <p className="text-xl lg:text-2xl text-gray-700 mt-2 lg:mt-4 font-semibold">
                                        Look at the host screen for results
                                    </p>
                                </div>
                            )}

                            {mode === 'truth_collapse' && phase === 'results' && (
                                <div className="mt-6 p-6 rounded-xl border-2 border-purple-200 bg-white">
                                    <div className="flex items-center justify-between mb-4">
                                        <p className="text-xl font-black text-purple-700">Distortion Power</p>
                                        <p className="text-xl font-black text-pink-700">{myCharges} charges</p>
                                    </div>
                                        {distortionToast && (
                                            <div className="mb-4 p-3 rounded-lg border border-purple-200 bg-purple-50 text-purple-800 font-semibold">
                                                {distortionToast}
                                            </div>
                                        )}
                                    <div className="grid grid-cols-2 gap-3">
                                        <button
                                            onClick={() => handleToggleDistortion('remove_option')}
                                            disabled={myCharges < 2}
                                            className={`py-3 rounded-xl border-2 font-bold disabled:opacity-50 ${pendingDistortion === 'remove_option' ? 'bg-purple-600 text-white border-purple-600' : ''}`}
                                        >
                                            Remove one option from target (2)
                                        </button>
                                        <button
                                            onClick={() => handleToggleDistortion('swap_category')}
                                            disabled={myCharges < 2}
                                            className={`py-3 rounded-xl border-2 font-bold disabled:opacity-50 ${pendingDistortion === 'swap_category' ? 'bg-purple-600 text-white border-purple-600' : ''}`}
                                        >
                                            Swap category (2)
                                        </button>
                                        <button
                                            onClick={() => handleToggleDistortion('force_blind')}
                                            disabled={myCharges < 3}
                                            className={`py-3 rounded-xl border-2 font-bold disabled:opacity-50 ${pendingDistortion === 'force_blind' ? 'bg-purple-600 text-white border-purple-600' : ''}`}
                                        >
                                            Shuffle answers (3)
                                        </button>
                                        <button
                                            onClick={() => handleToggleDistortion('inject_fake_option')}
                                            disabled={myCharges < 4}
                                            className={`py-3 rounded-xl border-2 font-bold disabled:opacity-50 ${pendingDistortion === 'inject_fake_option' ? 'bg-purple-600 text-white border-purple-600' : ''}`}
                                        >
                                            Inject custom fake option (4)
                                        </button>
                                    </div>
                                    {pendingDistortion === 'remove_option' && (
                                        <div className="mt-4 p-3 rounded-xl border border-purple-200 bg-purple-50/70">
                                            <p className="text-sm font-bold text-purple-800 mb-2">Choose target player</p>
                                            <div className="grid grid-cols-1 gap-3">
                                                <div className="grid grid-cols-2 md:grid-cols-3 gap-2">
                                                    {players
                                                        .slice()
                                                        .sort((a, b) => a.nickname.localeCompare(b.nickname))
                                                        .map((p) => (
                                                            <button
                                                                key={p.id}
                                                                type="button"
                                                                onClick={() => setDistortionTarget(p.id)}
                                                                className={`rounded-lg px-3 py-2 border-2 text-sm font-bold ${
                                                                    distortionTarget === p.id
                                                                        ? 'bg-purple-600 text-white border-purple-600'
                                                                        : 'bg-white text-purple-800 border-purple-200'
                                                                }`}
                                                            >
                                                                {p.nickname}
                                                            </button>
                                                        ))}
                                                </div>
                                                {distortionTarget ? (
                                                    <p className="text-sm font-semibold text-purple-800">
                                                        Selected: {players.find((p) => p.id === distortionTarget)?.nickname || 'Unknown'}
                                                    </p>
                                                ) : null}
                                            </div>
                                        </div>
                                    )}

                                    {pendingDistortion === 'inject_fake_option' && (
                                        <div className="mt-4 p-3 rounded-xl border border-purple-200 bg-purple-50/70">
                                            {!fakeLockConfirmed ? (
                                                <div className="space-y-3">
                                                    <p className="text-sm text-purple-800 font-semibold">
                                                        Confirm lock? This reveals the next question preview and cannot be undone.
                                                    </p>
                                                    <div className="grid grid-cols-2 gap-3">
                                                        <button
                                                            type="button"
                                                            onClick={handleConfirmFakeLock}
                                                            className="rounded-xl px-4 py-3 font-black bg-gradient-to-r from-purple-600 to-pink-500 text-white"
                                                        >
                                                            Yes, lock it
                                                        </button>
                                                        <button
                                                            type="button"
                                                            onClick={() => handleToggleDistortion('inject_fake_option')}
                                                            className="rounded-xl px-4 py-3 font-black bg-white border-2 border-purple-200 text-purple-700"
                                                        >
                                                            No, cancel
                                                        </button>
                                                    </div>
                                                </div>
                                            ) : (
                                                <div className="space-y-3">
                                                    <div className="rounded-lg border border-purple-200 bg-white p-3">
                                                        <p className="text-xs uppercase tracking-wide font-bold text-purple-700">Next question preview</p>
                                                        <p className="font-black text-purple-900">{fakePreview?.category_label}</p>
                                                        <p className="text-sm text-gray-700 mt-1">{fakePreview?.text}</p>
                                                    </div>
                                                    <input
                                                        value={fakeOptionText}
                                                        onChange={(e) => setFakeOptionText(e.target.value)}
                                                        maxLength={60}
                                                        placeholder="Type fake answer text (safe language only)"
                                                        className="w-full rounded-xl border-2 border-purple-200 bg-white px-3 py-3 font-semibold text-purple-900"
                                                    />
                                                    <p className="text-xs text-gray-600">
                                                        This locked power is submitted when you press Done.
                                                    </p>
                                                </div>
                                            )}
                                        </div>
                                    )}
                                    <p className="text-sm text-gray-600 mt-3">Use distortions before the next round starts.</p>

                                    <div className="mt-6 p-4 rounded-xl border border-purple-200 bg-purple-50/90">
                                        {resultsReadyProgress ? (
                                            <p className="text-center font-bold text-purple-800 mb-3">
                                                Ready: {resultsReadyProgress.acked}/{resultsReadyProgress.total}
                                            </p>
                                        ) : null}
                                        <button
                                            type="button"
                                            disabled={resultsReadySent}
                                            onClick={handleTruthResultsReady}
                                            className="w-full py-4 rounded-xl font-black text-lg bg-gradient-to-r from-pink-500 to-purple-600 text-white disabled:opacity-60 shadow-lg"
                                        >
                                            {resultsReadySent ? 'Waiting for other players…' : 'Done — ready for next round'}
                                        </button>
                                        <p className="text-xs text-gray-600 mt-2 text-center">
                                            Optional: spend distortions above, then confirm when you are finished. The
                                            round continues early when everyone taps this.
                                        </p>
                                    </div>
                                </div>
                            )}
                        </div>

                        {/* Auto-advance message */}
                        {showResult && (
                            <div className="text-center mt-4 p-5 lg:p-8 bg-gradient-to-r from-purple-50 to-pink-50 rounded-xl border-2 border-purple-200">
                                <p className="text-purple-700 font-black text-lg lg:text-2xl">
                                    Look at the host screen for results and the next question
                                </p>
                            </div>
                        )}
                    </div>
                )}
            </div>
        </div>
    );
}