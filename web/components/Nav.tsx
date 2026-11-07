"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";

const LINKS = [
  { href: "/", label: "Home" },
  { href: "/plan", label: "Meal Plan" },
  { href: "/shop", label: "Shop" },
  { href: "/chat", label: "Assistant" },
  { href: "/setup", label: "Targets" },
];

export function Nav() {
  const path = usePathname();
  return (
    <div className="sticky top-4 z-20 px-4">
      <nav className="soft-shadow mx-auto flex w-max max-w-full items-center gap-1 overflow-x-auto rounded-full border border-black/5 bg-surface/70 px-2 py-1.5 backdrop-blur-xl dark:border-white/10">
        <Link href="/" className="px-3 text-base font-bold text-brand">Nourlo</Link>
        {LINKS.map((l) => {
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
