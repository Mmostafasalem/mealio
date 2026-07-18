"use client";

import { useEffect, useState } from "react";
import type { BMRResponse } from "@/lib/api";

// Client-side persistence (localStorage) — the web analogue of the iOS app's
// UserDefaults. No backend account yet; everything personal lives in the browser.

export function useLocalStorage<T>(key: string, initial: T) {
  const [value, setValue] = useState<T>(initial);
  const [loaded, setLoaded] = useState(false);

  useEffect(() => {
    try {
      const raw = localStorage.getItem(key);
      if (raw) setValue(JSON.parse(raw) as T);
    } catch {
      /* ignore */
    }
    setLoaded(true);
  }, [key]);

  useEffect(() => {
    if (loaded) localStorage.setItem(key, JSON.stringify(value));
  }, [key, value, loaded]);

  return [value, setValue, loaded] as const;
}

export type Goal = "lose" | "maintain" | "gain";

export interface Profile {
  bmr: BMRResponse;
  goal: Goal;
}

export interface LogEntry {
  id: string;
  name: string;
  calories: number;
  protein: number;
  carbs: number;
  fat: number;
}

export interface CartLine {
  id: string;
  name: string;
  store: string;
  price: number;
  qty: number;
}

export const STORAGE = {
  profile: "mealio.profile",
  log: "mealio.log.today",
  cart: "mealio.cart",
  budget: "mealio.budget",
} as const;

/** The calorie target for the chosen goal. */
export function goalCalories(p: Profile): number {
  return p.goal === "lose"
    ? p.bmr.loseCalories
    : p.goal === "gain"
      ? p.bmr.gainCalories
      : p.bmr.maintainCalories;
}
