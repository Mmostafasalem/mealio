"use client";

import { useEffect, type ReactNode, type ComponentType } from "react";
import {
  motion, useMotionValue, useTransform, useSpring,
} from "motion/react";

const SPRING = { type: "spring", stiffness: 240, damping: 26 } as const;

export function Card({ children, className = "", delay = 0, hover = true }: {
  children: ReactNode; className?: string; delay?: number; hover?: boolean;
}) {
  return (
    <motion.section
      className={`soft-shadow rounded-[var(--radius-card)] bg-surface p-6 ring-1 ring-black/5 dark:ring-white/5 ${className}`}
      initial={{ opacity: 0, y: 18, filter: "blur(6px)" }}
      whileInView={{ opacity: 1, y: 0, filter: "blur(0px)" }}
      viewport={{ once: true, margin: "-40px" }}
      transition={{ ...SPRING, delay: delay / 1000 }}
      whileHover={hover ? { y: -3, transition: { ...SPRING, damping: 18 } } : undefined}
    >
      {children}
    </motion.section>
  );
}

/** Number that springs from its previous value to the new one. */
export function AnimatedNumber({ value, className, format }: {
  value: number; className?: string; format?: (n: number) => string;
}) {
  const mv = useMotionValue(value);
  const spring = useSpring(mv, { stiffness: 90, damping: 20 });
  const text = useTransform(spring, (v) =>
    format ? format(v) : Math.round(v).toLocaleString(),
  );
  useEffect(() => { mv.set(value); }, [value, mv]);
  return <motion.span className={className}>{text}</motion.span>;
}

/** Scroll/mount reveal for non-card content. */
export function Reveal({ children, delay = 0, className }: {
  children: ReactNode; delay?: number; className?: string;
}) {
  return (
    <motion.div className={className}
      initial={{ opacity: 0, y: 14, filter: "blur(5px)" }}
      whileInView={{ opacity: 1, y: 0, filter: "blur(0px)" }}
      viewport={{ once: true, margin: "-40px" }}
      transition={{ ...SPRING, delay: delay / 1000 }}>
      {children}
    </motion.div>
  );
}

export function PageHeader({ title, subtitle, eyebrow }: {
  title: string; subtitle?: string; eyebrow?: string;
}) {
  return (
    <header className="mb-7">
      {eyebrow && (
        <span className="mb-2.5 inline-block rounded-full bg-brand/10 px-3 py-1 text-[10px] font-semibold uppercase tracking-[0.2em] text-brand">
          {eyebrow}
        </span>
      )}
      <h1 className="text-3xl font-bold">{title}</h1>
      {subtitle && <p className="mt-1.5 max-w-prose text-sm text-muted">{subtitle}</p>}
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
      ? "bg-brand text-white shadow-[0_8px_24px_-8px_var(--brand)]"
      : "bg-brand/10 text-brand";
  return (
    <button type={type} onClick={onClick} disabled={disabled}
      className={`press flex h-12 w-full items-center justify-center gap-2 rounded-full font-semibold disabled:opacity-50 ${styles}`}>
      {children}
    </button>
  );
}

export function Chip({ active, onClick, children }: {
  active: boolean; onClick: () => void; children: ReactNode;
}) {
  return (
    <button onClick={onClick}
      className={`press rounded-full px-4 py-2 text-sm font-medium ${
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
          <AnimatedNumber value={Math.round(grams)} />{goal ? ` / ${Math.round(goal)}` : ""} g
        </span>
      </div>
      <div className="h-2.5 overflow-hidden rounded-full bg-black/10 dark:bg-white/10">
        <motion.div className="h-full rounded-full"
          initial={{ width: 0 }}
          animate={{ width: `${pct}%` }}
          transition={{ type: "spring", stiffness: 90, damping: 20, delay: 0.15 }}
          style={{ background: color }} />
      </div>
    </div>
  );
}

/** Calorie progress ring that draws itself in and re-springs when the value changes. */
export function CalorieRing({ consumed, goal, size = 168 }: {
  consumed: number; goal: number; size?: number;
}) {
  const stroke = 13;
  const r = (size - stroke) / 2;
  const c = 2 * Math.PI * r;
  const pct = goal > 0 ? Math.min(consumed / goal, 1) : 0;
  const over = consumed > goal;
  const color = over ? "var(--brand-danger)" : "var(--calorie)";
  return (
    <div className="relative shrink-0" style={{ width: size, height: size }}>
      <svg width={size} height={size} className="-rotate-90">
        <circle cx={size / 2} cy={size / 2} r={r} fill="none"
          stroke="currentColor" strokeWidth={stroke}
          className="text-black/[0.07] dark:text-white/[0.08]" />
        <motion.circle cx={size / 2} cy={size / 2} r={r} fill="none"
          stroke={color} strokeWidth={stroke} strokeLinecap="round"
          strokeDasharray={c}
          initial={{ strokeDashoffset: c }}
          animate={{ strokeDashoffset: c * (1 - pct) }}
          transition={{ type: "spring", stiffness: 55, damping: 18, delay: 0.1 }}
          style={{ filter: `drop-shadow(0 0 6px ${over ? "var(--brand-danger)" : "var(--calorie)"}40)` }} />
      </svg>
      <div className="absolute inset-0 flex flex-col items-center justify-center">
        <AnimatedNumber value={Math.max(goal - consumed, 0)}
          className="text-3xl font-bold tabular-nums" />
        <span className="text-xs text-muted">kcal left</span>
      </div>
    </div>
  );
}

export function EmptyState({ icon: Icon, title, message, action }: {
  icon: ComponentType<{ size?: number; weight?: "regular" | "duotone" | "fill" }>;
  title: string; message: string; action?: ReactNode;
}) {
  return (
    <div className="flex flex-col items-center gap-3 py-12 text-center">
      <div className="flex h-14 w-14 items-center justify-center rounded-2xl bg-brand/10 text-brand">
        <Icon size={26} weight="duotone" />
      </div>
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
