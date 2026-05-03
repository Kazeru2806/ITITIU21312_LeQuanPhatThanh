import { useEffect, useRef, useState } from 'react';
import { Socket, Channel } from 'phoenix';
import type { Room, Question, LeaderboardEntry, Player } from '../types/game';

// Match the backend host automatically (desktop + mobile)
const hostname = window.location.hostname || 'localhost';
const WS_URL = `ws://${hostname}:4000/socket`;

// Normalize room code to uppercase for consistent channel subscription
function normalizeRoomCode(code: string): string {
  return (code || '').toUpperCase().trim();
}

interface UseDisplaySocketProps {
  roomCode: string;
  onGameState?: (state: Room & { current_question?: Question }) => void;
  onPlayerJoined?: (data: { player_id: string; nickname: string; players: Player[] }) => void;
  onGameStarted?: (data: { round: number; total_rounds: number }) => void;
  onDiscussionStarted?: (data: {
    round: number;
    discussion_seconds: number;
    mode?: string;
    question?: Question;
    category?: string;
    category_label?: string;
    category_timeline?: string[];
    category_timeline_labels?: string[];
  }) => void;
  onOptionCountsUpdated?: (data: { round: number; counts: Record<string, number> }) => void;
  onDistortionUsed?: (data: any) => void;
  onQuestionRevealed?: (question: Question) => void;
  onPlayerCommitted?: (data: { player_id: string; nickname: string; timestamp: string }) => void;
  onRoundScored?: (data: any) => void;
  onRoundStarted?: (data: { round: number; total_rounds: number }) => void;
  onGameEnded?: (data: { final_scores: LeaderboardEntry[]; winner?: LeaderboardEntry }) => void;
  onRematchApproved?: (data?: any) => void;
  onRematchCancelled?: (data?: any) => void;
  onTruthResultsProgress?: (data: {
    round: number;
    acked_count: number;
    total: number;
    acked_player_ids: string[];
  }) => void;
}

export function useDisplaySocket({
  roomCode,
  onGameState,
  onPlayerJoined,
  onGameStarted,
  onDiscussionStarted,
  onOptionCountsUpdated,
  onDistortionUsed,
  onQuestionRevealed,
  onPlayerCommitted,
  onRoundScored,
  onRoundStarted,
  onGameEnded,
  onRematchApproved,
  onRematchCancelled,
  onTruthResultsProgress,
}: UseDisplaySocketProps) {
  const [connected, setConnected] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const socketRef = useRef<Socket | null>(null);
  const channelRef = useRef<Channel | null>(null);
  const cbRef = useRef<UseDisplaySocketProps>({ roomCode });
  cbRef.current = {
    roomCode,
    onGameState,
    onPlayerJoined,
    onGameStarted,
    onDiscussionStarted,
    onOptionCountsUpdated,
    onDistortionUsed,
    onQuestionRevealed,
    onPlayerCommitted,
    onRoundScored,
    onRoundStarted,
    onGameEnded,
    onRematchApproved,
    onRematchCancelled,
    onTruthResultsProgress,
  };

  useEffect(() => {
    const normalizedCode = normalizeRoomCode(roomCode);
    if (!normalizedCode) return;

    // Create socket connection
    const socket = new Socket(WS_URL, {
      params: {},
      logger: (kind, msg, data) => {
        console.log(`[${kind}] ${msg}`, data);
      },
    });

    socket.connect();
    socketRef.current = socket;

    // Join display channel (use normalized uppercase code for consistency)
    const channel = socket.channel(`display:${normalizedCode}`, {});

    channelRef.current = channel;

    // Handle join response
    channel
      .join()
      .receive('ok', (response: Room & { current_question?: Question }) => {
        console.log('✅ Joined display channel', response);
        setConnected(true);
        setError(null);
        const c = cbRef.current;
        if (c.onGameState) {
          c.onGameState(response);
        }
        if (response.current_question && c.onQuestionRevealed && !(response as { truth_resume?: unknown }).truth_resume) {
          c.onQuestionRevealed(response.current_question);
        }
      })
      .receive('error', (response: { reason?: string }) => {
        console.error('❌ Failed to join display channel', response);
        setError(response.reason || 'Failed to join display');
        setConnected(false);
      });

    // Listen to display events
    channel.on('display:player_joined', (data: { player_id: string; nickname: string; players: Player[] }) => {
      console.log('👤 Player joined:', data);
      cbRef.current.onPlayerJoined?.(data);
    });

    channel.on('display:game_started', (data: { round: number; total_rounds: number }) => {
      console.log('🎮 Game started:', data);
      cbRef.current.onGameStarted?.(data);
    });

    channel.on('display:discussion_started', (data) => {
      console.log('🗣 Discussion started:', data);
      cbRef.current.onDiscussionStarted?.(data);
    });

    channel.on('display:question_revealed', (data: Question) => {
      console.log('❓ Question revealed:', data);
      cbRef.current.onQuestionRevealed?.(data);
    });

    channel.on('display:option_counts_updated', (data) => {
      console.log('📊 Option counts updated:', data);
      cbRef.current.onOptionCountsUpdated?.(data);
    });

    channel.on('display:player_committed', (data: { player_id: string; nickname: string; timestamp: string }) => {
      console.log('✅ Player committed:', data);
      cbRef.current.onPlayerCommitted?.(data);
    });

    channel.on('display:round_scored', (data: {
      round: number;
      scores: Array<{ player_id: string; is_correct: boolean; points: number; answer: string }>;
      leaderboard: LeaderboardEntry[];
      correct_answer: string;
      question: Question;
    }) => {
      console.log('🎯 Round scored:', data);
      cbRef.current.onRoundScored?.(data);
    });

    channel.on('display:distortion_used', (data) => {
      console.log('🧩 Distortion used:', data);
      cbRef.current.onDistortionUsed?.(data);
    });

    channel.on('display:round_started', (data: { round: number; total_rounds: number }) => {
      console.log('🔄 Round started:', data);
      cbRef.current.onRoundStarted?.(data);
    });

    channel.on('display:truth_results_progress', (data) => {
      console.log('✓ Truth results ready progress:', data);
      cbRef.current.onTruthResultsProgress?.(data);
    });

    channel.on('display:game_ended', (data: { final_scores: LeaderboardEntry[]; winner?: LeaderboardEntry }) => {
      console.log('🎉 Game ended:', data);
      cbRef.current.onGameEnded?.(data);
    });

    channel.on('display:rematch_approved', (data: any) => {
      console.log('✅ Rematch approved (display):', data);
      cbRef.current.onRematchApproved?.(data);
    });

    channel.on('display:rematch_cancelled', (data: any) => {
      console.log('❌ Rematch cancelled (display):', data);
      cbRef.current.onRematchCancelled?.(data);
    });

    // Cleanup
    return () => {
      channel.leave();
      socket.disconnect();
    };
  }, [roomCode]);

  return {
    connected,
    error,
    channel: channelRef.current,
  };
}

