import type { Metadata } from "next";
import { Geist } from "next/font/google";
import "./globals.css";
import { Nav } from "@/components/Nav";
import Link from "next/link";

const geist = Geist({ subsets: ["latin"], variable: "--font-geist" });

export const metadata: Metadata = {
  title: "Nourlo — Eat well. Spend less.",
  description:
    "AI meal plans, calorie & macro tracking, and budget grocery lists for Vilnius.",
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="en" className={`${geist.variable} h-full antialiased`}>
      <body className="min-h-full">
        <Nav />
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
