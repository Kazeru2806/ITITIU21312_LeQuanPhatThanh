import { useEffect, useRef, useState } from 'react';
import { Socket, Channel } from 'phoenix';
import type { Room, Question, LeaderboardEntry, Player } from '../types/game';

// Match the backend host automatically (desktop + mobile)
const hostname = window.location.hostname || 'localhost';
const WS_URL = `ws://${hostname}:4000/socket`;

interface UseDisplaySocketProps {
  roomCode: string;
  onGameState?: (state: Room & { current_question?: Question }) => void;
  onPlayerJoined?: (data: { player_id: string; nickname: string; players: Player[] }) => void;
  onGameStarted?: (data: { round: number; total_rounds: number }) => void;
  onQuestionRevealed?: (question: Question) => void;
  onPlayerCommitted?: (data: { player_id: string; nickname: string; timestamp: string }) => void;
  onRoundScored?: (data: {
    round: number;
    scores: Array<{ player_id: string; is_correct: boolean; points: number; answer: string }>;
    leaderboard: LeaderboardEntry[];
    correct_answer: string;
    question: Question;
  }) => void;
  onRoundStarted?: (data: { round: number; total_rounds: number }) => void;
  onGameEnded?: (data: { final_scores: LeaderboardEntry[]; winner?: LeaderboardEntry }) => void;
}

export function useDisplaySocket({
  roomCode,
  onGameState,
  onPlayerJoined,
  onGameStarted,
  onQuestionRevealed,
  onPlayerCommitted,
  onRoundScored,
  onRoundStarted,
  onGameEnded,
}: UseDisplaySocketProps) {
  const [connected, setConnected] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const socketRef = useRef<Socket | null>(null);
  const channelRef = useRef<Channel | null>(null);

  useEffect(() => {
    if (!roomCode) return;

    // Create socket connection
    const socket = new Socket(WS_URL, {
      params: {},
      logger: (kind, msg, data) => {
        console.log(`[${kind}] ${msg}`, data);
      },
    });

    socket.connect();
    socketRef.current = socket;

    // Join display channel
    const channel = socket.channel(`display:${roomCode}`, {});

    channelRef.current = channel;

    // Handle join response
    channel
      .join()
      .receive('ok', (response: Room & { current_question?: Question }) => {
        console.log('✅ Joined display channel', response);
        setConnected(true);
        setError(null);
        if (onGameState) {
          onGameState(response);
        }
        if (response.current_question && onQuestionRevealed) {
          onQuestionRevealed(response.current_question);
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
      if (onPlayerJoined) onPlayerJoined(data);
    });

    channel.on('display:game_started', (data: { round: number; total_rounds: number }) => {
      console.log('🎮 Game started:', data);
      if (onGameStarted) onGameStarted(data);
    });

    channel.on('display:question_revealed', (data: Question) => {
      console.log('❓ Question revealed:', data);
      if (onQuestionRevealed) onQuestionRevealed(data);
    });

    channel.on('display:player_committed', (data: { player_id: string; nickname: string; timestamp: string }) => {
      console.log('✅ Player committed:', data);
      if (onPlayerCommitted) onPlayerCommitted(data);
    });

    channel.on('display:round_scored', (data: {
      round: number;
      scores: Array<{ player_id: string; is_correct: boolean; points: number; answer: string }>;
      leaderboard: LeaderboardEntry[];
      correct_answer: string;
      question: Question;
    }) => {
      console.log('🎯 Round scored:', data);
      if (onRoundScored) onRoundScored(data);
    });

    channel.on('display:round_started', (data: { round: number; total_rounds: number }) => {
      console.log('🔄 Round started:', data);
      if (onRoundStarted) onRoundStarted(data);
    });

    channel.on('display:game_ended', (data: { final_scores: LeaderboardEntry[]; winner?: LeaderboardEntry }) => {
      console.log('🎉 Game ended:', data);
      if (onGameEnded) onGameEnded(data);
    });

    // Cleanup
    return () => {
      channel.leave();
      socket.disconnect();
    };
  }, [roomCode, onGameState, onPlayerJoined, onGameStarted, onQuestionRevealed, onPlayerCommitted, onRoundScored, onRoundStarted, onGameEnded]);

  return {
    connected,
    error,
    channel: channelRef.current,
  };
}

