import { useEffect, useRef, useState } from 'react';
import { Socket, Channel } from 'phoenix';
import type { Room, Question, LeaderboardEntry, Player } from '../types/game';
import { getWsUrl } from '../lib/backendConfig';

function normalizeRoomCode(code: string): string {
  return (code || '').toUpperCase().trim();
}

interface UseDisplaySocketProps {
  roomCode: string;
  onGameState?: (state: Room & { current_question?: Question }) => void;
  onPlayerJoined?: (data: { player_id: string; nickname: string; players: Player[] }) => void;
  onPlayerDisconnected?: (data: { player_id: string; nickname?: string; players?: Player[] }) => void;
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
  onPlayersSync?: (data: { players: Player[]; host_id?: string | null }) => void;
}

export function useDisplaySocket({
  roomCode,
  onGameState,
  onPlayerJoined,
  onPlayerDisconnected,
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
  onPlayersSync,
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
    onPlayerDisconnected,
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
    onPlayersSync,
  };

  useEffect(() => {
    const normalizedCode = normalizeRoomCode(roomCode);
    if (!normalizedCode) return;

    const socket = new Socket(getWsUrl(), {
      params: {},
      logger: (kind, msg, data) => {
        console.log(`[${kind}] ${msg}`, data);
      },
    });

    socket.connect();
    socketRef.current = socket;

    const channel = socket.channel(`display:${normalizedCode}`, {});
    channelRef.current = channel;

    channel
      .join()
      .receive('ok', (response: Room & { current_question?: Question }) => {
        console.log('✅ Joined display channel', response);
        setConnected(true);
        setError(null);
        const c = cbRef.current;
        if (c.onGameState) c.onGameState(response);
        if (
          response.current_question &&
          c.onQuestionRevealed &&
          !(response as { truth_resume?: unknown }).truth_resume
        ) {
          c.onQuestionRevealed(response.current_question);
        }
      })
      .receive('error', (response: { reason?: string }) => {
        console.error('❌ Failed to join display channel', response);
        setError(response.reason || 'Failed to join display');
        setConnected(false);
      });

    channel.on('display:player_joined', (data) => {
      cbRef.current.onPlayerJoined?.(data);
    });

    channel.on('display:player_disconnected', (data) => {
      cbRef.current.onPlayerDisconnected?.(data);
    });

    channel.on('display:game_started', (data) => {
      cbRef.current.onGameStarted?.(data);
    });

    channel.on('display:discussion_started', (data) => {
      cbRef.current.onDiscussionStarted?.(data);
    });

    channel.on('display:question_revealed', (data: Question) => {
      cbRef.current.onQuestionRevealed?.(data);
    });

    channel.on('display:option_counts_updated', (data) => {
      cbRef.current.onOptionCountsUpdated?.(data);
    });

    channel.on('display:player_committed', (data) => {
      cbRef.current.onPlayerCommitted?.(data);
    });

    channel.on('display:round_scored', (data) => {
      cbRef.current.onRoundScored?.(data);
    });

    channel.on('display:distortion_used', (data) => {
      cbRef.current.onDistortionUsed?.(data);
    });

    channel.on('display:round_started', (data) => {
      cbRef.current.onRoundStarted?.(data);
    });

    channel.on('display:truth_results_progress', (data) => {
      cbRef.current.onTruthResultsProgress?.(data);
    });

    channel.on('display:game_ended', (data) => {
      cbRef.current.onGameEnded?.(data);
    });

    channel.on('display:rematch_approved', (data) => {
      cbRef.current.onRematchApproved?.(data);
    });

    channel.on('display:rematch_cancelled', (data) => {
      cbRef.current.onRematchCancelled?.(data);
    });

    channel.on('display:players_sync', (data: { players: Player[]; host_id?: string }) => {
      cbRef.current.onPlayersSync?.(data);
    });

    return () => {
      channel.leave();
      socket.disconnect();
    };
  }, [roomCode]);

  const requestForceEnd = () => {
    const channel = channelRef.current;
    if (!channel) return Promise.reject(new Error('Not connected'));
    return new Promise<void>((resolve, reject) => {
      channel
        .push('request_force_end', {})
        .receive('ok', () => resolve())
        .receive('error', (r: { reason?: string }) => reject(new Error(r.reason || 'Failed')));
    });
  };

  const confirmForceEnd = (code: string) => {
    const channel = channelRef.current;
    if (!channel) return Promise.reject(new Error('Not connected'));
    return new Promise<void>((resolve, reject) => {
      channel
        .push('confirm_force_end', { room_code: code })
        .receive('ok', () => resolve())
        .receive('error', (r: { reason?: string }) => reject(new Error(r.reason || 'Failed')));
    });
  };

  const leaveDisplay = () => {
    channelRef.current?.leave();
    socketRef.current?.disconnect();
  };

  return {
    connected,
    error,
    channel: channelRef.current,
    requestForceEnd,
    confirmForceEnd,
    leaveDisplay,
  };
}
