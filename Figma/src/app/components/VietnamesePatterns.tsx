export function LotusPattern({ className = "" }: { className?: string }) {
  return (
    <svg
      viewBox="0 0 100 100"
      className={className}
      fill="none"
      xmlns="http://www.w3.org/2000/svg"
    >
      {/* Lotus flower */}
      <ellipse cx="50" cy="65" rx="8" ry="15" fill="#FF6B9D" opacity="0.6" />
      <ellipse
        cx="50"
        cy="65"
        rx="8"
        ry="15"
        fill="#9D4EDD"
        opacity="0.6"
        transform="rotate(45 50 65)"
      />
      <ellipse
        cx="50"
        cy="65"
        rx="8"
        ry="15"
        fill="#FF9E3D"
        opacity="0.6"
        transform="rotate(90 50 65)"
      />
      <ellipse
        cx="50"
        cy="65"
        rx="8"
        ry="15"
        fill="#FF6B9D"
        opacity="0.6"
        transform="rotate(135 50 65)"
      />
      <circle cx="50" cy="65" r="6" fill="#FFE5EC" />
      
      {/* Stem */}
      <path
        d="M50 65 Q48 80 50 95"
        stroke="#7D5A8A"
        strokeWidth="2"
        fill="none"
      />
    </svg>
  );
}

export function DragonPattern({ className = "" }: { className?: string }) {
  return (
    <svg
      viewBox="0 0 150 100"
      className={className}
      fill="none"
      xmlns="http://www.w3.org/2000/svg"
    >
      {/* Dragon cloud pattern */}
      <path
        d="M20 50 Q30 40 40 50 Q50 60 60 50 Q70 40 80 50 Q90 60 100 50 Q110 40 120 50"
        stroke="#9D4EDD"
        strokeWidth="4"
        strokeLinecap="round"
        opacity="0.4"
      />
      <path
        d="M15 60 Q25 50 35 60 Q45 70 55 60 Q65 50 75 60 Q85 70 95 60 Q105 50 115 60"
        stroke="#FF6B9D"
        strokeWidth="4"
        strokeLinecap="round"
        opacity="0.4"
      />
      <path
        d="M25 70 Q35 60 45 70 Q55 80 65 70 Q75 60 85 70 Q95 80 105 70"
        stroke="#FF9E3D"
        strokeWidth="4"
        strokeLinecap="round"
        opacity="0.4"
      />
    </svg>
  );
}

export function LanternPattern({ className = "" }: { className?: string }) {
  return (
    <svg
      viewBox="0 0 60 100"
      className={className}
      fill="none"
      xmlns="http://www.w3.org/2000/svg"
    >
      {/* Traditional lantern */}
      <rect x="15" y="25" width="30" height="50" rx="15" fill="#FF9E3D" opacity="0.7" />
      <rect x="18" y="28" width="24" height="44" rx="12" fill="#FFB366" opacity="0.5" />
      
      {/* Top decoration */}
      <circle cx="30" cy="20" r="5" fill="#9D4EDD" />
      <path d="M30 15 L30 5" stroke="#9D4EDD" strokeWidth="2" />
      
      {/* Bottom tassel */}
      <path d="M30 75 L30 85" stroke="#FF6B9D" strokeWidth="3" strokeLinecap="round" />
      <circle cx="30" cy="88" r="3" fill="#FF6B9D" />
      
      {/* Horizontal lines */}
      <line x1="15" y1="35" x2="45" y2="35" stroke="#2D1B3D" strokeWidth="1" opacity="0.3" />
      <line x1="15" y1="50" x2="45" y2="50" stroke="#2D1B3D" strokeWidth="1" opacity="0.3" />
      <line x1="15" y1="65" x2="45" y2="65" stroke="#2D1B3D" strokeWidth="1" opacity="0.3" />
    </svg>
  );
}

export function BambooPattern({ className = "" }: { className?: string }) {
  return (
    <svg
      viewBox="0 0 80 150"
      className={className}
      fill="none"
      xmlns="http://www.w3.org/2000/svg"
    >
      {/* Bamboo stalks */}
      <path
        d="M30 10 L30 140"
        stroke="#7D5A8A"
        strokeWidth="4"
        strokeLinecap="round"
        opacity="0.4"
      />
      <path
        d="M50 20 L50 150"
        stroke="#9D4EDD"
        strokeWidth="4"
        strokeLinecap="round"
        opacity="0.4"
      />
      
      {/* Bamboo segments */}
      <line x1="25" y1="40" x2="35" y2="40" stroke="#9D4EDD" strokeWidth="3" opacity="0.6" />
      <line x1="25" y1="70" x2="35" y2="70" stroke="#9D4EDD" strokeWidth="3" opacity="0.6" />
      <line x1="25" y1="100" x2="35" y2="100" stroke="#9D4EDD" strokeWidth="3" opacity="0.6" />
      <line x1="45" y1="50" x2="55" y2="50" stroke="#7D5A8A" strokeWidth="3" opacity="0.6" />
      <line x1="45" y1="80" x2="55" y2="80" stroke="#7D5A8A" strokeWidth="3" opacity="0.6" />
      <line x1="45" y1="110" x2="55" y2="110" stroke="#7D5A8A" strokeWidth="3" opacity="0.6" />
      
      {/* Leaves */}
      <path d="M30 35 Q20 30 15 25" stroke="#FF9E3D" strokeWidth="2" opacity="0.5" />
      <path d="M30 45 Q20 50 15 55" stroke="#FF6B9D" strokeWidth="2" opacity="0.5" />
      <path d="M50 55 Q60 50 65 45" stroke="#FF9E3D" strokeWidth="2" opacity="0.5" />
      <path d="M50 65 Q60 70 65 75" stroke="#9D4EDD" strokeWidth="2" opacity="0.5" />
    </svg>
  );
}
