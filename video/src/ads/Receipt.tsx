import React from "react";
import { AbsoluteFill, Easing, Sequence, interpolate, useCurrentFrame } from "remotion";
import { Card, EndCard, FPS, Headline, Mascot, Page, grey, ink, pink, ring, s } from "./kit";
import T from "./receipt.json";

// The grocery receipt, before and after Nourlo: same week, half the receipt.

const clamp = { extrapolateLeft: "clamp", extrapolateRight: "clamp" } as const;
const mono = '"SF Mono", Menlo, monospace';

const BEFORE: [string, string][] = [["CRISPS FAMILY BAG", "3.49"], ["ENERGY DRINK X4", "5.99"], ["FROZEN PIZZA", "5.99"], ["FROZEN PIZZA", "5.99"], ["CHOC COOKIES", "2.89"],
  ["READY MEAL LASAGNE", "6.49"], ["TAKEAWAY SUSHI", "14.90"], ["ICE CREAM TUB", "4.99"], ["CHEESE PUFFS", "2.49"], ["SODA 2L", "2.19"], ["SNACK BARS X6", "6.99"], ["TAKEAWAY BURGER", "9.40"]];
const AFTER: [string, string][] = [["CHICKEN BREAST 600G", "6.29"], ["EGGS X12", "2.89"], ["RICE 1KG", "1.79"], ["SPINACH", "1.49"], ["CHICKPEAS X2", "1.38"],
  ["GREEK YOGURT 500G", "2.19"], ["OATS 1KG", "1.29"], ["BANANAS", "1.39"], ["SALMON 2 FILLETS", "5.99"], ["POTATOES 2KG", "2.49"], ["LENTILS", "1.59"], ["FROZEN BERRIES", "3.49"], ["TORTILLAS", "1.39"], ["TUNA X2", "2.18"], ["FETA", "1.79"]];

const Paper: React.FC<{ rows: [string, string][]; at: number; lps: number; total: string; stamp: number; stampText: string; stampColor: string; out: number; note: string }> = ({
  rows, at, lps, total, stamp, stampText, stampColor, out, note,
}) => {
  const frame = useCurrentFrame();
  const t = frame / FPS;
  if (t < at || t > out + 0.3) return null;
  const n = Math.min(rows.length, Math.floor((t - at) * lps));
  const printed = Math.min(1, (t - at) * lps / rows.length);
  const st = interpolate(t, [stamp, stamp + 0.18], [0, 1], { ...clamp, easing: Easing.out(Easing.back(2)) });
  const gone = interpolate(t, [out, out + 0.3], [0, 1], { ...clamp, easing: Easing.in(Easing.cubic) });
  const H = 300 + rows.length * 58;
  return (
    <div style={{ position: "absolute", top: 120 - gone * 1800, width: 760, display: "flex", flexDirection: "column", alignItems: "center" }}>
      {/* the printer slot */}
      <div style={{ width: 860, height: 40, borderRadius: 20, background: "#2A2A30", zIndex: 2 }} />
      <div style={{ width: 760, height: H * (0.15 + 0.85 * printed), overflow: "hidden", marginTop: -14, position: "relative" }}>
        <div style={{ position: "absolute", bottom: 0, width: 760, height: H, background: "#FFFDF8", boxShadow: "0 20px 60px rgba(0,0,0,0.12)", fontFamily: mono, color: "#2A2A30",
                      padding: "50px 54px", boxSizing: "border-box", clipPath: "polygon(0 0,100% 0,100% 98%,95% 100%,90% 98%,85% 100%,80% 98%,75% 100%,70% 98%,65% 100%,60% 98%,55% 100%,50% 98%,45% 100%,40% 98%,35% 100%,30% 98%,25% 100%,20% 98%,15% 100%,10% 98%,5% 100%,0 98%)" }}>
          <div style={{ textAlign: "center", fontSize: 34, fontWeight: 700, letterSpacing: 4 }}>GROCERY RECEIPT</div>
          <div style={{ textAlign: "center", fontSize: 26, color: grey, marginBottom: 26 }}>{note}</div>
          {rows.map(([name, price], i) => (
            <div key={i} style={{ display: "flex", justifyContent: "space-between", fontSize: 32, lineHeight: "58px", opacity: i < n ? 1 : 0 }}><span>{name}</span><span>€{price}</span></div>
          ))}
          <div style={{ borderTop: "3px dashed #999", marginTop: 20, paddingTop: 20, display: "flex", justifyContent: "space-between", fontSize: 44, fontWeight: 800, opacity: n >= rows.length ? 1 : 0 }}>
            <span>TOTAL</span><span>€{total}</span>
          </div>
        </div>
      </div>
      <div style={{ position: "absolute", top: 260 + rows.length * 30, border: `8px solid ${stampColor}`, color: stampColor, fontSize: 70, fontWeight: 900, padding: "14px 34px", borderRadius: 18,
                    transform: `rotate(-12deg) scale(${2 - st})`, opacity: st, fontFamily: '-apple-system, sans-serif', letterSpacing: 2, background: "rgba(255,255,255,0.75)", zIndex: 3 }}>{stampText}</div>
    </div>
  );
};

