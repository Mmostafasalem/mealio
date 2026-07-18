"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { api, type BMRRequest, type BMRResponse } from "@/lib/api";
import { useLocalStorage, STORAGE, type Profile, type Goal } from "@/lib/store";
import { Card, PageHeader, Button, Chip, MacroBar } from "@/components/ui";

const ACTIVITY = [
  { id: "sedentary", label: "Sedentary" },
  { id: "light", label: "Light" },
  { id: "moderate", label: "Moderate" },
  { id: "active", label: "Active" },
  { id: "veryActive", label: "Very active" },
];

const GOALS: { id: Goal; label: string }[] = [
  { id: "lose", label: "Lose weight" },
  { id: "maintain", label: "Maintain" },
  { id: "gain", label: "Gain muscle" },
];

export default function Setup() {
  const router = useRouter();
  const [, setProfile] = useLocalStorage<Profile | null>(STORAGE.profile, null);

  const [form, setForm] = useState<BMRRequest>({
    weight: 75, height: 178, age: 30, gender: "male", activityLevel: "moderate",
  });
  const [goal, setGoal] = useState<Goal>("maintain");
  const [result, setResult] = useState<BMRResponse | null>(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function calculate() {
    setLoading(true); setError(null);
    try {
      setResult(await api<BMRResponse>("bmr", form));
    } catch {
      setError("Couldn't reach the server. Please try again.");
    } finally {
      setLoading(false);
    }
  }

  function save() {
    if (!result) return;
    setProfile({ bmr: result, goal });
    router.push("/");
  }

  return (
    <>
      <PageHeader eyebrow="Setup" title="Your targets"
        subtitle="Set your body stats to get daily calorie & macro goals." />

      <Card>
        <div className="grid grid-cols-3 gap-3">
          <NumberField label="Weight (kg)" value={form.weight} onChange={(v) => setForm({ ...form, weight: v })} />
          <NumberField label="Height (cm)" value={form.height} onChange={(v) => setForm({ ...form, height: v })} />
          <NumberField label="Age" value={form.age} onChange={(v) => setForm({ ...form, age: v })} />
        </div>

        <Field label="Gender">
          {(["male", "female"] as const).map((g) => (
            <Chip key={g} active={form.gender === g} onClick={() => setForm({ ...form, gender: g })}>
              {g[0].toUpperCase() + g.slice(1)}
            </Chip>
          ))}
        </Field>

        <Field label="Activity level">
          {ACTIVITY.map((a) => (
            <Chip key={a.id} active={form.activityLevel === a.id} onClick={() => setForm({ ...form, activityLevel: a.id })}>
              {a.label}
            </Chip>
          ))}
        </Field>

        <Field label="Goal">
          {GOALS.map((g) => (
            <Chip key={g.id} active={goal === g.id} onClick={() => setGoal(g.id)}>{g.label}</Chip>
          ))}
        </Field>

        <div className="mt-6">
          <Button onClick={calculate} disabled={loading}>
            {loading ? "Calculating…" : "Calculate"}
          </Button>
        </div>
        {error && <p className="mt-3 text-center text-sm text-brand-danger">{error}</p>}
      </Card>

      {result && (
        <Card className="mt-6">
          <h2 className="mb-4 text-lg font-semibold">
            {goal === "lose" ? result.loseCalories : goal === "gain" ? result.gainCalories : result.maintainCalories}
            <span className="ml-1 text-sm font-normal text-muted">kcal / day</span>
          </h2>
          <div className="space-y-3">
            <MacroBar name="Protein" grams={result.macros.protein} color="var(--protein)" />
            <MacroBar name="Carbs" grams={result.macros.carbs} color="var(--carbs)" />
            <MacroBar name="Fat" grams={result.macros.fat} color="var(--fat)" />
          </div>
          <p className="mt-4 mb-4 text-xs text-muted">
            BMR {result.bmr} · TDEE {result.tdee} kcal. Estimates; individual needs vary.
          </p>
          <Button onClick={save}>Save &amp; start tracking</Button>
        </Card>
      )}
    </>
  );
}

function Field({ label, children }: { label: string; children: React.ReactNode }) {
  return (
    <div className="mt-4">
      <p className="mb-2 text-xs font-medium text-muted">{label}</p>
      <div className="flex flex-wrap gap-2">{children}</div>
    </div>
  );
}

function NumberField({ label, value, onChange }: {
  label: string; value: number; onChange: (v: number) => void;
}) {
  return (
    <label className="block">
      <span className="mb-1 block text-xs font-medium text-muted">{label}</span>
      <input type="number" value={value} onChange={(e) => onChange(Number(e.target.value))}
        className="w-full min-w-0 rounded-[var(--radius-chip)] bg-surface-elevated px-3 py-2 text-lg font-semibold outline-none ring-1 ring-black/10 focus:ring-2 focus:ring-brand dark:ring-white/10" />
    </label>
  );
}
