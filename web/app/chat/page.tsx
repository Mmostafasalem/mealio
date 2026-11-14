import { isWebAiEnabled } from "@/lib/flags";
import { ComingSoon } from "@/components/ComingSoon";
import { ChatClient } from "./ChatClient";

export default function ChatPage() {
  if (!isWebAiEnabled()) {
    return (
      <ComingSoon eyebrow="AI" title="Assistant"
        message="Online chat is coming soon. In the meantime, the Nourlo iOS app has the full assistant." />
    );
  }
  return <ChatClient />;
}
