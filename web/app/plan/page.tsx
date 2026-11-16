import { isWebAiEnabled } from "@/lib/flags";
import { ComingSoon } from "@/components/ComingSoon";
import { PlanClient } from "./PlanClient";

export default function PlanPage() {
  if (!isWebAiEnabled()) {
    return (
      <ComingSoon eyebrow="This week" title="Meal Plan"
        message="Online meal plans are coming soon. In the meantime, the Nourlo iOS app can build your weekly plan." />
    );
  }
  return <PlanClient />;
}
