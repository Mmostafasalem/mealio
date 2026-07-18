import { NextRequest } from "next/server";

// Server-side proxy to the Flask backend. The browser calls /api/backend/<x>;
// this forwards to <BACKEND_URL>/api/<x> and attaches the shared secret from a
// SERVER-only env var. The key is never sent to the browser — solving the
// "you can't hide a key in client JS" problem.

const BACKEND_URL =
  process.env.BACKEND_URL ?? "https://mealio-backend-17qg.onrender.com";
const API_KEY = process.env.APP_API_KEY ?? "";

async function forward(req: NextRequest, path: string[]) {
  const target = `${BACKEND_URL}/api/${path.join("/")}${req.nextUrl.search}`;

  const headers: Record<string, string> = { "Content-Type": "application/json" };
  if (API_KEY) headers["X-API-Key"] = API_KEY;

  const init: RequestInit = { method: req.method, headers };
  if (req.method !== "GET" && req.method !== "HEAD") {
    init.body = await req.text();
  }

  try {
    const res = await fetch(target, init);
    const body = await res.text();
    return new Response(body, {
      status: res.status,
      headers: {
        "Content-Type": res.headers.get("Content-Type") ?? "application/json",
      },
    });
  } catch {
    return Response.json(
      { error: "Backend unreachable" },
      { status: 502 },
    );
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
