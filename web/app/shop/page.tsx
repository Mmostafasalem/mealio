"use client";

import { useEffect, useState } from "react";
import { api } from "@/lib/api";
import { useLocalStorage, STORAGE, type CartLine } from "@/lib/store";
import { Card, PageHeader, Spinner, EmptyState } from "@/components/ui";

interface Product {
  id: number; name: string; brand: string; emoji: string; store: string;
  discountedPrice: number; category: string; unit: string; weeklyQty: number;
}

export default function ShopPage() {
  const [products, setProducts] = useState<Product[] | null>(null);
  const [error, setError] = useState(false);
  const [query, setQuery] = useState("");
  const [cart, setCart] = useLocalStorage<CartLine[]>(STORAGE.cart, []);
  const [budget] = useLocalStorage<number>(STORAGE.budget, 60);

  useEffect(() => {
    api<Product[]>("products").then(setProducts).catch(() => setError(true));
  }, []);

  const total = cart.reduce((s, l) => s + l.price * l.qty, 0);
  const remaining = Math.max(budget - total, 0);
  const pct = Math.min((total / budget) * 100, 100);

  function add(p: Product) {
    const existing = cart.find((l) => l.id === String(p.id) && l.store === p.store);
    if (existing) {
      setCart(cart.map((l) => l === existing ? { ...l, qty: l.qty + 1 } : l));
    } else {
      setCart([...cart, { id: String(p.id), name: p.name, store: p.store, price: p.discountedPrice, qty: 1 }]);
    }
  }
  function removeLine(id: string, store: string) {
    setCart(cart.filter((l) => !(l.id === id && l.store === store)));
  }

  const filtered = (products ?? []).filter((p) =>
    !query || p.name.toLowerCase().includes(query.toLowerCase()) || p.store.toLowerCase().includes(query.toLowerCase()),
  );

  return (
    <>
      <PageHeader title="Shop" subtitle="Grocery prices to plan and budget your shop." />

      {/* Budget */}
      <Card className="mb-6">
        <div className="mb-2 flex items-baseline justify-between">
          <div>
            <p className="text-xs text-muted">Weekly budget</p>
            <p className="text-2xl font-bold tabular-nums" style={{ color: total > budget ? "var(--brand-danger)" : "var(--brand)" }}>
              €{total.toFixed(2)} <span className="text-sm font-normal text-muted">/ €{budget}</span>
            </p>
          </div>
          <p className="text-sm text-muted">€{remaining.toFixed(2)} left</p>
        </div>
        <div className="h-2 overflow-hidden rounded-full bg-black/10 dark:bg-white/10">
          <div className="h-full rounded-full transition-[width] duration-500"
            style={{ width: `${pct}%`, background: total > budget ? "var(--brand-danger)" : "var(--brand)" }} />
        </div>
        {cart.length > 0 && (
          <ul className="mt-4 divide-y divide-black/5 dark:divide-white/5">
            {cart.map((l) => (
              <li key={`${l.id}-${l.store}`} className="flex items-center gap-2 py-2 text-sm">
                <span className="flex-1">{l.name} <span className="text-muted">×{l.qty}</span></span>
                <span className="tabular-nums">€{(l.price * l.qty).toFixed(2)}</span>
                <button onClick={() => removeLine(l.id, l.store)} aria-label={`Remove ${l.name}`}
                  className="text-brand-danger/70 hover:text-brand-danger">✕</button>
              </li>
            ))}
          </ul>
        )}
      </Card>

      {/* Product list */}
      <input value={query} onChange={(e) => setQuery(e.target.value)} placeholder="Search groceries…"
        className="mb-4 w-full rounded-[var(--radius-chip)] bg-surface px-4 py-3 outline-none ring-1 ring-black/10 focus:ring-2 focus:ring-brand dark:ring-white/10" />

      {error && <p className="text-center text-sm text-brand-danger">Couldn&apos;t load products.</p>}
      {!products && !error && <Spinner />}
      {products && filtered.length === 0 && (
        <EmptyState icon="🔍" title="No matches" message="Try a different search." />
      )}

      <div className="grid gap-3 sm:grid-cols-2">
        {filtered.map((p, i) => (
          <Card key={`${p.store}-${p.id}`} className="!p-4" delay={Math.min(i * 25, 320)}>
            <div className="flex items-center gap-3">
              <span className="text-2xl">{p.emoji}</span>
              <div className="flex-1">
                <p className="text-sm font-semibold leading-tight">{p.name}</p>
                <p className="text-xs text-muted">{p.store} · {p.weeklyQty}{p.unit}</p>
              </div>
              <div className="text-right">
                <p className="font-bold text-brand tabular-nums">€{p.discountedPrice.toFixed(2)}</p>
                <p className="text-[10px] text-muted">est. price</p>
              </div>
              <button onClick={() => add(p)} aria-label={`Add ${p.name}`}
                className="ml-1 h-9 w-9 rounded-full bg-brand text-lg font-bold text-white transition active:scale-95">+</button>
            </div>
          </Card>
        ))}
      </div>
    </>
  );
}
