import { useEffect, useState } from 'react';

/** Server-authoritative countdown from `phase_ends_at_ms` (Unix ms). */
export function usePhaseTimer(
  phaseEndsAtMs: number | null | undefined,
  fallbackSeconds = 0,
  active = true
) {
  const [secondsLeft, setSecondsLeft] = useState(fallbackSeconds);

  useEffect(() => {
    if (!active) {
      return;
    }

    if (!phaseEndsAtMs) {
      setSecondsLeft(fallbackSeconds);
      return;
    }

    const tick = () => {
      const left = Math.max(0, Math.ceil((phaseEndsAtMs - Date.now()) / 1000));
      setSecondsLeft(left);
    };

    tick();
    const id = window.setInterval(tick, 250);
    return () => window.clearInterval(id);
  }, [phaseEndsAtMs, fallbackSeconds, active]);

  return secondsLeft;
}
