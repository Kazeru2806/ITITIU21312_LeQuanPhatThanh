import { useState } from "react";
import { useNavigate } from 'react-router-dom';
import { api } from '../lib/api';
import { useGameStore } from '../store/gameStore';
import { PhoThePhoenix } from "../components/PhoThePhoenix";
import { LotusPattern, DragonPattern, LanternPattern, BambooPattern } from "../components/VietnamesePatterns";
import { Button } from "../components/ui/button";
import { Input } from "../components/ui/input";
import { Card } from "../components/ui/card";

export function JoinPage() {
  const navigate = useNavigate();
  const setPlayerInfo = useGameStore((state) => state.setPlayerInfo);
  const setRoomCode = useGameStore((state) => state.setRoomCode);
  
  const [roomCode, setRoomCodeInput] = useState("");
  const [nickname, setNickname] = useState("");
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const handleJoinRoom = async () => {
    if (!nickname.trim()) {
      setError('Please enter your name');
      return;
    }

    if (!roomCode.trim()) {
      setError('Please enter a room code');
      return;
    }

    setLoading(true);
    setError(null);

    try {
      const response = await api.joinRoom(roomCode, nickname);

      // Update store
      setPlayerInfo(
        response.player.id,
        response.player.nickname,
        response.player.is_host
      );
      setRoomCode(roomCode.toUpperCase());

      // Navigate to lobby
      navigate('/lobby');
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to join room');
    } finally {
      setLoading(false);
    }
  };

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

      {/* Main Content */}
      <div className="relative z-10 flex flex-col items-center justify-center min-h-screen px-4 py-8">
        {/* Logo/Title Area */}
        <div className="text-center mb-8 animate-in fade-in slide-in-from-top duration-700">
          <h1 className="mb-2" style={{ 
            fontFamily: "'Bangers', cursive",
            fontSize: "clamp(2.5rem, 8vw, 5rem)",
            lineHeight: "1.1",
            color: "#9D4EDD",
            textShadow: "4px 4px 0px #FF6B9D, 8px 8px 0px #FF9E3D",
            letterSpacing: "0.05em"
          }}>
            VN PARTY
          </h1>
          <div className="mb-4" style={{
            fontFamily: "'Bangers', cursive",
            fontSize: "clamp(1.8rem, 6vw, 3.5rem)",
            color: "#FF9E3D",
            textShadow: "3px 3px 0px #FF6B9D",
            letterSpacing: "0.05em"
          }}>
            Vietnamese Party Trivia
          </div>
        </div>

        {/* Mascot */}
        <div className="mb-8 animate-in fade-in zoom-in duration-700" style={{ animationDelay: "0.2s" }}>
          <PhoThePhoenix className="w-48 h-56 md:w-64 md:h-72 drop-shadow-2xl hover:scale-110 transition-transform duration-300" />
        </div>

        {/* Mascot Name */}
        <div className="mb-8 text-center animate-in fade-in slide-in-from-bottom duration-700" style={{ animationDelay: "0.3s" }}>
          <div className="inline-block bg-gradient-to-r from-pink-500 via-purple-500 to-orange-500 p-1 rounded-3xl shadow-lg">
            <div className="bg-white px-8 py-3 rounded-3xl">
              <p style={{
                fontFamily: "'Bangers', cursive",
                fontSize: "clamp(1.2rem, 4vw, 2rem)",
                color: "#9D4EDD",
                letterSpacing: "0.05em"
              }}>
                Play with Pho the Phoenix
              </p>
            </div>
          </div>
        </div>

        {/* Game Controls */}
        <Card className="w-full max-w-md p-8 bg-white/95 backdrop-blur shadow-2xl border-4 border-purple-500 animate-in fade-in slide-in-from-bottom duration-700" style={{ animationDelay: "0.4s", borderRadius: "2rem" }}>
          <div className="space-y-6">
            {/* Error Message */}
            {error && (
              <div className="p-4 bg-red-50 border-2 border-red-300 rounded-xl text-red-700 font-semibold shadow-md">
                {error}
              </div>
            )}

            {/* Name Input */}
            <div className="space-y-3">
              <label className="block" style={{
                fontFamily: "'Fredoka', sans-serif",
                fontSize: "1.1rem",
                color: "#2D1B3D"
              }}>
                Your name:
              </label>
              <div className="relative">
                <Input
                  type="text"
                  value={nickname}
                  onChange={(e) => setNickname(e.target.value)}
                  placeholder="Enter your name..."
                  maxLength={20}
                  className="w-full py-6 px-4 rounded-xl border-3 border-purple-300 focus:border-pink-500 transition-colors"
                  style={{
                    fontSize: "1.5rem",
                    fontFamily: "'Fredoka', sans-serif",
                    background: "#FFF0F5"
                  }}
                />
                <div className="absolute right-4 top-1/2 -translate-y-1/2 text-xs text-gray-400 font-semibold">
                  {nickname.length}/20
                </div>
              </div>
            </div>

            {/* Join Room */}
            <div className="space-y-3">
              <label className="block" style={{
                fontFamily: "'Fredoka', sans-serif",
                fontSize: "1.1rem",
                color: "#2D1B3D"
              }}>
                Room code:
              </label>
              <Input
                type="text"
                placeholder="e.g. ABC123"
                value={roomCode}
                onChange={(e) => setRoomCodeInput(e.target.value.toUpperCase())}
                className="w-full py-6 px-4 rounded-xl border-3 border-purple-300 focus:border-pink-500 transition-colors"
                style={{
                  fontSize: "1.5rem",
                  fontFamily: "'Fredoka', sans-serif",
                  textAlign: "center",
                  letterSpacing: "0.3em",
                  textTransform: "uppercase"
                }}
                maxLength={6}
              />
              <Button 
                onClick={handleJoinRoom}
                disabled={loading || roomCode.length !== 6 || !nickname.trim()}
                className="w-full py-6 rounded-2xl shadow-lg hover:shadow-xl transition-all duration-300 hover:scale-105 disabled:opacity-50 disabled:cursor-not-allowed disabled:hover:scale-100"
                style={{
                  fontSize: "1.5rem",
                  fontFamily: "'Fredoka', sans-serif",
                  background: (roomCode.length === 6 && nickname.trim()) 
                    ? "linear-gradient(135deg, #FF9E3D 0%, #FF6B9D 100%)" 
                    : "#E5E5E5",
                  border: "3px solid #2D1B3D",
                  color: (roomCode.length === 6 && nickname.trim()) ? "#FFFFFF" : "#999999"
                }}
              >
                {loading ? 'Working...' : 'JOIN'}
              </Button>
            </div>
          </div>
        </Card>

        {/* Footer Message */}
        <div className="mt-8 text-center animate-in fade-in duration-700" style={{ animationDelay: "0.6s" }}>
          <p style={{
            fontFamily: "'Fredoka', sans-serif",
            fontSize: "1rem",
            color: "#7D5A8A",
            maxWidth: "500px"
          }}>
            Cùng nhau chơi, cười và tạo kỷ niệm với những trò chơi vui nhộn từ Việt Nam!
          </p>
        </div>
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
    </div>
  );
}

