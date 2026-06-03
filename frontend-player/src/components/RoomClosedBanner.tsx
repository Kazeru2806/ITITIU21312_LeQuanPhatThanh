import { useEffect, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { useGameStore } from '../store/gameStore';

interface RoomClosedBannerProps {
  message: string;
  redirectSeconds?: number;
}

export function RoomClosedBanner({ message, redirectSeconds = 30 }: RoomClosedBannerProps) {
  const navigate = useNavigate();
  const reset = useGameStore((s) => s.reset);
  const [left, setLeft] = useState(redirectSeconds);

  useEffect(() => {
    const id = window.setInterval(() => {
      setLeft((prev) => {
        if (prev <= 1) {
          window.clearInterval(id);
          reset();
          navigate('/');
          return 0;
        }
        return prev - 1;
      });
    }, 1000);
    return () => window.clearInterval(id);
  }, [navigate, reset]);

  const leaveNow = () => {
    reset();
    navigate('/');
  };

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/60 p-4">
      <div className="bg-white rounded-3xl border-4 border-purple-500 p-8 max-w-md w-full text-center shadow-2xl">
        <h2 className="text-2xl font-black text-purple-800 mb-3">Room closed</h2>
        <p className="text-gray-700 font-medium mb-6">{message}</p>
        <p className="text-sm text-gray-500 mb-4">Returning to main screen in {left}s…</p>
        <button
          type="button"
          onClick={leaveNow}
          className="px-6 py-3 rounded-xl bg-purple-600 text-white font-bold hover:bg-purple-700"
        >
          Leave now
        </button>
      </div>
    </div>
  );
}
