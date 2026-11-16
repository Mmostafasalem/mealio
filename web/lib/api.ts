// Thin client for the server-side proxy (/api/backend/*). The browser never
// sees the backend URL or the API key — both live in the proxy.

export async function api<T>(path: string, body?: unknown): Promise<T> {
  const res = await fetch(`/api/backend/${path}`, {
    method: body === undefined ? "GET" : "POST",
    headers: { "Content-Type": "application/json" },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  if (!res.ok) throw new Error(`Request to ${path} failed (${res.status})`);
  return res.json() as Promise<T>;
}

// ---- Backend response shapes (mirror smartmarket-backend/app.py) ----

export interface BMRResponse {
  bmr: number;
  tdee: number;
  loseCalories: number;
  maintainCalories: number;
  gainCalories: number;
  macros: { protein: number; carbs: number; fat: number };
}

export interface BMRRequest {
  weight: number;
  height: number;
  age: number;
  gender: "male" | "female";
  activityLevel: string;
}
