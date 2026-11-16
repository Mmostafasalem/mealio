import type { Metadata } from "next";
import { LegalPage } from "@/components/LegalPage";
import legal from "@/content/legal.json";

export const metadata: Metadata = {
  title: "Privacy Policy — Nourlo",
  description: "Nourlo privacy policy: data use, retention, and your choices.",
};

export default function PrivacyPage() {
  return <LegalPage markdown={legal.privacy} />;
}
