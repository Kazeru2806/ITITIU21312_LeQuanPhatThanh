import type { ReactNode } from 'react';
import { BambooPattern, DragonPattern, LanternPattern, LotusPattern } from './VietnamesePatterns';

export function HostPageShell({ children }: { children: ReactNode }) {
  return (
    <div className="min-h-screen relative overflow-hidden bg-background">
      <div className="absolute inset-0 overflow-hidden pointer-events-none opacity-70">
        <LotusPattern className="absolute top-10 left-10 w-16 h-16 md:w-24 md:h-24 animate-pulse" />
        <LotusPattern
          className="absolute bottom-20 right-20 w-20 h-20 md:w-28 md:h-28 animate-pulse"
          style={{ animationDelay: '1s' }}
        />
        <DragonPattern className="absolute top-1/4 right-6 w-32 h-20 md:w-48 md:h-32 opacity-50" />
        <DragonPattern className="absolute bottom-1/3 left-6 w-32 h-20 md:w-48 md:h-32 opacity-50" />
        <LanternPattern
          className="absolute top-1/3 left-1/4 w-12 h-16 md:w-16 md:h-24 animate-bounce"
          style={{ animationDuration: '3s' }}
        />
        <LanternPattern
          className="absolute bottom-1/4 right-1/3 w-12 h-16 md:w-14 md:h-20 animate-bounce"
          style={{ animationDuration: '3.5s' }}
        />
        <BambooPattern className="absolute top-0 right-0 w-16 h-32 md:w-20 md:h-40 opacity-25" />
        <BambooPattern className="absolute bottom-0 left-0 w-16 h-32 md:w-20 md:h-40 opacity-25" />
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
        <div
          className="absolute rounded-full blur-3xl opacity-20 animate-pulse"
          style={{
            width: '500px',
            height: '500px',
            background: 'radial-gradient(circle, #9D4EDD 0%, transparent 70%)',
            bottom: '-10%',
            right: '-10%',
            animationDuration: '5s',
            animationDelay: '1s',
          }}
        />
        <div
          className="absolute rounded-full blur-3xl opacity-20 animate-pulse"
          style={{
            width: '350px',
            height: '350px',
            background: 'radial-gradient(circle, #FF9E3D 0%, transparent 70%)',
            top: '50%',
            left: '50%',
            transform: 'translate(-50%, -50%)',
            animationDuration: '6s',
            animationDelay: '2s',
          }}
        />
      </div>

      <div className="relative z-10">{children}</div>
    </div>
  );
}

export function HostTitle({ children }: { children: ReactNode }) {
  return (
    <h1
      className="mb-2 text-center"
      style={{
        fontFamily: "'Bangers', cursive",
        fontSize: 'clamp(2.5rem, 8vw, 4.5rem)',
        lineHeight: 1.1,
        color: '#9D4EDD',
        textShadow: '4px 4px 0px #FF6B9D, 8px 8px 0px #FF9E3D',
        letterSpacing: '0.05em',
      }}
    >
      {children}
    </h1>
  );
}

export function HostSubtitle({ children }: { children: ReactNode }) {
  return (
    <p
      className="text-center mb-6"
      style={{
        fontFamily: "'Fredoka', sans-serif",
        fontSize: '1.1rem',
        color: '#7D5A8A',
      }}
    >
      {children}
    </p>
  );
}
