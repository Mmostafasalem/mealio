"use client";

import { useState } from "react";
import { api } from "@/lib/api";
import { useLocalStorage, STORAGE, goalCalories, type Profile } from "@/lib/store";
import { Sparkle, PaperPlaneTilt } from "@phosphor-icons/react";
import { PageHeader, EmptyState } from "@/components/ui";

interface Msg { role: "user" | "assistant"; content: string }

export function ChatClient() {
  const [profile] = useLocalStorage<Profile | null>(STORAGE.profile, null);
  const [messages, setMessages] = useState<Msg[]>([]);
  const [input, setInput] = useState("");
  const [loading, setLoading] = useState(false);

  async function send() {
    const text = input.trim();
    if (!text || loading) return;
    const next = [...messages, { role: "user" as const, content: text }];
    setMessages(next);
    setInput("");
    setLoading(true);
    try {
      const res = await api<{ reply: string }>("agent-chat", {
        message: text,
        history: messages,
        userContext: {
          goal: profile?.goal ?? "maintain",
          targetCalories: profile ? goalCalories(profile) : 2000,
          caloriesConsumed: 0,
          favoriteFoods: [],
        },
      });
      setMessages([...next, { role: "assistant", content: res.reply }]);
    } catch {
      setMessages([...next, { role: "assistant", content: "Sorry, I couldn't reach the assistant. Please try again." }]);
    } finally {
      setLoading(false);
    }
  }

  return (
    <>
      <PageHeader eyebrow="AI" title="Assistant" subtitle="Ask about meals, groceries, or your nutrition goals." />

      <div className="flex min-h-[60vh] flex-col rounded-[var(--radius-card)] bg-surface p-4 shadow-sm">
        <div className="flex-1 space-y-3 overflow-y-auto">
          {messages.length === 0 && !loading && (
            <EmptyState icon={Sparkle} title="Ask me anything"
              message="e.g. “A high-protein breakfast under 400 kcal” or “What should I buy this week?”" />
          )}
          {messages.map((m, i) => (
            <div key={i} className={`flex ${m.role === "user" ? "justify-end" : "justify-start"}`}>
              <div className={`max-w-[80%] rounded-2xl px-4 py-2 text-sm ${
                m.role === "user" ? "bg-brand text-white" : "bg-surface-elevated"
              }`}>
                {m.content}
              </div>
            </div>
          ))}
          {loading && (
            <div className="flex justify-start">
              <div className="rounded-2xl bg-surface-elevated px-4 py-3">
                <span className="inline-flex gap-1">
                  <Dot /> <Dot delay="0.15s" /> <Dot delay="0.3s" />
                </span>
              </div>
            </div>
          )}
        </div>

        <div className="mt-3 flex gap-2">
          <input value={input} onChange={(e) => setInput(e.target.value)}
            onKeyDown={(e) => e.key === "Enter" && send()}
            placeholder="Ask about meals, groceries, nutrition…"
            className="flex-1 rounded-full bg-surface-elevated px-4 py-3 outline-none ring-1 ring-black/10 focus:ring-2 focus:ring-brand dark:ring-white/10" />
          <button onClick={send} disabled={!input.trim() || loading} aria-label="Send message"
            className="press flex h-12 w-12 shrink-0 items-center justify-center rounded-full bg-brand text-white disabled:opacity-40">
            <PaperPlaneTilt size={20} weight="fill" /></button>
        </div>
      </div>
    </>
  );
}

function Dot({ delay = "0s" }: { delay?: string }) {
  return (
    <span className="inline-block h-2 w-2 animate-bounce rounded-full bg-muted"
      style={{ animationDelay: delay }} />
  );
}
