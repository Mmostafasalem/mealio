import { NextRequest } from "next/server";
import { isWebAiEnabled } from "@/lib/flags";

// Server-side proxy to the Flask backend. The browser calls /api/backend/<x>;
// this forwards to <BACKEND_URL>/api/<x> and attaches the shared secret from a
// SERVER-only env var. The key is never sent to the browser — solving the
// "you can't hide a key in client JS" problem.
//
// Because every forwarded request carries the server's X-API-Key, this is NOT
// a generic proxy: only the exact endpoints the website uses are allowed
// (ROUTES below). Everything else gets a 404 and never reaches the backend.

// The AI endpoints (meal-plan, chat) can take ~25s on Groq, and the Render free
// tier adds a cold-start delay on top. Allow the serverless function to run long
// enough to cover that instead of being killed at the platform default (~10s).
export const maxDuration = 60;

// Abort the upstream call a hair under maxDuration so we return a clean 504
// ourselves rather than being hard-killed mid-request.
const UPSTREAM_TIMEOUT_MS = 55_000;

const MAX_BODY_BYTES = 64 * 1024;

type Method = "GET" | "POST";

interface Route {
  method: Method;
  /** Query params forwarded to the backend (GET only). Others are dropped. */
  query?: readonly string[];
  /** AI-backed endpoint: disabled unless NOURLO_WEB_AI_ENABLED is on. */
  ai?: boolean;
}

// Exact allowlist: the only backend endpoints the website calls
// (app/shop, app/setup, app/plan, app/chat via lib/api.ts).
const ROUTES: Record<string, Route> = {
  products: { method: "GET", query: ["store", "category", "q"] },
  bmr: { method: "POST" },
  "meal-plan": { method: "POST", ai: true },
  "agent-chat": { method: "POST", ai: true },
};

const MAX_QUERY_VALUE_LENGTH = 100;

// ---- Rate limiting ---------------------------------------------------------
// Best-effort, in-memory, per-IP fixed window. NOTE: serverless instances do
// not share memory, so each warm instance keeps its own counters and a cold
// start resets them — this only blunts casual abuse. For real production
// limits use a shared store (e.g. Upstash Redis + @upstash/ratelimit).
const RATE_LIMIT = 30;
const RATE_WINDOW_MS = 60_000;
const MAX_TRACKED_IPS = 10_000;
const hits = new Map<string, { count: number; resetAt: number }>();

function clientIp(req: NextRequest): string {
  const fwd = req.headers.get("x-forwarded-for");
  if (fwd) {
    const first = fwd.split(",")[0]?.trim();
    if (first) return first;
  }
  return req.headers.get("x-real-ip")?.trim() || "unknown";
}

function rateLimited(ip: string): { limited: boolean; retryAfter: number } {
  const now = Date.now();
  if (hits.size > MAX_TRACKED_IPS) {
    for (const [key, entry] of hits) if (entry.resetAt <= now) hits.delete(key);
    if (hits.size > MAX_TRACKED_IPS) hits.clear();
  }
  const entry = hits.get(ip);
  if (!entry || entry.resetAt <= now) {
    hits.set(ip, { count: 1, resetAt: now + RATE_WINDOW_MS });
    return { limited: false, retryAfter: 0 };
  }
  entry.count += 1;
  return {
    limited: entry.count > RATE_LIMIT,
    retryAfter: Math.ceil((entry.resetAt - now) / 1000),
  };
}

// ---- Helpers ---------------------------------------------------------------

function error(message: string, status: number, headers?: Record<string, string>) {
  return Response.json({ error: message }, { status, headers });
}

function validSegment(s: string): boolean {
  return s !== "" && s !== "." && s !== ".." && !s.includes("/") && !s.includes("\\");
}

/** Backend base URL, or null if unset / not https (fail closed). */
function backendUrl(): string | null {
  const raw = process.env.BACKEND_URL?.trim();
  if (!raw) return null;
  try {
    const url = new URL(raw);
    if (url.protocol !== "https:") return null;
    return url.origin + url.pathname.replace(/\/+$/, "");
  } catch {
    return null;
  }
}

