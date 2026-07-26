import { NextRequest } from "next/server";

// Server-side proxy to the Flask backend. The browser calls /api/backend/<x>;
// this forwards to <BACKEND_URL>/api/<x> and attaches the shared secret from a
// SERVER-only env var. The key is never sent to the browser — solving the
// "you can't hide a key in client JS" problem.

const BACKEND_URL =
  process.env.BACKEND_URL ?? "https://mealio-backend-17qg.onrender.com";
const API_KEY = process.env.APP_API_KEY ?? "";

// The AI endpoints (meal-plan, chat) can take ~25s on Groq, and the Render free
// tier adds a cold-start delay on top. Allow the serverless function to run long
// enough to cover that instead of being killed at the platform default (~10s).
export const maxDuration = 60;

// Abort the upstream call a hair under maxDuration so we return a clean 504
// ourselves rather than being hard-killed mid-request.
const UPSTREAM_TIMEOUT_MS = 55_000;

async function forward(req: NextRequest, path: string[]) {
  const target = `${BACKEND_URL}/api/${path.join("/")}${req.nextUrl.search}`;

  const headers: Record<string, string> = { "Content-Type": "application/json" };
  if (API_KEY) headers["X-API-Key"] = API_KEY;

  const init: RequestInit = { method: req.method, headers };
  if (req.method !== "GET" && req.method !== "HEAD") {
    init.body = await req.text();
  }

  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), UPSTREAM_TIMEOUT_MS);
  init.signal = controller.signal;

  try {
    const res = await fetch(target, init);
    const body = await res.text();
    return new Response(body, {
      status: res.status,
      headers: {
        "Content-Type": res.headers.get("Content-Type") ?? "application/json",
      },
    });
  } catch (err) {
    const timedOut = err instanceof Error && err.name === "AbortError";
    return Response.json(
      { error: timedOut ? "Backend timed out" : "Backend unreachable" },
      { status: timedOut ? 504 : 502 },
    );
  } finally {
    clearTimeout(timer);
  }
}

export async function GET(
  req: NextRequest,
  { params }: { params: Promise<{ path: string[] }> },
) {
  const { path } = await params;
  return forward(req, path);
}

export async function POST(
  req: NextRequest,
  { params }: { params: Promise<{ path: string[] }> },
) {
  const { path } = await params;
  return forward(req, path);
}
