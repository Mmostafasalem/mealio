import type { Metadata } from "next";
import { Geist } from "next/font/google";
import Image from "next/image";
import Link from "next/link";
import "./globals.css";

const geist = Geist({ subsets: ["latin"], variable: "--font-geist" });

export const metadata: Metadata = {
  title: "Nourlo: meals, budget and training",
  description: "Plan a week of meals on a budget, log food by voice, track calories and macros, and get workouts made for you.",
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="en" className={`${geist.variable} h-full antialiased`}>
      <body className="min-h-full">
        <header className="mx-auto flex max-w-3xl items-center px-4 pt-6">
          <Link href="/" className="flex items-center gap-2.5 font-semibold">
            <Image src="/icon.png" alt="" width={32} height={32} className="rounded-[8px]" />
            Nourlo
          </Link>
        </header>
        <div className="mx-auto max-w-3xl px-4 pb-16 pt-6">{children}</div>
        <footer className="mx-auto max-w-3xl px-4 pb-8 text-sm text-muted">
          <nav aria-label="Legal and support" className="flex flex-wrap gap-6">
            <Link href="/privacy" className="underline underline-offset-4">Privacy Policy</Link>
            <Link href="/support" className="underline underline-offset-4">Support</Link>
          </nav>
        </footer>
      </body>
    </html>
  );
}