async function readBody(req: NextRequest): Promise<string | null> {
  const declared = Number(req.headers.get("content-length") ?? "");
  if (Number.isFinite(declared) && declared > MAX_BODY_BYTES) return null;
  if (!req.body) return "";
  const reader = req.body.getReader();
  const chunks: Uint8Array[] = [];
  let size = 0;
  for (;;) {
    const { done, value } = await reader.read();
    if (done) break;
    size += value.byteLength;
    if (size > MAX_BODY_BYTES) {
      await reader.cancel();
      return null;
    }
    chunks.push(value);
  }
  const all = new Uint8Array(size);
  let offset = 0;
  for (const c of chunks) {
    all.set(c, offset);
    offset += c.byteLength;
  }
  return new TextDecoder().decode(all);
}

// ---- Proxy -----------------------------------------------------------------

async function forward(req: NextRequest, path: string[], method: Method) {
  // 1. Path must be a single, clean, allowlisted segment with the right method.
  if (!Array.isArray(path) || path.length !== 1 || !path.every(validSegment)) {
    return error("Not found", 404);
  }
  const name = path[0];
  const route = Object.hasOwn(ROUTES, name) ? ROUTES[name] : undefined;
  if (!route || route.method !== method) return error("Not found", 404);

  // 2. Rate limit (best-effort, see note above).
  const { limited, retryAfter } = rateLimited(clientIp(req));
  if (limited) {
    return error("Too many requests", 429, { "Retry-After": String(retryAfter) });
  }

  // 3. AI endpoints are off unless explicitly enabled.
  if (route.ai && !isWebAiEnabled()) {
    return error("This feature is not available online yet", 503);
  }

  // 4. Fail closed if the backend isn't configured with an https URL.
  const base = backendUrl();
  if (!base) return error("Backend not configured", 503);

  // 5. Build the upstream request.
  const upstream = new URL(`${base}/api/${encodeURIComponent(name)}`);
  const headers: Record<string, string> = { Accept: "application/json" };
  const apiKey = process.env.APP_API_KEY;
  if (apiKey) headers["X-API-Key"] = apiKey;
  const init: RequestInit = { method, headers, cache: "no-store" };

  if (method === "GET") {
    for (const key of route.query ?? []) {
      const value = req.nextUrl.searchParams.get(key);
      if (value !== null && value.length <= MAX_QUERY_VALUE_LENGTH) {
        upstream.searchParams.set(key, value);
      }
    }
  } else {
    const contentType = req.headers.get("content-type") ?? "";
    if (contentType.split(";")[0].trim().toLowerCase() !== "application/json") {
      return error("Content-Type must be application/json", 415);
    }
    const body = await readBody(req);
    if (body === null) return error("Request body too large", 413);
    headers["Content-Type"] = "application/json";
    init.body = body;
  }

  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), UPSTREAM_TIMEOUT_MS);
  init.signal = controller.signal;

  try {
    const res = await fetch(upstream, init);
    // Never pass upstream 5xx bodies through: they may contain stack traces
    // or internal details. 4xx bodies (validation errors) are passed through.
    if (res.status >= 500) {
      await res.body?.cancel();
      return error("Backend error", res.status);
    }
    const body = await res.text();
    return new Response(body, {
      status: res.status,
      headers: {
        "Content-Type": res.headers.get("Content-Type") ?? "application/json",
        "Cache-Control": "no-store",
      },
    });
  } catch (err) {
    const timedOut = err instanceof Error && err.name === "AbortError";
    return error(timedOut ? "Backend timed out" : "Backend unreachable", timedOut ? 504 : 502);
  } finally {
    clearTimeout(timer);
  }
}

export async function GET(
  req: NextRequest,
  { params }: { params: Promise<{ path: string[] }> },
) {
  const { path } = await params;
  return forward(req, path, "GET");
}

export async function POST(
  req: NextRequest,
  { params }: { params: Promise<{ path: string[] }> },
) {
  const { path } = await params;
  return forward(req, path, "POST");
}
