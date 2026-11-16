"use client";

import { Sparkle } from "@phosphor-icons/react";
import { Card, PageHeader, EmptyState } from "@/components/ui";

// Shown in place of AI features while they're disabled on the website.
export function ComingSoon({ eyebrow, title, message }: {
  eyebrow: string; title: string; message: string;
}) {
  return (
    <>
      <PageHeader eyebrow={eyebrow} title={title} />
      <Card>
        <EmptyState icon={Sparkle} title="Coming soon" message={message} />
      </Card>
    </>
  );
}
