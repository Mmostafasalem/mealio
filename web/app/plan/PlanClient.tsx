"use client";

import { useState } from "react";
import Link from "next/link";
import { api } from "@/lib/api";
import { useLocalStorage, STORAGE, type Profile } from "@/lib/store";
import { ForkKnife, Sparkle } from "@phosphor-icons/react";
import { Card, PageHeader, Button, EmptyState, Spinner } from "@/components/ui";

interface Meal { pavadinimas?: string; kcal?: number; ingredientai?: string[] }
type Day = Record<string, Meal | number | undefined>;
type Weekly = Record<string, Day | string | undefined> & { agentMessage?: string };

const DAYS: [string, string][] = [
  ["pirmadienis", "Monday"], ["antradienis", "Tuesday"], ["treciadienis", "Wednesday"],
  ["ketvirtadienis", "Thursday"], ["pentadienis", "Friday"], ["sestadienis", "Saturday"],
  ["sekmadienis", "Sunday"],
];
const MEALS: [string, string][] = [
  ["pusryciai", "Breakfast"], ["pietūs", "Lunch"], ["vakariene", "Dinner"], ["uzkandziai", "Snack"],
];

export function PlanClient() {
  const [profile, , loaded] = useLocalStorage<Profile | null>(STORAGE.profile, null);
  const [plan, setPlan] = useState<Weekly | null>(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function generate() {
    if (!profile) return;
    setLoading(true); setError(null);
    try {
      setPlan(await api<Weekly>("meal-plan", {
        user: { favoriteFoods: [], dietaryOptions: [] },
        bmrData: profile.bmr,
        goal: profile.goal,
        lang: "en",
      }));
    } catch {
      setError("Couldn't generate a plan. Please try again.");
    } finally {
      setLoading(false);
    }
  }

  if (!loaded) return null;
  if (!profile) {
    return (
      <Card>
        <EmptyState icon={ForkKnife} title="Set your targets first"
          message="Your meal plan is built around your calorie goal."
          action={<Link href="/setup"><span className="inline-block rounded-full bg-brand px-5 py-2 font-semibold text-white">Set up targets</span></Link>} />
      </Card>
    );
  }

  return (
    <>
      <PageHeader eyebrow="This week" title="Meal Plan" subtitle="A 7-day plan built around your goal." />

      {plan?.agentMessage && (
        <Card className="mb-6 bg-brand/10">
          <p className="text-sm">{plan.agentMessage}</p>
        </Card>
      )}

      {!plan && !loading && (
        <Card>
          <EmptyState icon={Sparkle} title="No plan yet"
            message="Generate a fresh 7-day plan tailored to your daily targets."
            action={<Button onClick={generate}>Generate plan</Button>} />
        </Card>
      )}

      {loading && (
        <Card><Spinner /><p className="text-center text-sm text-muted">The assistant is planning your week…</p></Card>
      )}
      {error && <p className="text-center text-sm text-brand-danger">{error}</p>}

      {plan && !loading && (
        <>
          <div className="space-y-4">
            {DAYS.map(([key, label], i) => {
              const day = plan[key] as Day | undefined;
              if (!day) return null;
              const total = day.visoKcal as number | undefined;
              return (
                <Card key={key} delay={Math.min(i * 50, 300)}>
                  <div className="mb-2 flex items-center justify-between">
                    <h3 className="font-semibold">{label}</h3>
                    {typeof total === "number" && (
                      <span className="text-sm text-muted tabular-nums">{total} kcal</span>
                    )}
                  </div>
                  <ul className="divide-y divide-black/5 dark:divide-white/5">
                    {MEALS.map(([mkey, mlabel]) => {
                      const meal = day[mkey] as Meal | undefined;
                      if (!meal?.pavadinimas) return null;
                      return (
                        <li key={mkey} className="flex items-center gap-3 py-2">
                          <span className="w-20 shrink-0 text-xs font-medium text-muted">{mlabel}</span>
                          <span className="flex-1 text-sm">{meal.pavadinimas}</span>
                          {typeof meal.kcal === "number" && (
                            <span className="text-xs text-muted tabular-nums">{meal.kcal} kcal</span>
                          )}
                        </li>
                      );
                    })}
                  </ul>
                </Card>
              );
            })}
          </div>
          <div className="mt-6">
            <Button variant="secondary" onClick={generate}>Regenerate plan</Button>
          </div>
        </>
      )}
    </>
  );
}
