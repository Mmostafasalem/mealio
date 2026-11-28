import React from "react";
import { AbsoluteFill, Sequence, interpolate, useCurrentFrame } from "remotion";
import { AskBar, Card, EndCard, FPS, Headline, LockScreen, Mascot, Notice, Page, Pointer, grey, ink, line, pink, s, useP, useSpring } from "./kit";
import T from "./notifications.json";

// After reference 1: the notifications pile up, "one minute earlier", one request to Nourlo,
// the week gets planned, and the notifications change their tune.

const Pile: React.FC<{ list: typeof T.before; offset?: number }> = ({ list, offset = 0 }) => (
  <LockScreen>
    {list.map((n, i) => (
      <Notice key={i} at={n.at - offset} app={n.title} title={n.title} body={n.body} avatar={n.color} initial={n.initial} icon={n.icon} time={n.time} />
    ))}
  </LockScreen>
);

const Thinking: React.FC<{ at: number; until: number }> = ({ at, until }) => {
  const frame = useCurrentFrame();
  const t = frame / FPS;
  if (t < at || t > until) return null;
  const dots = ".".repeat(1 + (Math.floor(t * 4) % 3));
  return <div style={{ fontSize: 40, color: grey, fontWeight: 600 }}>Planning your week{dots}</div>;
};

const Week: React.FC = () => {
  const frame = useCurrentFrame();
  const t = frame / FPS;
  const fill = useP(T.plan.at + 0.3, T.plan.at + 1.6);
  const spent = (38.6 * fill).toFixed(2);
  const btn = useSpring(T.plan.button, 13);
  const press = 1 - 0.06 * Math.max(0, 1 - Math.abs(t - T.plan.click - 0.08) * 10);
  const toast = useSpring(T.plan.toast, 12);
  return (
    <>
      <div style={{ position: "absolute", top: 380, display: "flex", alignItems: "center", gap: 18 }}>
        <Mascot clip={t < T.plan.at ? "thinking" : "happy"} at={t < T.plan.at ? T.ask.sent : T.plan.at} size={170} />
        <Thinking at={T.ask.sent} until={T.plan.at} />
      </div>
      {t >= T.plan.at && (
        <Card at={T.plan.at} top={560} style={{ padding: "36px 44px" }}>
          <div style={{ display: "flex", justifyContent: "space-between", alignItems: "baseline" }}>
            <div style={{ fontSize: 50, fontWeight: 800 }}>Your week</div>
            <div style={{ fontSize: 38, color: grey, fontVariantNumeric: "tabular-nums", fontWeight: 600 }}>€{spent} of €40</div>
          </div>
          <div style={{ height: 18, borderRadius: 9, background: "#F1F1F4", marginTop: 20, overflow: "hidden" }}>
            <div style={{ width: `${fill * 96.5}%`, height: "100%", borderRadius: 9, background: pink }} />
          </div>
          <div style={{ marginTop: 16 }}>
            {T.plan.days.map((d, i) => {
              const p = interpolate(t, [T.plan.at + 0.4 + i * 0.16, T.plan.at + 0.7 + i * 0.16], [0, 1], { extrapolateLeft: "clamp", extrapolateRight: "clamp" });
              return (
                <div key={d[0]} style={{ display: "flex", alignItems: "center", gap: 22, padding: "16px 0", borderTop: i ? `2px solid ${line}` : "none", opacity: p, transform: `translateX(${(1 - p) * 40}px)` }}>
                  <div style={{ width: 86, fontSize: 34, fontWeight: 700, color: grey }}>{d[0]}</div>
                  <div style={{ fontSize: 44 }}>{d[1]}</div>
                  <div style={{ flex: 1, fontSize: 36, fontWeight: 600 }}>{d[2]}</div>
                  <div style={{ fontSize: 32, color: grey, fontVariantNumeric: "tabular-nums" }}>{d[3]}</div>
                </div>
              );
            })}
          </div>
          <div style={{ marginTop: 24, height: 104, borderRadius: 52, background: ink, color: "#fff", fontSize: 40, fontWeight: 700, display: "flex", alignItems: "center", justifyContent: "center",
                        transform: `scale(${btn * press})` }}>
            Add 14 items to cart
          </div>
        </Card>
      )}
      <div style={{ position: "absolute", top: 1660, background: "#fff", border: `2px solid ${line}`, borderRadius: 50, padding: "22px 40px", fontSize: 38, fontWeight: 700,
                    boxShadow: "0 16px 40px rgba(0,0,0,0.12)", transform: `translateY(${(1 - toast) * 160}px)`, opacity: toast, display: "flex", gap: 14, alignItems: "center" }}>
        <span style={{ color: "#1FA98C" }}>✓</span> 14 items in your cart · €38.60
      </div>
    </>
  );
};

export const notificationsLength = s(T.dur);

export const Notifications: React.FC = () => {
  const frame = useCurrentFrame();
  const t = frame / FPS;
  return (
    <AbsoluteFill>
      <Sequence durationInFrames={s(T.earlier)}><Pile list={T.before} /></Sequence>
      {t >= T.earlier && t < T.after && (<AbsoluteFill>
        <Page>
          {t < T.ask.at && <div style={{ position: "absolute", top: 860, width: "100%" }}><Headline text="One minute earlier.." at={T.earlier + 0.1} top={0} size={84} /></div>}
          {t >= T.ask.at && (
            <div style={{ position: "absolute", top: interpolate(t, [T.ask.sent + 0.1, T.ask.sent + 0.5], [880, 150], { extrapolateLeft: "clamp", extrapolateRight: "clamp" }), display: "flex", justifyContent: "center", width: "100%" }}>
              <AskBar text={T.ask.text} at={T.ask.at} cps={T.ask.cps} top={0} sendAt={T.ask.sent} />
            </div>
          )}
          {t >= T.ask.sent && <Week />}
        </Page>
        <Pointer stops={[[T.ask.sent - 0.9, 1100, 1250], [T.ask.sent, 900, 935, true], [T.plan.click - 0.6, 900, 980], [T.plan.click, 560, 1380, true], [T.plan.click + 0.6, 760, 1560]]}
                 show={[T.ask.sent - 0.9, T.plan.toast + 0.6]} />
      </AbsoluteFill>)}
      <Sequence from={s(T.after)} durationInFrames={s(T.punch.at - T.after)}>
        <Pile list={T.afterList} offset={T.after} />
        <div style={{ position: "absolute", bottom: -40, left: 0, right: 0, display: "flex", justifyContent: "center" }}>
          <Mascot clip="celebrate" at={T.mascot - T.after} size={520} />
        </div>
      </Sequence>
      <Sequence from={s(T.punch.at)} durationInFrames={s(T.end - T.punch.at)}>
        <Page><div style={{ position: "absolute", top: 880, display: "flex", justifyContent: "center", width: "100%" }}>
          <AskBar text={T.punch.text} at={0.15} cps={T.punch.cps} top={0} />
        </div></Page>
      </Sequence>
      <Sequence from={s(T.end)}><EndCard at={0} /></Sequence>
    </AbsoluteFill>
  );
};
