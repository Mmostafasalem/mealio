"use client";

import { useCallback, useMemo, useState, useSyncExternalStore, type SetStateAction } from "react";
import type { BMRResponse } from "@/lib/api";

// Client-side persistence (localStorage) — the web analogue of the iOS app's
// UserDefaults. No backend account yet; everything personal lives in the browser.

const STORAGE_CHANGE = "mealio:storage-change";
// Keep updates usable in this tab if browser privacy settings or a full quota
// prevent persistence. Successful writes resume normal localStorage access.
const pendingWrites = new Map<string, string>();

function readStorage(key: string): string | null {
  if (pendingWrites.has(key)) return pendingWrites.get(key)!;
  try {
    return window.localStorage.getItem(key);
  } catch {
    return null;
  }
}

function parseStorage<T>(raw: string | null | undefined, initial: T): T {
  try {
    return raw == null ? initial : JSON.parse(raw) as T;
  } catch {
    return initial;
  }
}

// The server and the client's first hydration render share this snapshot.
const serverSnapshot = () => undefined;

export function useLocalStorage<T>(key: string, initial: T) {
  const [fallback] = useState<T>(initial);
  const subscribe = useCallback((notify: () => void) => {
    function onStorage(event: StorageEvent) {
      if (event.storageArea === window.localStorage
        && (event.key === key || event.key === null)) {
        pendingWrites.delete(key);
        notify();
      }
    }
    window.addEventListener("storage", onStorage);
    window.addEventListener(STORAGE_CHANGE, notify);
    return () => {
      window.removeEventListener("storage", onStorage);
      window.removeEventListener(STORAGE_CHANGE, notify);
    };
  }, [key]);
  const getSnapshot = useCallback(() => readStorage(key), [key]);
  // A raw string is a stable snapshot even when the stored JSON is an object.
  const raw = useSyncExternalStore(subscribe, getSnapshot, serverSnapshot);
  const value = useMemo(() => parseStorage(raw, fallback), [raw, fallback]);

  const setValue = useCallback((update: SetStateAction<T>) => {
    const previous = parseStorage(readStorage(key), fallback);
    const next = typeof update === "function"
      ? (update as (previous: T) => T)(previous)
      : update;
    const serialized = JSON.stringify(next);
    try {
      window.localStorage.setItem(key, serialized);
      pendingWrites.delete(key);
    } catch {
      pendingWrites.set(key, serialized);
    }
    // Native storage events only reach other tabs. Notify same-tab hooks too.
    window.dispatchEvent(new Event(STORAGE_CHANGE));
  }, [key, fallback]);

  return [value, setValue, raw !== undefined] as const;
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
