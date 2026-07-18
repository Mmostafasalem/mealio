import type { Metadata } from "next";
import { Geist } from "next/font/google";
import "./globals.css";
import { Nav } from "@/components/Nav";

const geist = Geist({ subsets: ["latin"], variable: "--font-geist" });

export const metadata: Metadata = {
  title: "Mealio — Eat well. Spend less.",
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
      </body>
    </html>
  );
}
