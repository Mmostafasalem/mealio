import type { Metadata } from "next";
import "./globals.css";

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
    <html lang="en" className="h-full antialiased">
      <body className="min-h-full">{children}</body>
    </html>
  );
}
