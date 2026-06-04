import { useEffect, useState, useRef } from 'react';
import { useNavigate } from 'react-router-dom';
import { useDisplayStore } from '../store/displayStore';
import { useDisplaySocket } from '../hooks/useDisplaySocket';
import { usePhaseTimer } from '../lib/usePhaseTimer';
import { api } from '../lib/api';
import { HostPageShell, HostTitle } from '../components/HostPageShell';

export function GameDisplayPage() {
  const navigate = useNavigate();
  const roomCode = useDisplayStore((state) => state.roomCode);
  const mode = useDisplayStore((state) => state.mode);
  const currentRound = useDisplayStore((state) => state.currentRound);
  const totalRounds = useDisplayStore((state) => state.totalRounds);
  const currentQuestion = useDisplayStore((state) => state.currentQuestion);
  const players = useDisplayStore((state) => state.players);
  const roundScores = useDisplayStore((state) => state.roundScores);
  const leaderboard = useDisplayStore((state) => state.leaderboard);
  
  const setMode = useDisplayStore((state) => state.setMode);
  const setQuestion = useDisplayStore((state) => state.setQuestion);
  const setTimeLeft = useDisplayStore((state) => state.setTimeLeft);
  const setRound = useDisplayStore((state) => state.setRound);
  const setPlayers = useDisplayStore((state) => state.setPlayers);
  const setRoundScores = useDisplayStore((state) => state.setRoundScores);
  const setLeaderboard = useDisplayStore((state) => state.setLeaderboard);
  const setGameState = useDisplayStore((state) => state.setGameState);
  const setWinner = useDisplayStore((state) => state.setWinner);

  const [localTimeLeft, setLocalTimeLeft] = useState(15);
  const [committedPlayers, setCommittedPlayers] = useState<Set<string>>(new Set());
  const [phase, setPhase] = useState<'transition' | 'discussion' | 'answering' | 'results'>('discussion');
  const [optionCounts, setOptionCounts] = useState<Record<string, number>>({ A: 0, B: 0, C: 0, D: 0 });
  const [distortionLog, setDistortionLog] = useState<any[]>([]);
  const [truthMeta, setTruthMeta] = useState<any>(null);
  const [truthDiscussionMeta, setTruthDiscussionMeta] = useState<{
    categoryLabel?: string;
    timelineLabels?: string[];
  } | null>(null);
  const [truthReadyProgress, setTruthReadyProgress] = useState<{ acked: number; total: number } | null>(null);
  const [discussionReadyProgress, setDiscussionReadyProgress] = useState<{ acked: number; total: number } | null>(null);
  const [discussionEndsAtMs, setDiscussionEndsAtMs] = useState<number | null>(null);
  const discussionLeft = usePhaseTimer(phase === 'discussion' ? discussionEndsAtMs : null, 15);
  const isTruth = mode === 'truth_collapse';

  useEffect(() => {
    if (mode !== 'truth_collapse' || phase !== 'discussion') return;
    if (!discussionEndsAtMs) {
      setDiscussionEndsAtMs(Date.now() + (localTimeLeft || 15) * 1000);
    }
  }, [mode, phase, discussionEndsAtMs, localTimeLeft]);
  const reset = useDisplayStore((s) => s.reset);
  const [forceEndStep, setForceEndStep] = useState<'idle' | 'confirm'>('idle');
  const [forceEndCode, setForceEndCode] = useState('');
  const [forceEndError, setForceEndError] = useState<string | null>(null);

  useEffect(() => {
    if (!roomCode) {
      navigate('/');
    }
  }, [roomCode, navigate]);

  // Timer countdown - reset when new question arrives
  useEffect(() => {
    if (!currentQuestion) return;

    // Reset timer to the question's time limit when question changes
    setLocalTimeLeft(currentQuestion.time_limit);
  }, [currentQuestion]);

  // Timer countdown - actually count down
  useEffect(() => {
    if (roundScores) return; // Don't count down if showing results
    if (mode === 'truth_collapse') {
      if (phase !== 'answering' || !currentQuestion) return;
    } else {
      if (!currentQuestion) return;
    }

    const timer = setInterval(() => {
      setLocalTimeLeft((prev) => {
        if (prev <= 1) {
          clearInterval(timer);
          return 0;
        }
        return prev - 1;
      });
    }, 1000);

    return () => clearInterval(timer);
  }, [currentQuestion, roundScores, phase, mode]);

  // Truth Collapse: discussion countdown
  useEffect(() => {
    if (mode !== 'truth_collapse') return;
    if (phase !== 'discussion') return;

    const timer = setInterval(() => {
      setLocalTimeLeft((prev) => {
        if (prev <= 1) {
          clearInterval(timer);
          return 0;
        }
        return prev - 1;
      });
    }, 1000);

    return () => clearInterval(timer);
  }, [mode, phase]);

  // Update ref on each render so callbacks have access to latest state
  const callbacksRef = useRef<any>({});
  callbacksRef.current = {
    onGameState: (state: any) => {
      if (state.players) setPlayers(state.players);
      if (state.mode) setMode(state.mode);
      setGameState(state.state);
      if (state.current_round && state.total_rounds) {
        setRound(state.current_round, state.total_rounds);
      }

      const tr = state.truth_resume;
      if (state.mode === 'truth_collapse' && tr && state.state === 'round_start') {
        if (tr.phase === 'transition') {
          setPhase('transition');
          setQuestion(null);
          setRoundScores(null);
          setTruthReadyProgress(null);
          return;
        }
        if (tr.phase === 'discussion') {
          setPhase('discussion');
          setQuestion(null);
          setRoundScores(null);
          setTruthMeta(null);
          const secs = tr.discussion_seconds ?? 15;
          setLocalTimeLeft(secs);
          setDiscussionEndsAtMs(
            tr.phase_ends_at_ms ?? Date.now() + secs * 1000
          );
          setTruthDiscussionMeta({
            categoryLabel: tr.category_label,
            timelineLabels: tr.category_timeline_labels ?? [],
          });
          setTruthReadyProgress(null);
          return;
        }
        if (tr.phase === 'answering' && tr.display_question) {
          setPhase('answering');
          setQuestion(tr.display_question);
          const tl = tr.display_question.time_limit ?? 120;
          setTimeLeft(tl);
          setLocalTimeLeft(tr.time_left != null ? tr.time_left : tl);
          setRoundScores(null);
          setTruthReadyProgress(null);
          setCommittedPlayers(new Set());
          return;
        }
        if (tr.phase === 'results' && tr.display_round_scored) {
          const d = tr.display_round_scored;
          setPhase('results');
          setTruthMeta(d);
          setRoundScores(d.scores ?? []);
          setLeaderboard(d.leaderboard ?? []);
          const connected = (state.players || []).filter((p: { connected?: boolean }) => p.connected).length;
          setTruthReadyProgress({
            acked: 0,
            total: connected || (state.players || []).length || 0,
          });
          if (d.counts && typeof d.counts === 'object') {
            setOptionCounts((prev) => ({ ...prev, ...d.counts }));
          }
          setTimeLeft(0);
          setLocalTimeLeft(0);
          return;
        }
      }

      if (state.current_question) {
        setQuestion(state.current_question);
        setTimeLeft(state.current_question.time_limit);
        setPhase('answering');
      } else if (state.mode === 'truth_collapse' && state.state === 'round_start') {
        // Truth Collapse round starts with discussion, question comes later.
        setQuestion(null);
        setRoundScores(null);
        setPhase('discussion');
      }
    },
    onPlayerJoined: (data: any) => {
      if (data.players) setPlayers(data.players);
    },
    onPlayerDisconnected: (data: any) => {
      if (data.players) setPlayers(data.players);
    },
    onGameStarted: (data: any) => {
      if (data.mode) setMode(data.mode);
      setRound(data.round, data.total_rounds);
      setGameState('round_start');
      setRoundScores(null);
      setCommittedPlayers(new Set());
      setTruthReadyProgress(null);
      if (data.mode === 'truth_collapse') {
        setPhase('discussion');
        setQuestion(null);
        setLocalTimeLeft(15);
        setDiscussionEndsAtMs(Date.now() + 15 * 1000);
      }
    },
    onDiscussionStarted: (data: any) => {
      // Use event payload as source of truth (avoid stale `mode` closures)
      if (data?.mode && data.mode !== 'truth_collapse') return;
      setMode('truth_collapse');
      setPhase('discussion');
      // Never show question text during discussion (server sends question: null)
      setQuestion(null);
      setRoundScores(null);
      setTruthMeta(null);
      setDistortionLog([]);
      setCommittedPlayers(new Set());
      setOptionCounts({ A: 0, B: 0, C: 0, D: 0 });
      const secs = data.discussion_seconds || 15;
      setLocalTimeLeft(secs);
      setDiscussionEndsAtMs(
        (data as { phase_ends_at_ms?: number }).phase_ends_at_ms ?? Date.now() + secs * 1000
      );
      setDiscussionReadyProgress(null);
      setTruthDiscussionMeta({
        categoryLabel: data.category_label,
        timelineLabels: data.category_timeline_labels ?? [],
      });
    },
    onQuestionRevealed: (question: any) => {
      setQuestion(question);
      setTimeLeft(question.time_limit);
      setLocalTimeLeft(question.time_limit);
      setCommittedPlayers(new Set());
      setRoundScores(null);
      setPhase('answering');
    },
    onPlayerCommitted: (data: any) => {
      console.log('✅ Display received player_committed:', data);
      setCommittedPlayers((prev) => {
        const updated = new Set([...prev, data.player_id]);
        console.log('Updated committed players:', Array.from(updated));
        return updated;
      });
    },
    onOptionCountsUpdated: (data: any) => {
      if (mode !== 'truth_collapse') return;
      if (!data?.counts) return;
      setOptionCounts((prev) => ({
        ...prev,
        ...data.counts,
      }));
    },
    onDistortionUsed: (data: any) => {
      if (mode !== 'truth_collapse') return;
      setDistortionLog((prev) => [data, ...prev].slice(0, 10));
    },
    onRoundScored: (data: any) => {
      if (mode === 'truth_collapse') {
        setTruthMeta(data);
        setRoundScores(data.scores || []);
        setLeaderboard(data.leaderboard || []);
        setPhase('results');
        setTruthReadyProgress(null);
      } else {
        setRoundScores(data.scores);
        setLeaderboard(data.leaderboard);
        setPhase('results');
      }
      setTimeLeft(0);
      setLocalTimeLeft(0);
    },
    onRoundStarted: (data: any) => {
      setRound(data.round, data.total_rounds);
      setRoundScores(null);
      setCommittedPlayers(new Set());
      setTruthReadyProgress(null);
      if (data.mode === 'truth_collapse' || mode === 'truth_collapse') {
        setPhase('discussion');
        setQuestion(null);
        if (data.category_label) {
          setTruthDiscussionMeta({
            categoryLabel: data.category_label,
            timelineLabels: data.category_timeline_labels ?? [],
          });
        }
        const secs = data.discussion_seconds ?? 15;
        setLocalTimeLeft(secs);
        setDiscussionEndsAtMs(
          (data as { phase_ends_at_ms?: number }).phase_ends_at_ms ?? Date.now() + secs * 1000
        );
      }
    },
    onTruthResultsProgress: (data: any) => {
      setTruthReadyProgress({ acked: data.acked_count ?? 0, total: data.total ?? 0 });
    },
    onTruthDiscussionProgress: (data: any) => {
      setDiscussionReadyProgress({ acked: data.acked_count ?? 0, total: data.total ?? 0 });
    },
    onGameEnded: (data: any) => {
      setLeaderboard(data.final_scores);
      if (data.winner) setWinner(data.winner);
      setGameState('game_end');
      setTimeout(() => navigate('/results'), 2000);
    },
    onRoomClosed: () => {
      reset();
      navigate('/');
    },
  };

  const { requestForceEnd, confirmForceEnd, leaveDisplay, closeRoom } = useDisplaySocket({
    roomCode: roomCode || '',
    onGameState: callbacksRef.current.onGameState,
    onPlayerJoined: callbacksRef.current.onPlayerJoined,
    onPlayerDisconnected: callbacksRef.current.onPlayerDisconnected,
    onGameStarted: callbacksRef.current.onGameStarted,
    onDiscussionStarted: callbacksRef.current.onDiscussionStarted,
    onOptionCountsUpdated: callbacksRef.current.onOptionCountsUpdated,
    onDistortionUsed: callbacksRef.current.onDistortionUsed,
    onQuestionRevealed: callbacksRef.current.onQuestionRevealed,
    onPlayerCommitted: callbacksRef.current.onPlayerCommitted,
    onRoundScored: callbacksRef.current.onRoundScored,
    onRoundStarted: callbacksRef.current.onRoundStarted,
    onGameEnded: callbacksRef.current.onGameEnded,
    onTruthResultsProgress: callbacksRef.current.onTruthResultsProgress,
    onTruthDiscussionProgress: callbacksRef.current.onTruthDiscussionProgress,
    onRoomClosed: callbacksRef.current.onRoomClosed,
  });

  if (!roomCode) return null;

  const handleReturnHome = async () => {
    const code = useDisplayStore.getState().roomCode;
    if (code) {
      try {
        await api.closeRoom(code);
      } catch {
        // continue with socket close
      }
    }
    try {
      await closeRoom();
    } catch {
      leaveDisplay();
    }
    reset();
    navigate('/');
  };

  const handleRequestForceEnd = async () => {
    setForceEndError(null);
    try {
      await requestForceEnd();
      setForceEndStep('confirm');
      setForceEndCode('');
    } catch (e) {
      setForceEndError(e instanceof Error ? e.message : 'Could not start end-game flow');
    }
  };

  const handleConfirmForceEnd = async () => {
    setForceEndError(null);
    try {
      await confirmForceEnd(forceEndCode.trim().toUpperCase());
      setForceEndStep('idle');
    } catch (e) {
      setForceEndError(e instanceof Error ? e.message : 'Confirmation failed');
    }
  };

  const getPlayerName = (playerId: string) => {
    return players.find(p => p.id === playerId)?.nickname || 'Unknown';
  };

  const getOptionText = (optionId: string) => {
    if (!currentQuestion) return optionId;
    if (Array.isArray(currentQuestion.options)) {
      const option = currentQuestion.options.find((opt: any) => 
        typeof opt === 'object' ? opt.id === optionId : opt === optionId
      );
      return typeof option === 'object' ? option.text : option;
    }
    return optionId;
  };

  return (
    <HostPageShell>
    <div className="min-h-screen text-[#2D1B3D] p-4 lg:p-8">
      <div className="max-w-7xl mx-auto">
        <div className="mb-5 rounded-2xl border-2 border-purple-300 bg-white/90 backdrop-blur px-5 py-4 shadow-lg">
          <HostTitle>Live Game</HostTitle>
          <p className="text-sm text-[#7D5A8A] text-center font-medium">Room {roomCode} · Round {currentRound}/{totalRounds}</p>
          <div className="flex flex-wrap justify-center gap-3 mt-4">
            <button
              type="button"
              onClick={handleReturnHome}
              className="px-4 py-2 rounded-xl border-2 border-gray-300 font-bold text-gray-700 hover:bg-gray-50"
            >
              Return to main screen
            </button>
            {forceEndStep === 'idle' ? (
              <button
                type="button"
                onClick={handleRequestForceEnd}
                className="px-4 py-2 rounded-xl border-2 border-red-300 font-bold text-red-700 hover:bg-red-50"
              >
                End game early…
              </button>
            ) : (
              <div className="flex flex-wrap items-center gap-2">
                <input
                  type="text"
                  value={forceEndCode}
                  onChange={(e) => setForceEndCode(e.target.value.toUpperCase())}
                  placeholder={roomCode}
                  className="px-3 py-2 border-2 border-red-200 rounded-lg font-mono uppercase w-28"
                />
                <button
                  type="button"
                  onClick={handleConfirmForceEnd}
                  className="px-3 py-2 rounded-lg bg-red-600 text-white font-bold"
                >
                  Confirm
                </button>
                <button type="button" onClick={() => setForceEndStep('idle')} className="text-gray-600 font-semibold">
                  Cancel
                </button>
              </div>
            )}
          </div>
          {forceEndError && <p className="text-center text-red-600 text-sm font-semibold mt-2">{forceEndError}</p>}
        </div>
        <div className="flex justify-between items-center mb-6 gap-4">
          <div className="bg-white px-8 py-4 rounded-full text-purple-700 font-black text-2xl shadow-lg border-2 border-purple-300">
            Round {currentRound}/{totalRounds}
          </div>
          <div className="bg-white px-8 py-4 rounded-full text-pink-600 font-black text-xl shadow-lg border-2 border-pink-300">
            {roomCode}
          </div>
        </div>

        {/* Main Content */}
        {isTruth ? (
          phase === 'transition' ? (
            <div className="bg-white rounded-3xl shadow-2xl p-16 text-center border-4 border-purple-300">
              <h2 className="text-5xl font-black mb-4 text-purple-700">Next round</h2>
              <p className="text-2xl text-gray-600">Syncing with the room…</p>
            </div>
          ) : phase === 'discussion' ? (
            <div className="bg-white rounded-3xl shadow-2xl p-16 text-center border-4 border-pink-300">
              <h2 className="text-5xl font-black mb-4 text-pink-700">Discussion (before answering)</h2>
              <div className="flex justify-center mb-6">
                <div className="w-28 h-28 rounded-full bg-gradient-to-br from-green-400 to-emerald-500 flex items-center justify-center text-5xl font-black text-white border-4 border-green-300 shadow-lg">
                  {discussionLeft}
                </div>
              </div>
              <p className="text-2xl text-gray-600 mb-4">
                Discussion ends in <span className="text-pink-700 font-black">{discussionLeft}s</span>
              </p>
              {discussionReadyProgress && discussionReadyProgress.total > 0 ? (
                <p className="text-xl font-bold text-purple-800 mb-4">
                  Ready to answer: {discussionReadyProgress.acked}/{discussionReadyProgress.total}
                </p>
              ) : null}
              <p className="text-lg text-gray-500 mb-10 max-w-2xl mx-auto">
                The full question is hidden until the answer phase—use this time to talk, bluff, and lock in a prediction on your phone.
              </p>

              {truthDiscussionMeta?.categoryLabel ? (
                <div className="mb-10 max-w-3xl mx-auto text-left bg-gradient-to-r from-purple-50 to-pink-50 rounded-2xl p-6 border-2 border-purple-200">
                  <p className="text-sm font-black text-purple-600 uppercase tracking-widest mb-1">Round theme</p>
                  <p className="text-4xl font-black text-pink-700">{truthDiscussionMeta.categoryLabel}</p>
                  {truthDiscussionMeta.timelineLabels && truthDiscussionMeta.timelineLabels.length > 1 ? (
                    <p className="text-lg text-gray-700 mt-3">
                      <span className="font-bold text-purple-700">After distortions: </span>
                      {truthDiscussionMeta.timelineLabels.join(' → ')}
                    </p>
                  ) : null}
                  <p className="text-sm text-gray-600 mt-2">
                    Category stays the same each round until someone uses Swap Category.
                  </p>
                </div>
              ) : (
                <div className="mb-10 max-w-xl mx-auto rounded-2xl p-6 border-2 border-dashed border-purple-200 text-gray-500">
                  Loading theme…
                </div>
              )}

              <div className="bg-gradient-to-r from-purple-50 to-pink-50 rounded-2xl p-6 border-4 border-purple-300 inline-block">
                <p className="text-2xl font-black text-purple-700 mb-4">Live counts (if any)</p>
                <div className="grid grid-cols-4 gap-4">
                  {['A', 'B', 'C', 'D'].map((opt) => (
                    <div key={opt} className="bg-white rounded-xl p-4 border-2 border-purple-200">
                      <div className="text-3xl font-black text-purple-700">{opt}</div>
                      <div className="text-2xl font-bold text-pink-700">{optionCounts[opt] ?? 0}</div>
                    </div>
                  ))}
                </div>
              </div>

              {distortionLog.length > 0 && (
                <div className="mt-8 text-left">
                  <p className="text-2xl font-black text-purple-700 mb-3">Distortion log</p>
                  <div className="space-y-2">
                    {distortionLog.slice(0, 5).map((d: any, idx: number) => (
                      <div key={idx} className="bg-gradient-to-r from-purple-50 to-pink-50 rounded-xl p-4 border-2 border-purple-200">
                        <p className="font-bold text-gray-800">{d.nickname} used: {d.action}</p>
                        <p className="text-sm text-gray-600">
                          Remaining: {d.remaining_charges ?? '??'} charges
                        </p>
                      </div>
                    ))}
                  </div>
                </div>
              )}
            </div>
          ) : phase === 'results' && roundScores ? (
            <div className="bg-white rounded-3xl shadow-2xl p-12 border-4 border-purple-300">
              <h2 className="text-5xl font-black text-center mb-6 text-purple-600">
                Round {currentRound} Results
              </h2>

              {truthReadyProgress && truthReadyProgress.total > 0 ? (
                <p className="text-center text-xl font-bold text-purple-800 mb-6">
                  Players ready for next round: {truthReadyProgress.acked}/{truthReadyProgress.total}
                </p>
              ) : null}

              <div className="mb-8 grid grid-cols-1 lg:grid-cols-2 gap-6">
                <div className="bg-gradient-to-r from-purple-50 to-pink-50 rounded-2xl p-6 border-4 border-purple-300">
                  <p className="text-2xl font-black text-purple-700 mb-2">True reality</p>
                  <p className="text-4xl font-black text-pink-700">
                    {truthMeta?.true_reality ?? '??'}
                  </p>
                  <p className="text-lg text-gray-600 mt-2">
                    {truthMeta?.stable_round ? 'Stable round (no distortions generated)' : 'Distortions generated'}
                    {truthMeta?.merged_realities ? ' | Realities merged early' : ''}
                  </p>
                  <div className="mt-4">
                    <p className="text-2xl font-black text-purple-700 mb-3">Answer counts</p>
                    <div className="grid grid-cols-4 gap-3">
                      {['A', 'B', 'C', 'D'].map((opt) => (
                        <div key={opt} className="bg-white rounded-xl p-3 border-2 border-purple-200 text-center">
                          <div className="text-lg font-black text-purple-700">{opt}</div>
                          <div className="text-2xl font-bold text-pink-700">{optionCounts[opt] ?? truthMeta?.counts?.[opt] ?? 0}</div>
                        </div>
                      ))}
                    </div>
                  </div>
                </div>

                <div className="bg-white rounded-2xl p-6 border-4 border-pink-200">
                  <p className="text-2xl font-black text-purple-700 mb-3">Distortions used</p>
                  {distortionLog.length === 0 ? (
                    <p className="text-gray-600 text-lg">No distortions used this round.</p>
                  ) : (
                    <div className="space-y-2">
                      {distortionLog.slice(0, 6).map((d: any, idx: number) => (
                        <div key={idx} className="bg-gradient-to-r from-purple-50 to-pink-50 rounded-xl p-4 border-2 border-purple-200">
                          <p className="font-bold text-gray-800">{d.nickname} used {d.action}</p>
                        </div>
                      ))}
                    </div>
                  )}
                </div>
              </div>

              <div className="space-y-4 mb-8">
                {roundScores.map((row: any) => {
                  const inTrue = !!row.in_true_reality;
                  return (
                    <div
                      key={row.player_id}
                      className={`p-6 rounded-xl border-4 ${
                        inTrue ? 'bg-green-50 border-green-400' : 'bg-red-50 border-red-400'
                      }`}
                    >
                      <div className="flex items-center justify-between">
                        <div className="flex items-center gap-4">
                          <div className={`w-12 h-12 rounded-full flex items-center justify-center text-white font-bold text-xl ${
                            inTrue ? 'bg-green-500' : 'bg-red-500'
                          }`}>
                            {inTrue ? '+' : '*'}
                          </div>
                          <div>
                            <p className="text-2xl font-bold">{getPlayerName(row.player_id)}</p>
                            <p className="text-lg text-gray-600">
                              Picked: <span className="font-bold">{row.answer}</span>
                            </p>
                          </div>
                        </div>
                        <div className="text-right">
                          {inTrue ? (
                            <p className="text-2xl font-bold text-purple-600">+{row.tp_gain} TP</p>
                          ) : (
                            <p className="text-2xl font-bold text-purple-600">+{row.distortion_gain ?? 1} DI (charge: {row.charges ?? '??'})</p>
                          )}
                        </div>
                      </div>
                    </div>
                  );
                })}
              </div>

              {/* Leaderboard */}
              <div className="bg-gradient-to-r from-purple-50 to-pink-50 rounded-xl p-6 border-4 border-purple-300">
                <h3 className="text-3xl font-bold mb-4 text-center">Leaderboard (Final Collapse)</h3>
                <div className="space-y-2">
                  {leaderboard.map((entry: any, index) => (
                    <div key={entry.player_id} className="flex items-center justify-between p-4 bg-white rounded-lg">
                      <div className="flex items-center gap-4">
                        <div className="w-10 h-10 rounded-full bg-gradient-to-r from-pink-500 to-purple-500 flex items-center justify-center text-white font-bold">
                          {index + 1}
                        </div>
                        <p className="text-xl font-semibold">{entry.nickname}</p>
                      </div>
                      <div className="text-right">
                        <p className="text-2xl font-bold text-purple-600">
                          {entry.final_score ?? entry.score} pts
                        </p>
                        <p className="text-sm text-gray-600">
                          TP {entry.tp ?? 0} | DI {entry.di ?? 0} | PS {entry.ps ?? 0}
                        </p>
                      </div>
                    </div>
                  ))}
                </div>
              </div>
            </div>
          ) : !currentQuestion ? (
            <div className="bg-white rounded-3xl shadow-2xl p-16 text-center border-4 border-pink-300">
              <p className="text-3xl font-black text-purple-700">Loading question…</p>
            </div>
          ) : (
            // Truth Collapse question view
            <div className="bg-white rounded-3xl shadow-2xl p-12 border-4 border-pink-300">
              <div className="flex justify-between items-start mb-6">
              <div className="bg-white px-6 py-3 rounded-full border-4 border-purple-200">
                  <p className="text-2xl font-black text-purple-700">Round {currentRound}/{totalRounds}</p>
                  <p className="text-sm text-gray-600 mt-1">Realities will split after answers lock</p>
                </div>
                {((currentQuestion as any)?.shuffle_targets?.length > 0 ||
                  (currentQuestion as any)?.blind_targets?.length > 0) && (
                  <div className="bg-red-50 border-4 border-red-200 px-6 py-3 rounded-full">
                    <p className="text-xl font-black text-red-700">Answer shuffle active</p>
                    <p className="text-sm text-red-800 mt-1">Some phones will scramble option order</p>
                  </div>
                )}
              </div>

              <div className="flex justify-center mb-8">
                <div className={`w-32 h-32 rounded-full flex items-center justify-center text-6xl font-black transition-all shadow-lg border-4 ${
                  localTimeLeft > 10
                    ? 'bg-gradient-to-br from-green-400 to-emerald-500 text-white border-green-300'
                    : localTimeLeft > 5
                    ? 'bg-gradient-to-br from-yellow-400 to-orange-500 text-white border-yellow-300'
                    : 'bg-gradient-to-br from-red-400 to-pink-500 text-white border-red-300 animate-pulse'
                }`}>
                  {localTimeLeft}
                </div>
              </div>

              <div className="text-center mb-10">
                {(currentQuestion as any)?.category_label && (
                  <p className="text-sm font-black text-purple-600 uppercase tracking-widest mb-2">
                    {(currentQuestion as any).category_label}
                  </p>
                )}
                <h2 className="text-5xl lg:text-6xl font-black mb-6 text-purple-600" style={{ fontFamily: "'Bangers', cursive" }}>
                  {currentQuestion.text}
                </h2>
              </div>

              <div className="grid grid-cols-1 lg:grid-cols-2 gap-6 mb-8">
                <div className="grid grid-cols-2 gap-4">
                  {currentQuestion.options.map((option: any, index: number) => {
                    const optionId = typeof option === 'object' ? option.id : ['A', 'B', 'C', 'D'][index];
                    const optionText = typeof option === 'object' ? option.text : option;
                    return (
                      <div key={optionId} className="p-6 rounded-2xl border-4 border-purple-200 bg-gradient-to-r from-purple-50 to-pink-50 text-center">
                        <div className="text-4xl font-black text-purple-700 mb-2">{optionId}</div>
                        <div className="text-lg font-semibold text-gray-700 mb-3">{optionText}</div>
                        <div className="text-2xl font-black text-pink-700">{optionId}: {optionCounts[optionId] ?? 0}</div>
                      </div>
                    );
                  })}
                </div>

                <div className="bg-gradient-to-r from-purple-50 to-pink-50 rounded-2xl p-6 border-4 border-purple-300">
                  <p className="text-2xl font-black text-purple-700 mb-4">Distortions this round</p>
                  {distortionLog.length === 0 ? (
                    <p className="text-gray-600 text-lg">No distortions used yet.</p>
                  ) : (
                    <div className="space-y-2">
                      {distortionLog.slice(0, 6).map((d: any, idx: number) => (
                        <div key={idx} className="bg-white rounded-xl p-4 border-2 border-purple-200">
                          <p className="font-bold text-gray-800">{d.nickname}</p>
                          <p className="text-gray-600">used {d.action}</p>
                          <p className="text-sm text-gray-600">{d.remaining_charges ?? '??'} charges left</p>
                        </div>
                      ))}
                    </div>
                  )}
                </div>
              </div>

              {/* Player Status */}
              <div className="bg-gradient-to-r from-purple-50 to-pink-50 rounded-xl p-6 border-4 border-purple-300">
                <h3 className="text-2xl font-bold mb-4 text-center">
                  Players ({committedPlayers.size}/{players.length})
                </h3>
                <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
                  {players.map((player) => (
                    <div
                      key={player.id}
                      className={`p-4 rounded-lg text-center ${
                        committedPlayers.has(player.id)
                          ? 'bg-green-100 border-2 border-green-500'
                          : 'bg-gray-100 border-2 border-gray-300'
                      }`}
                    >
                      <p className="font-semibold">{player.nickname}</p>
                      <p className="text-sm">
                      {committedPlayers.has(player.id) ? '✓ Answered' : 'Waiting...'}
                      </p>
                    </div>
                  ))}
                </div>
              </div>
            </div>
          )
        ) : (
          // Classic Trivia (existing UI)
          <>
            {!currentQuestion ? (
              <div className="bg-white rounded-3xl shadow-2xl p-16 text-center">
                <h2 className="text-5xl font-black mb-4 text-purple-600">Preparing next question...</h2>
                <p className="text-2xl text-gray-600">Please wait...</p>
              </div>
            ) : roundScores ? (
              /* Round Results */
              <div className="bg-white rounded-3xl shadow-2xl p-12">
                <h2 className="text-5xl font-black text-center mb-8 text-purple-600">Round {currentRound} Results</h2>
                
                <div className="mb-8">
                  <p className="text-3xl font-bold text-center mb-4">
                    Correct answer: <span className="text-green-600">{currentQuestion.correct as any}</span>
                  </p>
                  <p className="text-xl text-center text-gray-600 mb-8">
                    {getOptionText(currentQuestion.correct as any)}
                  </p>
                </div>

                <div className="space-y-4 mb-8">
                  {roundScores.map((score: any) => (
                    <div
                      key={score.player_id}
                      className={`p-6 rounded-xl border-4 ${
                        score.is_correct
                          ? 'bg-green-50 border-green-400'
                          : 'bg-red-50 border-red-400'
                      }`}
                    >
                      <div className="flex items-center justify-between">
                        <div className="flex items-center gap-4">
                          <div className={`w-12 h-12 rounded-full flex items-center justify-center text-white font-bold text-xl ${
                            score.is_correct ? 'bg-green-500' : 'bg-red-500'
                          }`}>
                            {score.is_correct ? '✓' : '✗'}
                          </div>
                          <div>
                            <p className="text-2xl font-bold">{getPlayerName(score.player_id)}</p>
                            <p className="text-lg text-gray-600">
                              Picked: {score.answer} - {getOptionText(score.answer)}
                            </p>
                          </div>
                        </div>
                        <div className="text-right">
                          <p className="text-2xl font-bold text-purple-600">+{score.points} pts</p>
                        </div>
                      </div>
                    </div>
                  ))}
                </div>

                {/* Leaderboard */}
                <div className="bg-gradient-to-r from-purple-50 to-pink-50 rounded-xl p-6 border-4 border-purple-300">
                  <h3 className="text-3xl font-bold mb-4 text-center">Leaderboard</h3>
                  <div className="space-y-2">
                    {leaderboard.map((entry: any, index) => (
                      <div key={entry.player_id} className="flex items-center justify-between p-4 bg-white rounded-lg">
                        <div className="flex items-center gap-4">
                          <div className="w-10 h-10 rounded-full bg-gradient-to-r from-pink-500 to-purple-500 flex items-center justify-center text-white font-bold">
                            {index + 1}
                          </div>
                          <p className="text-xl font-semibold">{entry.nickname}</p>
                        </div>
                        <p className="text-2xl font-bold text-purple-600">{entry.score} pts</p>
                      </div>
                    ))}
                  </div>
                </div>
              </div>
            ) : (
              /* Question Display */
              <div className="bg-white rounded-3xl shadow-2xl p-12 border-4 border-purple-300">
                {/* Timer */}
                <div className="flex justify-center mb-8">
                  <div className={`w-32 h-32 rounded-full flex items-center justify-center text-6xl font-black transition-all shadow-lg border-4 ${
                    localTimeLeft > 10
                      ? 'bg-gradient-to-br from-green-400 to-emerald-500 text-white border-green-300'
                      : localTimeLeft > 5
                      ? 'bg-gradient-to-br from-yellow-400 to-orange-500 text-white border-yellow-300'
                      : 'bg-gradient-to-br from-red-400 to-pink-500 text-white border-red-300 animate-pulse'
                  }`}>
                    {localTimeLeft}
                  </div>
                </div>

                {/* Question Text */}
                <div className="text-center mb-12">
                  <h2 className="text-5xl lg:text-6xl font-black mb-6 text-purple-600" style={{ fontFamily: "'Bangers', cursive" }}>
                    {currentQuestion.text}
                  </h2>
                </div>

                {/* Answer Options */}
                <div className="grid grid-cols-2 gap-6 mb-8">
                  {currentQuestion.options.map((option: any, index: number) => {
                    const optionId = typeof option === 'object' ? option.id : ['A', 'B', 'C', 'D'][index];
                    const optionText = typeof option === 'object' ? option.text : option;
                    const isCorrect = optionId === currentQuestion.correct;
                    
                    return (
                      <div
                        key={optionId}
                        className={`p-8 rounded-2xl border-4 text-center transition-all ${
                          isCorrect && roundScores
                            ? 'bg-green-100 border-green-500 scale-105'
                            : 'bg-gradient-to-br from-purple-50 to-pink-50 border-purple-300 hover:scale-105'
                        }`}
                      >
                        <div className="text-4xl font-black text-purple-600 mb-2">{optionId}</div>
                        <div className="text-2xl font-semibold">{optionText}</div>
                      </div>
                    );
                  })}
                </div>

                {/* Player Status */}
                <div className="bg-gradient-to-r from-purple-50 to-pink-50 rounded-xl p-6 border-4 border-purple-300">
                  <h3 className="text-2xl font-bold mb-4 text-center">
                    Players ({committedPlayers.size}/{players.length})
                  </h3>
                  <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
                    {players.map((player) => (
                      <div
                        key={player.id}
                        className={`p-4 rounded-lg text-center ${
                          committedPlayers.has(player.id)
                            ? 'bg-green-100 border-2 border-green-500'
                            : 'bg-gray-100 border-2 border-gray-300'
                        }`}
                      >
                        <p className="font-semibold">{player.nickname}</p>
                        <p className="text-sm">
                      {committedPlayers.has(player.id) ? '✓ Answered' : 'Waiting...'}
                        </p>
                      </div>
                    ))}
                  </div>
                </div>
              </div>
            )}
          </>
        )}
      </div>
    </div>
    </HostPageShell>
  );
}

