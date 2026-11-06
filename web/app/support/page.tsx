import type { Metadata } from "next";
import { LegalPage } from "@/components/LegalPage";
import legal from "@/content/legal.json";

export const metadata: Metadata = {
  title: "Support — Mealio",
  description: "Help and frequently asked questions for the Mealio pre-release build.",
};

export default function SupportPage() {
  return <LegalPage markdown={legal.support} />;
}
