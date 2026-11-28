import Image from "next/image";

// The landing page: what Nourlo is, the mascot, and where to get it.
// The App Store link is set once the app is live (APP_STORE_URL below).
const APP_STORE_URL: string | null = null;

const FEATURES: { emoji: string; title: string; text: string }[] = [
  { emoji: "🥣", title: "Meal plans on a budget", text: "A week of meals built around what you like and what you can spend." },
  { emoji: "🎙️", title: "Log food by voice", text: "Say “two eggs and a banana” and it's logged. Or scan the barcode." },
  { emoji: "🎯", title: "Calories and macros", text: "Rings for calories, protein, carbs and fat that fill as you go." },
  { emoji: "🧺", title: "Cook what you have", text: "Keep track of what's at home and get dinners that use it up." },
  { emoji: "🏃", title: "Workouts made for you", text: "Pick where and how long; Nourlo builds the session and times it." },
  { emoji: "🔒", title: "Private by design", text: "Your log and stock stay on your iPhone unless you turn on online AI. Health data never leaves it." },
];

function StoreButton() {
  const label = (
    <>
      <svg width="22" height="22" viewBox="0 0 24 24" fill="currentColor" aria-hidden="true">
        <path d="M16.37 12.6c-.02-2.2 1.8-3.26 1.88-3.31-1.03-1.5-2.62-1.7-3.18-1.73-1.35-.14-2.64.8-3.33.8-.69 0-1.74-.78-2.87-.76-1.47.02-2.83.86-3.59 2.18-1.54 2.66-.39 6.6 1.1 8.76.73 1.06 1.6 2.24 2.73 2.2 1.1-.05 1.51-.71 2.84-.71 1.32 0 1.7.71 2.86.69 1.18-.02 1.93-1.07 2.65-2.13.84-1.22 1.18-2.41 1.2-2.47-.03-.01-2.3-.88-2.32-3.5ZM14.2 6.13c.6-.73 1.01-1.75.9-2.76-.87.04-1.92.58-2.54 1.31-.56.64-1.05 1.68-.92 2.67.97.08 1.96-.49 2.56-1.22Z" />
      </svg>
      <span className="flex flex-col items-start leading-none">
        <span className="text-[11px] font-medium opacity-80">{APP_STORE_URL ? "Download on the" : "Coming soon to the"}</span>
        <span className="text-[19px] font-semibold tracking-tight">App Store</span>
      </span>
    </>
  );
  const className = "press inline-flex items-center gap-3 rounded-2xl bg-foreground px-6 py-3.5 text-background soft-shadow";
  return APP_STORE_URL ? (
    <a href={APP_STORE_URL} className={className}>{label}</a>
  ) : (
    <span className={className} aria-label="Coming soon to the App Store">{label}</span>
  );
}

export default function Home() {
  return (
    <main className="flex flex-col items-center text-center">
      <section className="flex flex-col items-center pt-6">
        <Image src="/icon.png" alt="" width={96} height={96} priority className="rounded-[22px] soft-shadow" />
        <h1 className="mt-6 text-5xl font-bold tracking-tight sm:text-6xl">Nourlo</h1>
        <p className="mt-4 max-w-md text-lg text-muted">
          Meals, budget and training in one friendly app. Plan your week, log what you eat by voice, and stay on track.
        </p>
        <div className="mt-8"><StoreButton /></div>
        <Image src="/mascot.png" alt="Nourlo's bowl mascot, smiling" width={450} height={417} priority className="mt-10 w-[300px] sm:w-[380px] h-auto" />
      </section>

      <section aria-label="What Nourlo does" className="mt-14 grid w-full gap-4 text-left sm:grid-cols-2">
        {FEATURES.map((f) => (
          <div key={f.title} className="rounded-[var(--radius-card)] bg-surface p-5 soft-shadow">
            <div className="text-3xl" aria-hidden="true">{f.emoji}</div>
            <h2 className="mt-3 text-lg font-semibold">{f.title}</h2>
            <p className="mt-1 text-muted">{f.text}</p>
          </div>
        ))}
      </section>

      <section className="mt-14 flex flex-col items-center">
        <h2 className="text-2xl font-bold tracking-tight">Free to start. On your iPhone.</h2>
        <p className="mt-2 max-w-md text-muted">Nourlo works offline, with no account needed to log food, plan meals or train.</p>
        <div className="mt-6"><StoreButton /></div>
      </section>
    </main>
  );
}
