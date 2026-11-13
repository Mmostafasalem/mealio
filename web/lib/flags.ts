// Server-only feature flags. Read from env on the server; never import this
// from a "use client" module.

/**
 * AI features on the website (Assistant chat, Meal Plan generation).
 * Off by default: the backend AI is disabled and the web flow has no consent
 * or sign-in yet. Set NOURLO_WEB_AI_ENABLED=true to turn them on. Pages read
 * this at build/render time, so toggling it needs a redeploy.
 */
export function isWebAiEnabled(): boolean {
  return process.env.NOURLO_WEB_AI_ENABLED?.trim().toLowerCase() === "true";
}