export const receiptLength = s(T.dur);

export const Receipt: React.FC = () => {
  const frame = useCurrentFrame();
  const t = frame / FPS;
  const fill = interpolate(t, [T.budget.at + 0.3, T.budget.at + 1.4], [0, 38.6 / 40], { ...clamp, easing: Easing.out(Easing.cubic) });
  return (
    <AbsoluteFill>
      <Page bg="#F4F1EC">
        <Paper rows={BEFORE} at={T.before.at} lps={T.before.lps} total="71.40" stamp={T.before.stamp} stampText="OVER BUDGET" stampColor="#E24B4A" out={T.before.out} note="a normal week, apparently" />
        {t >= T.then.at && t < T.then.out + 0.2 && <Headline text="Then I tried Nourlo" at={T.then.at} top={820} size={120} mark={["nourlo"]} out={T.then.out} />}
        <Paper rows={AFTER} at={T.after.at} lps={T.after.lps} total="38.60" stamp={T.after.stamp} stampText="UNDER BUDGET" stampColor={ring.protein} out={T.after.out} note="7 days of meals, planned" />
        {t >= T.budget.at && t < T.budget.out + 0.2 && (
          <AbsoluteFill style={{ alignItems: "center" }}>
            <Card at={T.budget.at} top={420} style={{ padding: "44px 50px" }}>
              <div style={{ display: "flex", justifyContent: "space-between", alignItems: "baseline" }}>
                <div style={{ fontSize: 52, fontWeight: 800 }}>This week</div>
                <div style={{ fontSize: 40, color: grey, fontWeight: 600, fontVariantNumeric: "tabular-nums" }}>€{(fill * 40).toFixed(2)} of €40</div>
              </div>
              <div style={{ height: 28, borderRadius: 14, background: "#F1F1F4", marginTop: 26, overflow: "hidden" }}><div style={{ width: `${fill * 100}%`, height: "100%", background: pink, borderRadius: 14 }} /></div>
              <div style={{ display: "flex", gap: 18, marginTop: 30, fontSize: 36, fontWeight: 700 }}>
                <span style={{ background: "#E9F8F2", color: "#14805F", padding: "12px 24px", borderRadius: 30 }}>−€32.80 vs last week</span>
                <span style={{ background: "#FDE7EE", color: "#B3365A", padding: "12px 24px", borderRadius: 30 }}>21 meals</span>
              </div>
            </Card>
            <div style={{ position: "absolute", top: 1000 }}><Mascot clip="love" at={T.budget.at + 0.2} size={720} /></div>
          </AbsoluteFill>
        )}
        {t >= T.line.at && <><Headline text="Same week. Half the receipt." at={T.line.at} top={760} size={118} mark={["half"]} /></>}
      </Page>
      <Sequence from={s(T.end)}><EndCard at={0} /></Sequence>
      <span style={{ display: "none", color: ink }} />
    </AbsoluteFill>
  );
};
