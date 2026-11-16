"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";

const LINKS = [
  { href: "/", label: "Home" },
  { href: "/plan", label: "Meal Plan", ai: true },
  { href: "/shop", label: "Shop" },
  { href: "/chat", label: "Assistant", ai: true },
  { href: "/setup", label: "Targets" },
];

// `aiEnabled` comes from the server-side NOURLO_WEB_AI_ENABLED flag (layout).
export function Nav({ aiEnabled }: { aiEnabled: boolean }) {
  const path = usePathname();
  const links = LINKS.filter((l) => aiEnabled || !l.ai);
  return (
    <div className="sticky top-4 z-20 px-4">
      <nav className="soft-shadow mx-auto flex w-max max-w-full items-center gap-1 overflow-x-auto rounded-full border border-black/5 bg-surface/70 px-2 py-1.5 backdrop-blur-xl dark:border-white/10">
        <Link href="/" className="px-3 text-base font-bold text-brand">Nourlo</Link>
        {links.map((l) => {
          const active = l.href === "/" ? path === "/" : path.startsWith(l.href);
          return (
            <Link key={l.href} href={l.href}
              className={`whitespace-nowrap rounded-full px-3 py-1.5 text-sm font-medium transition-colors ${
                active ? "bg-brand text-white" : "text-muted hover:text-foreground"
              }`}>
              {l.label}
            </Link>
          );
        })}
      </nav>
    </div>
  );
}
