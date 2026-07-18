"use client";

import { useState } from "react";
import { api, type BMRRequest, type BMRResponse } from "@/lib/api";

const ACTIVITY = [
  { id: "sedentary", label: "Sedentary" },
  { id: "light", label: "Light" },
  { id: "moderate", label: "Moderate" },
  { id: "active", label: "Active" },
  { id: "veryActive", label: "Very active" },
];

export default function Home() {
  const [form, setForm] = useState<BMRRequest>({
    weight: 75,
    height: 178,
    age: 30,
    gender: "male",
    activityLevel: "moderate",
  });
  const [result, setResult] = useState<BMRResponse | null>(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function calculate() {
    setLoading(true);
    setError(null);
    try {
      setResult(await api<BMRResponse>("bmr", form));
    } catch {
      setError("Couldn't reach the server. Please try again.");
    } finally {
      setLoading(false);
    }
  }

  return (
    <main className="mx-auto min-h-screen max-w-2xl px-5 py-10">
      <header className="mb-8 text-center">
        <h1 className="text-4xl font-bold tracking-tight text-brand">Mealio</h1>
        <p className="mt-1 text-muted">Eat well. Spend less.</p>
      </header>

      {/* Body stats */}
      <section className="rounded-[var(--radius-card)] bg-surface p-6 shadow-sm">
        <h2 className="mb-1 text-lg font-semibold">Your body stats</h2>
        <p className="mb-5 text-sm text-muted">
          Get your daily calorie &amp; macro targets in one tap.
        </p>

        <div className="grid grid-cols-3 gap-3">
          <NumberField label="Weight (kg)" value={form.weight}
            onChange={(v) => setForm({ ...form, weight: v })} />
          <NumberField label="Height (cm)" value={form.height}
            onChange={(v) => setForm({ ...form, height: v })} />
          <NumberField label="Age" value={form.age}
            onChange={(v) => setForm({ ...form, age: v })} />
        </div>

        <div className="mt-4">
          <p className="mb-2 text-xs font-medium text-muted">Gender</p>
          <div className="flex gap-2">
            {(["male", "female"] as const).map((g) => (
              <Chip key={g} active={form.gender === g}
                onClick={() => setForm({ ...form, gender: g })}>
                {g[0].toUpperCase() + g.slice(1)}
              </Chip>
            ))}
          </div>
        </div>

        <div className="mt-4">
          <p className="mb-2 text-xs font-medium text-muted">Activity level</p>
          <div className="flex flex-wrap gap-2">
            {ACTIVITY.map((a) => (
              <Chip key={a.id} active={form.activityLevel === a.id}
                onClick={() => setForm({ ...form, activityLevel: a.id })}>
                {a.label}
              </Chip>
            ))}
          </div>
        </div>

        <button onClick={calculate} disabled={loading}
          className="mt-6 h-12 w-full rounded-[var(--radius-tile)] bg-brand font-semibold text-white transition active:scale-[0.99] disabled:opacity-50">
          {loading ? "Calculating…" : "Calculate my targets"}
        </button>
        {error && <p className="mt-3 text-center text-sm text-brand-danger">{error}</p>}
      </section>

      {/* Results */}
      {result && (
        <section className="mt-6 rounded-[var(--radius-card)] bg-surface p-6 shadow-sm">
          <h2 className="mb-4 text-lg font-semibold">Your daily targets</h2>

          <div className="grid grid-cols-3 gap-3">
            <GoalCard label="Lose" kcal={result.loseCalories} />
            <GoalCard label="Maintain" kcal={result.maintainCalories} highlight />
            <GoalCard label="Gain" kcal={result.gainCalories} />
          </div>

          <p className="mt-6 mb-3 text-sm font-medium text-muted">
            Macros at maintenance
          </p>
          <div className="space-y-3">
            <MacroBar name="Protein" grams={result.macros.protein} color="var(--protein)" />
            <MacroBar name="Carbs" grams={result.macros.carbs} color="var(--carbs)" />
            <MacroBar name="Fat" grams={result.macros.fat} color="var(--fat)" />
          </div>

          <p className="mt-5 text-xs text-muted">
            BMR {result.bmr} kcal · TDEE {result.tdee} kcal. Estimates; individual
            needs vary.
          </p>
        </section>
      )}
    </main>
  );
}

function NumberField({ label, value, onChange }: {
  label: string; value: number; onChange: (v: number) => void;
}) {
  return (
    <label className="block">
      <span className="mb-1 block text-xs font-medium text-muted">{label}</span>
      <input type="number" value={value}
        onChange={(e) => onChange(Number(e.target.value))}
        className="w-full rounded-[var(--radius-chip)] bg-surface-elevated px-3 py-2 text-lg font-semibold outline-none ring-1 ring-black/10 focus:ring-2 focus:ring-brand" />
    </label>
  );
}

function Chip({ active, onClick, children }: {
  active: boolean; onClick: () => void; children: React.ReactNode;
}) {
  return (
    <button onClick={onClick}
      className={`rounded-full px-4 py-2 text-sm font-medium transition ${
        active ? "bg-brand text-white" : "bg-surface-elevated text-muted ring-1 ring-black/10"
      }`}>
      {children}
    </button>
  );
}

function GoalCard({ label, kcal, highlight }: {
  label: string; kcal: number; highlight?: boolean;
}) {
  return (
    <div className={`rounded-[var(--radius-tile)] p-4 text-center ${
      highlight ? "bg-brand text-white" : "bg-surface-elevated"
    }`}>
      <div className="text-2xl font-bold tabular-nums">{kcal}</div>
      <div className={`text-xs ${highlight ? "text-white/80" : "text-muted"}`}>{label} · kcal</div>
    </div>
  );
}

function MacroBar({ name, grams, color }: { name: string; grams: number; color: string }) {
  const pct = Math.min((grams / 250) * 100, 100);
  return (
    <div>
      <div className="mb-1 flex justify-between text-sm">
        <span className="font-medium">{name}</span>
        <span className="tabular-nums text-muted">{grams} g</span>
      </div>
      <div className="h-2 overflow-hidden rounded-full bg-black/10">
        <div className="h-full rounded-full" style={{ width: `${pct}%`, background: color }} />
      </div>
    </div>
  );
}
