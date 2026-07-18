"use client";

import { useState } from "react";
import Link from "next/link";
import {
  useLocalStorage, STORAGE, goalCalories,
  type Profile, type LogEntry,
} from "@/lib/store";
import { Card, PageHeader, Button, CalorieRing, MacroBar, EmptyState } from "@/components/ui";

const PRESETS: Omit<LogEntry, "id">[] = [
  { name: "Chicken breast (150g)", calories: 248, protein: 46, carbs: 0, fat: 5 },
  { name: "Eggs (2)", calories: 156, protein: 13, carbs: 1, fat: 11 },
  { name: "Oats (60g)", calories: 233, protein: 8, carbs: 40, fat: 4 },
  { name: "Greek yogurt (200g)", calories: 118, protein: 20, carbs: 8, fat: 1 },
  { name: "Banana", calories: 105, protein: 1, carbs: 27, fat: 0 },
  { name: "Salmon (150g)", calories: 312, protein: 38, carbs: 0, fat: 18 },
];

export default function Dashboard() {
  const [profile, , profileLoaded] = useLocalStorage<Profile | null>(STORAGE.profile, null);
  const [log, setLog] = useLocalStorage<LogEntry[]>(STORAGE.log, []);

  if (!profileLoaded) return null;

  if (!profile) {
    return (
      <Card>
        <EmptyState icon="🎯" title="Set your targets first"
          message="Tell us your body stats and goal to get daily calorie & macro targets, then start tracking."
          action={<Link href="/setup"><span className="inline-block rounded-full bg-brand px-5 py-2 font-semibold text-white">Set up targets</span></Link>} />
      </Card>
    );
  }

  const goal = goalCalories(profile);
  const consumed = log.reduce((s, e) => s + e.calories, 0);
  const protein = log.reduce((s, e) => s + e.protein, 0);
  const carbs = log.reduce((s, e) => s + e.carbs, 0);
  const fat = log.reduce((s, e) => s + e.fat, 0);

  function add(entry: Omit<LogEntry, "id">) {
    setLog([...log, { ...entry, id: crypto.randomUUID() }]);
  }
  function remove(id: string) {
    setLog(log.filter((e) => e.id !== id));
  }

  return (
    <>
      <PageHeader eyebrow="Dashboard" title="Today" subtitle="Your calories and macros for the day." />

      <Card>
        <div className="flex flex-col items-center gap-6 sm:flex-row sm:items-center">
          <CalorieRing consumed={consumed} goal={goal} />
          <div className="flex-1 space-y-3 self-stretch">
            <div className="flex items-baseline gap-2">
              <span className="text-3xl font-bold tabular-nums">{consumed}</span>
              <span className="text-muted">/ {goal} kcal</span>
            </div>
            <MacroBar name="Protein" grams={protein} goal={profile.bmr.macros.protein} color="var(--protein)" />
            <MacroBar name="Carbs" grams={carbs} goal={profile.bmr.macros.carbs} color="var(--carbs)" />
            <MacroBar name="Fat" grams={fat} goal={profile.bmr.macros.fat} color="var(--fat)" />
          </div>
        </div>
      </Card>

      <Card className="mt-6" delay={70}>
        <h2 className="mb-3 text-lg font-semibold">Quick add</h2>
        <div className="flex flex-wrap gap-2">
          {PRESETS.map((p) => (
            <button key={p.name} onClick={() => add(p)}
              className="press rounded-full bg-surface-elevated px-3 py-1.5 text-sm ring-1 ring-black/10 hover:bg-brand/10 hover:text-brand dark:ring-white/10">
              + {p.name}
            </button>
          ))}
        </div>
      </Card>

      <Card className="mt-6" delay={140}>
        <div className="mb-3 flex items-center justify-between">
          <h2 className="text-lg font-semibold">Today&apos;s log</h2>
          <span className="text-sm font-semibold text-calorie">{Math.max(goal - consumed, 0)} kcal left</span>
        </div>
        {log.length === 0 ? (
          <p className="py-6 text-center text-sm text-muted">Nothing logged yet — add something above.</p>
        ) : (
          <ul className="divide-y divide-black/5 dark:divide-white/5">
            {log.map((e) => (
              <li key={e.id} className="flex items-center gap-3 py-3">
                <div className="flex-1">
                  <p className="text-sm font-medium">{e.name}</p>
                  <p className="text-xs text-muted tabular-nums">
                    P{e.protein} · C{e.carbs} · F{e.fat}
                  </p>
                </div>
                <span className="text-sm font-semibold tabular-nums">{e.calories} kcal</span>
                <button onClick={() => remove(e.id)} aria-label={`Remove ${e.name}`}
                  className="text-brand-danger/70 transition hover:text-brand-danger">✕</button>
              </li>
            ))}
          </ul>
        )}
      </Card>
    </>
  );
}
