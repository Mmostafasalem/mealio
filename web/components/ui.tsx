"use client";

import type { ReactNode } from "react";

export function Card({ children, className = "" }: { children: ReactNode; className?: string }) {
  return (
    <section className={`rounded-[var(--radius-card)] bg-surface p-6 shadow-sm ${className}`}>
      {children}
    </section>
  );
}

export function PageHeader({ title, subtitle }: { title: string; subtitle?: string }) {
  return (
    <header className="mb-6">
      <h1 className="text-2xl font-bold tracking-tight">{title}</h1>
      {subtitle && <p className="mt-1 text-sm text-muted">{subtitle}</p>}
    </header>
  );
}

export function Button({
  children, onClick, disabled, variant = "primary", type = "button",
}: {
  children: ReactNode; onClick?: () => void; disabled?: boolean;
  variant?: "primary" | "secondary"; type?: "button" | "submit";
}) {
  const styles =
    variant === "primary"
      ? "bg-brand text-white"
      : "bg-brand/10 text-brand";
  return (
    <button type={type} onClick={onClick} disabled={disabled}
      className={`h-12 w-full rounded-[var(--radius-tile)] font-semibold transition active:scale-[0.99] disabled:opacity-50 ${styles}`}>
      {children}
    </button>
  );
}

export function Chip({ active, onClick, children }: {
  active: boolean; onClick: () => void; children: ReactNode;
}) {
  return (
    <button onClick={onClick}
      className={`rounded-full px-4 py-2 text-sm font-medium transition ${
        active ? "bg-brand text-white" : "bg-surface-elevated text-muted ring-1 ring-black/10 dark:ring-white/10"
      }`}>
      {children}
    </button>
  );
}

export function MacroBar({ name, grams, goal, color }: {
  name: string; grams: number; goal?: number; color: string;
}) {
  const denom = goal && goal > 0 ? goal : 250;
  const pct = Math.min((grams / denom) * 100, 100);
  return (
    <div>
      <div className="mb-1 flex justify-between text-sm">
        <span className="font-medium">{name}</span>
        <span className="tabular-nums text-muted">
          {Math.round(grams)}{goal ? ` / ${Math.round(goal)}` : ""} g
        </span>
      </div>
      <div className="h-2 overflow-hidden rounded-full bg-black/10 dark:bg-white/10">
        <div className="h-full rounded-full transition-[width] duration-500"
          style={{ width: `${pct}%`, background: color }} />
      </div>
    </div>
  );
}

/** Calorie progress ring (SVG). */
export function CalorieRing({ consumed, goal, size = 150 }: {
  consumed: number; goal: number; size?: number;
}) {
  const stroke = 12;
  const r = (size - stroke) / 2;
  const c = 2 * Math.PI * r;
  const pct = goal > 0 ? Math.min(consumed / goal, 1) : 0;
  const over = consumed > goal;
  const color = over ? "var(--brand-danger)" : "var(--calorie)";
  return (
    <svg width={size} height={size} className="-rotate-90">
      <circle cx={size / 2} cy={size / 2} r={r} fill="none"
        stroke="currentColor" strokeWidth={stroke} className="text-black/10 dark:text-white/10" />
      <circle cx={size / 2} cy={size / 2} r={r} fill="none"
        stroke={color} strokeWidth={stroke} strokeLinecap="round"
        strokeDasharray={c} strokeDashoffset={c * (1 - pct)}
        className="transition-[stroke-dashoffset] duration-700" />
      <g className="rotate-90" style={{ transformOrigin: "center" }}>
        <text x="50%" y="46%" textAnchor="middle" dominantBaseline="middle"
          className="fill-foreground text-2xl font-bold" style={{ fontVariantNumeric: "tabular-nums" }}>
          {Math.max(goal - consumed, 0)}
        </text>
        <text x="50%" y="60%" textAnchor="middle" dominantBaseline="middle"
          className="fill-muted text-xs">kcal left</text>
      </g>
    </svg>
  );
}

export function EmptyState({ icon, title, message, action }: {
  icon: string; title: string; message: string; action?: ReactNode;
}) {
  return (
    <div className="flex flex-col items-center gap-2 py-10 text-center">
      <div className="text-4xl">{icon}</div>
      <p className="font-semibold">{title}</p>
      <p className="max-w-xs text-sm text-muted">{message}</p>
      {action && <div className="mt-2">{action}</div>}
    </div>
  );
}

export function Spinner() {
  return (
    <div className="mx-auto my-10 h-8 w-8 animate-spin rounded-full border-2 border-black/10 border-t-brand dark:border-white/10 dark:border-t-brand" />
  );
}
