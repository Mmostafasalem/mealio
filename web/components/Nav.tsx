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
    <nav className="sticky top-0 z-10 border-b border-black/5 bg-surface/80 backdrop-blur dark:border-white/5">
      <div className="mx-auto flex max-w-3xl items-center gap-1 px-4 py-3">
        <Link href="/" className="mr-2 text-xl font-bold text-brand">Mealio</Link>
        <div className="flex flex-1 items-center gap-1 overflow-x-auto">
          {LINKS.map((l) => {
            const active = l.href === "/" ? path === "/" : path.startsWith(l.href);
            return (
              <Link key={l.href} href={l.href}
                className={`whitespace-nowrap rounded-full px-3 py-1.5 text-sm font-medium transition ${
                  active ? "bg-brand/10 text-brand" : "text-muted hover:text-foreground"
                }`}>
                {l.label}
              </Link>
            );
          })}
        </div>
      </div>
    </nav>
  );
}
