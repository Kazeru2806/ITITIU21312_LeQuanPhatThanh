export function PhoThePhoenix({ className = "" }: { className?: string }) {
  return (
    <svg
      viewBox="0 0 200 240"
      className={className}
      fill="none"
      xmlns="http://www.w3.org/2000/svg"
    >
      {/* Bowl of Pho - Base */}
      <ellipse cx="100" cy="180" rx="70" ry="20" fill="#FF9E3D" />
      <path
        d="M30 180 L30 160 Q30 140 50 140 L150 140 Q170 140 170 160 L170 180"
        fill="#FFB366"
        stroke="#FF9E3D"
        strokeWidth="3"
      />
      
      {/* Noodles */}
      <path
        d="M50 155 Q60 150 70 155 Q80 160 90 155 Q100 150 110 155 Q120 160 130 155 Q140 150 150 155"
        stroke="#FFF5E1"
        strokeWidth="4"
        strokeLinecap="round"
        fill="none"
      />
      <path
        d="M55 165 Q65 160 75 165 Q85 170 95 165 Q105 160 115 165 Q125 170 135 165"
        stroke="#FFF5E1"
        strokeWidth="4"
        strokeLinecap="round"
        fill="none"
      />

      {/* Phoenix Body */}
      <ellipse cx="100" cy="110" rx="35" ry="40" fill="#FF6B9D" />
      
      {/* Phoenix Wings - Left */}
      <path
        d="M65 110 Q50 100 45 85 Q40 70 50 60"
        stroke="#9D4EDD"
        strokeWidth="8"
        strokeLinecap="round"
        fill="none"
      />
      <path
        d="M60 115 Q45 110 40 95"
        stroke="#C77DFF"
        strokeWidth="6"
        strokeLinecap="round"
        fill="none"
      />
      
      {/* Phoenix Wings - Right */}
      <path
        d="M135 110 Q150 100 155 85 Q160 70 150 60"
        stroke="#9D4EDD"
        strokeWidth="8"
        strokeLinecap="round"
        fill="none"
      />
      <path
        d="M140 115 Q155 110 160 95"
        stroke="#C77DFF"
        strokeWidth="6"
        strokeLinecap="round"
        fill="none"
      />

      {/* Phoenix Head */}
      <circle cx="100" cy="85" r="25" fill="#FF85B3" />
      
      {/* Eyes */}
      <circle cx="92" cy="82" r="4" fill="#2D1B3D" />
      <circle cx="108" cy="82" r="4" fill="#2D1B3D" />
      <circle cx="93" cy="81" r="1.5" fill="white" />
      <circle cx="109" cy="81" r="1.5" fill="white" />
      
      {/* Beak */}
      <path
        d="M100 88 L95 93 L100 91 L105 93 Z"
        fill="#FF9E3D"
      />
      
      {/* Happy expression */}
      <path
        d="M92 92 Q100 98 108 92"
        stroke="#2D1B3D"
        strokeWidth="2"
        strokeLinecap="round"
        fill="none"
      />

      {/* Phoenix Tail Feathers */}
      <path
        d="M100 150 Q95 170 90 190"
        stroke="#FF6B9D"
        strokeWidth="6"
        strokeLinecap="round"
        fill="none"
      />
      <path
        d="M100 150 Q100 175 100 195"
        stroke="#9D4EDD"
        strokeWidth="6"
        strokeLinecap="round"
        fill="none"
      />
      <path
        d="M100 150 Q105 170 110 190"
        stroke="#FF9E3D"
        strokeWidth="6"
        strokeLinecap="round"
        fill="none"
      />

      {/* Crest/Crown feathers */}
      <path
        d="M85 75 Q83 65 85 55"
        stroke="#FF9E3D"
        strokeWidth="5"
        strokeLinecap="round"
        fill="none"
      />
      <path
        d="M100 70 Q100 58 100 48"
        stroke="#9D4EDD"
        strokeWidth="5"
        strokeLinecap="round"
        fill="none"
      />
      <path
        d="M115 75 Q117 65 115 55"
        stroke="#FF6B9D"
        strokeWidth="5"
        strokeLinecap="round"
        fill="none"
      />

      {/* Decorative Vietnamese pattern on bowl */}
      <path
        d="M50 145 L55 145 M65 145 L70 145 M80 145 L85 145 M95 145 L100 145 M110 145 L115 145 M125 145 L130 145 M140 145 L145 145"
        stroke="#FFF5E1"
        strokeWidth="2"
      />
    </svg>
  );
}
