import React from "react";
import { theme } from "./theme";

export type Mood = "smile" | "sad" | "wow";

// The bowl from the app icon (docs/brand/app-icon.swift), redrawn as SVG so it can move.
// `fruit` is how far each of the three toppings has dropped in (0 = not yet, 1 = landed).
export const Bowl: React.FC<{
  width: number;
  mood?: Mood;
  fruit?: [number, number, number];
  blink?: boolean;
  arms?: number; // 0 hidden, 1 raised
  look?: number; // eyes shift left/right, -1…1
  barbell?: boolean; // held in the raised hands
}> = ({ width, mood = "smile", fruit = [1, 1, 1], blink = false, arms = 0, look = 0, barbell = false }) => {
  const drop = (p: number) => ({ transform: `translateY(${-(1 - Math.min(Math.max(p, 0), 1)) * 520}px)`, opacity: p <= 0 ? 0 : 1 });
  const berry = (x: number, y: number, w: number, tilt: number) => (
    <g transform={`translate(${x} ${y}) rotate(${(tilt * 180) / Math.PI})`}>
      <path
        d={`M0,${0.95 * w} C${-0.35 * w},${0.7 * w} ${-0.66 * w},${0.2 * w} ${-0.62 * w},${-0.25 * w} C${-0.55 * w},${-0.72 * w} ${0.55 * w},${-0.72 * w} ${0.62 * w},${-0.25 * w} C${0.66 * w},${0.2 * w} ${0.35 * w},${0.7 * w} 0,${0.95 * w}Z`}
        fill="#D25467"
      />
      <ellipse cx={0.3 * w} cy={0.3 * w} rx={0.25 * w} ry={0.4 * w} fill="#B23F55" opacity={0.5} />
      {[[-0.25, 0], [0.2, 0.05], [-0.05, 0.35], [0.28, 0.4], [-0.3, 0.38], [0.02, -0.2]].map(([sx, sy], i) => (
        <ellipse key={i} cx={sx * w} cy={sy * w} rx={6} ry={8} fill="#F6E3A8" />
      ))}
      {[-0.9, -0.3, 0.3, 0.9].map((a, i) => (
        <ellipse key={i} cx={0} cy={-0.21 * w} rx={10} ry={0.21 * w} fill="#6FA77A" transform={`rotate(${(a * 180) / Math.PI} 0 ${-0.42 * w}) translate(0 ${-0.42 * w})`} />
      ))}
    </g>
  );
  const eyeRy = blink ? 4 : 31;
  const ex = look * 8;
  return (
    <svg width={width} height={(width * 600) / 784} viewBox="120 270 784 600" style={{ overflow: "visible" }}>
      {arms > 0 &&
        [-1, 1].map((side) => {
          const x1 = 512 + side * 292, y1 = 540;
          const x2 = 512 + side * (380 - 42 * arms), y2 = 600 - 244 * arms;
          return (
            <g key={side} strokeLinecap="round" opacity={Math.min(arms * 3, 1)}>
              <line x1={x1} y1={y1} x2={x2} y2={y2} stroke={theme.pinkDeep} strokeWidth={92} />
              <line x1={x1} y1={y1} x2={x2 - side * 4} y2={y2 + 2} stroke={theme.pink} strokeWidth={78} />
            </g>
          );
        })}
      {barbell && arms > 0 && (
        <g>
          <line x1={40} y1={560 - 244 * arms} x2={984} y2={560 - 244 * arms} stroke={theme.ink} strokeWidth={20} strokeLinecap="round" />
          {[-1, 1].map((side) => (
            <g key={side}>
              <rect x={512 + side * 452 - 26} y={560 - 244 * arms - 92} width={52} height={184} rx={18} fill={theme.ink} />
              <rect x={512 + side * 392 - 20} y={560 - 244 * arms - 66} width={40} height={132} rx={14} fill="#4F5F96" />
            </g>
          ))}
        </g>
      )}
      <defs>
        <linearGradient id="bowlShade" x1="170" y1="600" x2="854" y2="700" gradientUnits="userSpaceOnUse">
          <stop offset="0" stopColor="#fff" stopOpacity="0.16" />
          <stop offset="0.42" stopColor={theme.pink} stopOpacity="0" />
          <stop offset="1" stopColor={theme.pinkDeep} stopOpacity="0.75" />
        </linearGradient>
      </defs>
      <path id="bowlBody" d="M170,470 C174,712 340,832 512,832 C684,832 850,712 854,470Z" fill={theme.pink} />
      <path d="M170,470 C174,712 340,832 512,832 C684,832 850,712 854,470Z" fill="url(#bowlShade)" />
      <ellipse cx={512} cy={470} rx={342} ry={74} fill={theme.pinkDeep} />
      <ellipse cx={512} cy={468} rx={308} ry={56} fill={theme.cream} />

      <g style={drop(fruit[0])}>
        {[[380, 418, 66], [482, 448, 58]].map(([x, y, r], i) => (
          <g key={i}>
            <ellipse cx={x} cy={y} rx={r} ry={r * 0.82} fill="#F6E3A8" />
            {[0, 1, 2, 3, 4].map((k) => {
              const a = (k / 5) * Math.PI * 2 - Math.PI / 2;
              return <ellipse key={k} cx={x + Math.cos(a) * r * 0.32} cy={y + Math.sin(a) * r * 0.27} rx={7} ry={5} fill="#E2C676" />;
            })}
          </g>
        ))}
      </g>
      <g style={drop(fruit[2])}>
        {berry(668, 408, 84, 0.18)}
        {berry(758, 438, 68, -0.25)}
      </g>
      <g style={drop(fruit[1])}>
        {[[578, 418, 31], [548, 466, 29], [608, 472, 30]].map(([x, y, r], i) => (
          <g key={i}>
            <ellipse cx={x} cy={y} rx={r} ry={r * 0.92} fill="#4F5F96" />
            <ellipse cx={x + r * 0.4} cy={y + r * 0.32} rx={r * 0.5} ry={r * 0.52} fill="#374573" opacity={0.55} />
            <ellipse cx={x - r * 0.37} cy={y - r * 0.42} rx={r * 0.25} ry={r * 0.2} fill="#8090C4" opacity={0.8} />
          </g>
        ))}
      </g>

      <ellipse cx={428 + ex} cy={625} rx={28} ry={eyeRy} fill={theme.ink} />
      <ellipse cx={596 + ex} cy={625} rx={28} ry={eyeRy} fill={theme.ink} />
      {!blink && (
        <>
          <circle cx={432 + ex} cy={612} r={8} fill="#fff" opacity={0.85} />
          <circle cx={600 + ex} cy={612} r={8} fill="#fff" opacity={0.85} />
        </>
      )}
      {mood === "smile" && <path d="M558.9,700.1 A58,58 0 0 1 465.1,700.1" stroke={theme.ink} strokeWidth={22} strokeLinecap="round" fill="none" />}
      {mood === "sad" && <path d="M470,722 A58,58 0 0 1 554,722" stroke={theme.ink} strokeWidth={22} strokeLinecap="round" fill="none" />}
      {mood === "wow" && <ellipse cx={512} cy={708} rx={26} ry={30} fill={theme.ink} />}
      <ellipse cx={358} cy={688} rx={32} ry={18} fill={theme.pinkLight} opacity={0.75} />
      <ellipse cx={666} cy={688} rx={32} ry={18} fill={theme.pinkLight} opacity={0.75} />
    </svg>
  );
};
