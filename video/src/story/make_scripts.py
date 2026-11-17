"""Writes the scripted adverts (src/story/ads/<id>.json): scenes on the music's bar lines, Nourlo's path
(walks, jumps between spots and into the next scene) and what Nourlo does (moods, hops, waves, flexes).

    python3 src/story/make_scripts.py && ./make-stories.sh
"""
import json
from pathlib import Path

OUT = Path(__file__).parent / "ads"

# Where Nourlo stands. Cards sit between y 420 and about 1150; Nourlo's home is below them.
HOME = {"left": (270, 1470, 500), "mid": (540, 1470, 520), "right": (810, 1470, 500), "low": (540, 1580, 440),
        "hero": (540, 1150, 780), "big": (540, 1250, 640), "offL": (-380, 1470, 500), "offR": (1460, 1470, 500),
        "top": (540, -400, 520), "badge": (800, 1300, 440),
        # big, but low enough that a speech bubble above clears the headline
        "talk": (540, 1360, 640)}


class Ad:
    def __init__(self, id, bpm, style, bars, drums=(1, None), theme="white"):
        self.id, self.bpm, self.bar, self.theme, self.overlays = id, bpm, 240 / bpm, theme, []
        self.music = {"style": style, "bars": bars, "drumsFrom": drums[0], "drumsTo": drums[1] if drums[1] else len(bars) - 1}
        self.scenes, self.path, self.rig, self.sfx = [], [], [], []

    def b(self, n):  # bar n in seconds
        return round(n * self.bar, 3)

    def scene(self, kind, at, label=None, mark=(), cut="dissolve", **kw):
        s = {"kind": kind, "at": at, "cut": cut}
        if label: s["label"] = label
        if mark: s["mark"] = list(mark)
        s.update(kw)
        self.scenes.append(s)

    def at(self, t, spot, move=None, arc=None, **kw):
        x, y, size = HOME[spot] if isinstance(spot, str) else spot
        k = {"t": round(t, 3), "x": x, "y": y, "size": size}
        if move: k["move"] = move
        if arc: k["arc"] = arc
        k.update(kw)
        self.path.append(k)

    def hold(self, t):  # stay where the last key put Nourlo until t
        last = self.path[-1]
        self.path.append({"t": round(t, 3), "x": last["x"], "y": last["y"], "size": last["size"]})

    def jump(self, t0, t1, spot, arc=280):
        self.hold(t0); self.at(t1, spot, "jump", arc)

    def walk(self, t0, t1, spot):
        self.hold(t0); self.at(t1, spot, "walk")

    def glide(self, t0, t1, spot):
        self.hold(t0); self.at(t1, spot)

    def do(self, t, *cmds):
        for c in cmds: self.rig.append([round(t, 3), c])

    def overlay(self, kind, at, **kw):
        self.overlays.append({"kind": kind, "at": round(at, 3), **kw})

    def say(self, t0, t1, text, side="right"):
        self.overlay("bubble", t0, until=round(t1, 3), text=text, side=side); self.fx(t0, "pop")

    def fx(self, t, kind, *args):
        self.sfx.append([round(t, 3), kind, *args])

    def write(self, end_at, tail=2.6):
        self.scene("end", end_at)
        data = {"id": self.id, "dur": round(end_at + tail, 3), "bpm": self.bpm, "music": self.music,
                "scenes": self.scenes, "path": self.path, "rig": self.rig, "sfx": self.sfx, "theme": self.theme, "overlays": self.overlays}
        keys = [k["t"] for k in self.path]
        assert keys == sorted(keys), (self.id, keys)
        (OUT / f"{self.id}.json").write_text(json.dumps(data, indent=1, ensure_ascii=False))
        print(self.id, data["dur"], "s")


def gym():
    a = Ad("gym", 120, "disco", ["Am9", "Dm9", "G9", "Cmaj7", "Am9", "Dm9", "G9", "Cmaj7", "Am9"])
    b = a.b
    a.scene("title", 0, "Nourlo trains with you", ["nourlo"])
    a.scene("workout", b(1), "Log every set", ["set"], "slide")
    a.scene("progress", b(3), "Watch yourself grow", ["grow"], "slide")
    a.scene("timer", b(5), "Rest timer built in", ["timer"], "zoom")
    a.scene("title", b(6), "Stronger every week", ["stronger"], "rise", titleTop=260)
    a.at(0, "offL"); a.walk(0, 1.3, (540, 1250, 640)); a.do(0, "mood happy"); a.do(1.35, "wave")
    # into the workout: a jump to the right of the card
    a.jump(b(1) - 0.15, b(1) + 0.45, "right"); a.do(b(1) + 0.6, "look -0.3 -0.9")
    for i in range(3): a.fx(b(1) + 0.55 + i * 0.4, "tap")
    # the record: up beside the badge, a big flex
    a.jump(b(1) + 1.45, b(1) + 1.85, "badge", 200); a.do(b(1) + 1.75, "mood flex"); a.fx(b(1) + 1.75, "sparkle")
    a.do(b(1) + 2.9, "resize 0.7"); a.do(b(2) + 1.2, "mood happy", "look none")
    # the chart slides in; Nourlo walks across with it
    a.jump(b(3) - 0.3, b(3) + 0.3, "right", 160); a.walk(b(3) + 0.35, b(3) + 1.3, "left")
    a.do(b(3) + 1.3, "look 0.5 -0.8"); a.do(b(3) + 1.6, "hop"); a.fx(b(3) + 1.25, "success"); a.do(b(4) + 1, "look none")
    # the timer: hops to the middle and jogs on the spot
    a.jump(b(5) - 0.2, b(5) + 0.4, "low", 300); a.do(b(5) + 0.5, "walk 1.3"); a.do(b(6) - 0.3, "walk 0"); a.fx(b(5) + 0.9, "beep")
    # the finale: big and flexing
    a.jump(b(6) - 0.1, b(6) + 0.6, "hero", 220); a.do(b(6) + 0.6, "mood flex"); a.fx(b(6) + 0.6, "sparkle")
    a.do(b(6) + 1.5, "resize 0.8"); a.do(b(6) + 2.3, "hop")
    a.do(b(7) + 0.9, "mood love"); a.do(b(7) + 1.1, "wave")
    a.write(b(7) + 1)


def kitchen():
    a = Ad("kitchen", 88, "lofi", ["Fmaj7", "Em7", "Dm9", "Cmaj7", "Fmaj7", "Em7", "Dm9", "Cmaj7"])
    b = a.b
    a.scene("title", 0, "What's for dinner?", ["dinner"])
    a.scene("stock", b(1), "Cook what you have", ["have"], "slide")
    a.scene("recipe", b(3), "1,500 recipes. No AI.", ["1500"], "rise")
    a.scene("day", b(5), "Counted for you", ["counted"], "zoom")
    a.at(0, "big"); a.do(0, "mood thinking", "look -0.6 -0.8"); a.do(1.2, "look 0.6 -0.8"); a.fx(1.8, "pop")
    a.do(b(1) - 0.6, "mood happy", "look none"); a.do(b(1) - 0.3, "resize 0.8")
    # hops across the fridge tiles, left to right
    a.jump(b(1) - 0.1, b(1) + 0.5, (220, 800, 380), 300); a.fx(b(1) + 0.5, "pop")
    a.jump(b(1) + 0.9, b(1) + 1.4, (540, 800, 380), 200); a.fx(b(1) + 1.4, "pop")
    a.jump(b(1) + 1.8, b(1) + 2.3, (860, 800, 380), 200); a.fx(b(1) + 2.3, "pop"); a.do(b(1) + 2.4, "look -0.4 0.6")
    a.jump(b(2) + 0.2, b(2) + 0.9, "left", 200); a.do(b(2) + 1.0, "look 0.6 -0.6", "mood love"); a.fx(b(2) + 0.6, "success")
    # the recipe rises; Nourlo waits by the button, then celebrates the log
    a.glide(b(3) - 0.3, b(3) + 0.4, "right"); a.do(b(3) + 0.4, "mood happy", "look -0.6 -0.5")
    a.fx(b(3) + 1.55, "tap"); a.fx(b(3) + 1.8, "success"); a.do(b(3) + 1.8, "mood celebrate"); a.do(b(3) + 2.6, "hop")
    # rings fill; Nourlo pats its tummy (resize) and grins
    a.jump(b(5) - 0.2, b(5) + 0.5, "mid", 260); a.do(b(5) + 0.5, "mood happy", "look none"); a.do(b(5) + 1.6, "resize 0.6")
    a.do(b(6) + 0.6, "mood love", "wave")
    a.write(b(6) + 0.9)


def budget():
    a = Ad("budget", 116, "pop", ["C", "G", "Am7", "F", "C", "G", "Am7", "F", "C"])
    b = a.b
    a.scene("title", 0, "€40 for a whole week?", ["week"], titleSize=124)
    a.scene("groceries", b(1), "Groceries fitted to your budget", ["budget"], "slide")
    a.scene("budget", b(3), "Money to spare", ["spare"], "slide")
    a.scene("plan", b(5), "Meals from what you buy", ["buy"], "zoom")
    a.at(0, "offR"); a.walk(0, 1.2, "big"); a.do(0, "mood worried"); a.do(1.3, "look 0 -1"); a.fx(1.0, "pop")
    a.do(b(1) - 0.4, "mood happy", "look none")
    # runs alongside the list as each item lands
    a.jump(b(1) - 0.1, b(1) + 0.5, "left", 260)
    a.walk(b(1) + 0.6, b(1) + 1.6, "right"); a.do(b(1) + 1.7, "look -0.5 -0.8")
    for i in range(5): a.fx(b(1) + 0.35 + i * 0.22, "coin")
    a.do(b(2) + 1.0, "hop")
    # the budget bar: hearts when there is money left
    a.jump(b(3) - 0.2, b(3) + 0.4, "mid", 220); a.do(b(3) + 1.3, "mood love"); a.fx(b(3) + 1.3, "sparkle"); a.do(b(4), "resize 0.7")
    # the week of meals: Nourlo bounces in from above the page
    a.glide(b(5) - 0.3, b(5) - 0.05, "top"); a.at(b(5) + 0.55, "mid", "jump", 80); a.do(b(5) + 0.6, "mood happy")
    a.do(b(5) + 1.4, "look 0 -1"); a.do(b(6) + 0.4, "look none", "wave")
    a.write(b(6) + 1.1)


def voice():
    a = Ad("voice", 132, "garage", ["Bbmaj9", "Am7", "Gm9", "C13", "Bbmaj9", "Am7", "Gm9", "C13", "Fmaj9", "Fmaj9"])
    b = a.b
    a.scene("title", 0, "Just say what you ate", ["say"])
    a.scene("voice", b(1), "Nourlo logs it", ["logs"], "slide")
    a.scene("lines", b(3), "In four languages", ["four"], "rise", items=["English", "Deutsch", "العربية", "Lietuvių"])
    a.scene("scan", b(5), "Or scan it", ["scan"], "slide")
    a.scene("title", b(7), "Logging, done in a second", ["second"], "zoom", titleTop=300)
    a.at(0, "big"); a.do(0, "mood happy"); a.do(0.6, "tap")
    a.jump(b(1) - 0.2, b(1) + 0.4, "right", 260); a.do(b(1) + 0.4, "look -0.6 -0.9", "mood idle"); a.do(b(1) + 1.3, "mood happy", "hop")
    a.fx(b(1) + 1.3, "success")
    for i, lang in enumerate(range(4)):
        x = 220 + i * 210
        a.jump(b(3) + 0.25 + i * 0.25, b(3) + 0.45 + i * 0.25, (x, 1470, 440), 120)
    a.fx(b(3) + 0.4, "pop"); a.fx(b(3) + 0.65, "pop"); a.fx(b(3) + 0.9, "pop"); a.fx(b(3) + 1.15, "pop"); a.do(b(3) + 1.3, "mood love")
    a.walk(b(5) - 0.4, b(5) + 0.6, "left"); a.do(b(5) + 0.6, "mood cheeky", "look 0.5 -0.9"); a.fx(b(5) + 0.85, "beep"); a.fx(b(5) + 1.05, "success")
    a.do(b(5) + 1.1, "hop", "look none")
    a.jump(b(7) - 0.2, b(7) + 0.5, "hero", 240); a.do(b(7) + 0.5, "mood celebrate"); a.do(b(8) + 0.2, "mood love", "wave")
    a.write(b(8) + 0.6)


def plan():
    a = Ad("plan", 110, "song", ["Fmaj7", "Am7", "Dm9", "Bbmaj7", "Csus", "Fmaj7", "Am7", "Dm9", "Bbmaj7", "Fadd9"], (1, 9))
    b = a.b
    a.scene("title", 0, "A week of meals in one tap", ["one", "tap"])
    a.scene("plan", b(1), "Built from your kitchen", ["kitchen"], "slide")
    a.scene("split", b(3), "Split your day your way", ["your", "way"], "slide")
    a.scene("shuffle", b(5), "Not feeling it?", ["feeling"], "rise")
    a.scene("title", b(7), "Nourlo plans. You eat.", ["eat"], "zoom", titleTop=300)
    a.at(0, "offL"); a.walk(0, 1.4, "big"); a.do(0, "mood happy"); a.do(1.5, "wave")
    a.jump(b(1) - 0.2, b(1) + 0.4, "left", 280); a.do(b(1) + 0.4, "look 0.5 -0.9"); a.fx(b(1) + 0.15, "type", 22, 30); a.fx(b(1) + 1.0, "click")
    a.do(b(1) + 1.2, "hop"); a.fx(b(1) + 1.1, "success")
    a.walk(b(3) - 0.5, b(3) + 0.5, "right"); a.do(b(3) + 0.6, "look -0.5 -0.9", "mood thinking"); a.do(b(4), "mood happy", "resize 0.6")
    a.jump(b(5) - 0.2, b(5) + 0.5, "mid", 200); a.do(b(5) + 0.5, "mood cheeky"); a.fx(b(5) + 1.0, "click"); a.do(b(5) + 1.0, "hop")
    for i in range(3): a.fx(b(5) + 1.1 + i * 0.12, "pop")
    a.do(b(5) + 1.6, "mood happy")
    a.jump(b(7) - 0.2, b(7) + 0.5, "hero", 240); a.do(b(7) + 0.5, "mood love"); a.do(b(8), "wave")
    a.write(b(8) + 0.9)


def day():
    # The whole app in one day: Nourlo jumps from each scene into the next.
    a = Ad("day", 124, "disco", ["Dm9", "Gm9", "C9", "Fmaj7", "Dm9", "Gm9", "C9", "Fmaj7", "Dm9", "Gm9", "C9", "Fmaj7"])
    b = a.b
    a.scene("title", 0, "A day with Nourlo", ["nourlo"])
    a.scene("voice", b(1), "Breakfast, logged by voice", ["voice"], "slide")
    a.scene("groceries", b(2.5), "Groceries on budget", ["budget"], "slide")
    a.scene("workout", b(4), "Lunch break PR", ["pr"], "slide")
    a.scene("recipe", b(5.5), "Dinner from your fridge", ["fridge"], "slide")
    a.scene("day", b(7), "Every calorie counted", ["counted"], "slide")
    a.scene("title", b(8.5), "Your whole day, one bowl", ["one", "bowl"], "zoom", titleTop=300)
    a.at(0, "offL"); a.do(0, "mood sleepy"); a.walk(0.2, 1.4, "big"); a.do(1.0, "mood happy", "wave")
    spots = ["right", "left", "badge", "right", "mid"]
    starts = [1, 2.5, 4, 5.5, 7]
    for i, (s, st) in enumerate(zip(spots, starts)):
        t0 = b(st)
        a.jump(t0 - 0.25, t0 + 0.35, s if s != "badge" else "right", 300 if i % 2 == 0 else 220)
    # what Nourlo does in each scene
    a.do(b(1) + 0.5, "look -0.6 -0.9"); a.do(b(1) + 1.3, "hop"); a.fx(b(1) + 1.3, "success")
    for i in range(5): a.fx(b(2.5) + 0.35 + i * 0.22, "coin")
    a.do(b(2.5) + 1.4, "mood love")
    for i in range(3): a.fx(b(4) + 0.55 + i * 0.4, "tap")
    a.do(b(4) + 1.75, "mood flex"); a.fx(b(4) + 1.75, "sparkle"); a.do(b(4) + 2.4, "resize 0.8")
    a.do(b(5.5) + 0.2, "mood happy"); a.fx(b(5.5) + 1.55, "tap"); a.fx(b(5.5) + 1.8, "success"); a.do(b(5.5) + 1.8, "hop")
    a.do(b(7) + 0.4, "look 0 -1"); a.do(b(7) + 1.5, "look none", "resize 0.6")
    a.jump(b(8.5) - 0.2, b(8.5) + 0.5, "hero", 240); a.do(b(8.5) + 0.5, "mood celebrate"); a.do(b(9.5), "mood flex"); a.do(b(10) + 0.4, "mood love", "wave")
    a.write(b(10) + 0.7)


def buddy():
    # A short teaser: Nourlo drops in, flexes, and shows off.
    a = Ad("buddy", 120, "pop", ["Am7", "F", "C", "G", "Am7", "F", "C"])
    b = a.b
    a.scene("title", 0, "Meet your gym buddy", ["buddy"], titleSize=124)
    a.scene("timer", b(1.5), "Every rest, timed", ["timed"], "slide")
    a.scene("workout", b(3), "Every PR, cheered", ["cheered"], "slide")
    a.scene("title", b(4.5), "It's a bowl. It lifts.", ["lifts"], "zoom", titleTop=300)
    a.at(0, "top"); a.at(0.7, "hero", "jump", 60); a.do(0.75, "mood happy"); a.do(1.3, "mood flex"); a.fx(1.3, "sparkle"); a.do(2.2, "resize 0.9")
    a.jump(b(1.5) - 0.2, b(1.5) + 0.4, "low", 300); a.do(b(1.5) + 0.5, "walk 1.4"); a.do(b(3) - 0.4, "walk 0"); a.fx(b(1.5) + 0.9, "beep")
    a.jump(b(3) - 0.2, b(3) + 0.4, "right", 260)
    for i in range(3): a.fx(b(3) + 0.55 + i * 0.4, "tap")
    a.jump(b(3) + 1.45, b(3) + 1.85, "badge", 200); a.do(b(3) + 1.75, "mood flex"); a.fx(b(3) + 1.75, "sparkle")
    a.jump(b(4.5) - 0.2, b(4.5) + 0.5, "hero", 240); a.do(b(4.5) + 0.6, "resize 0.9"); a.do(b(5) + 0.4, "hop"); a.do(b(5.5) + 0.3, "mood love", "wave")
    a.write(b(5.5) + 0.6, 2.4)


def morning():
    a = Ad("morning", 90, "lofi", ["Cmaj7", "Am7", "Dm9", "G9", "Cmaj7", "Am7", "Dm9", "Cmaj7"])
    b = a.b
    a.scene("title", 0, "Good morning", ["morning"], titleSize=130)
    a.scene("voice", b(1), "Say breakfast. Done.", ["done"], "rise")
    a.scene("day", b(2.5), "See your day at a glance", ["glance"], "slide")
    a.scene("plan", b(4), "Lunch and dinner, planned", ["planned"], "slide")
    a.at(0, "big"); a.do(0, "mood sleepy"); a.do(1.6, "mood happy", "resize 0.8"); a.fx(1.6, "pop"); a.do(2.2, "wave")
    a.jump(b(1) - 0.2, b(1) + 0.4, "right", 240); a.do(b(1) + 0.4, "look -0.6 -0.9"); a.do(b(1) + 1.3, "hop"); a.fx(b(1) + 1.3, "success")
    a.walk(b(2.5) - 0.3, b(2.5) + 0.7, "left"); a.do(b(2.5) + 0.8, "look 0.5 -0.9", "mood love")
    a.jump(b(4) - 0.2, b(4) + 0.4, "mid", 260); a.do(b(4) + 0.4, "mood happy", "look 0 -1"); a.fx(b(4) + 0.15, "type", 22, 30); a.fx(b(4) + 1.0, "click")
    a.do(b(4) + 1.2, "hop", "look none"); a.do(b(5) + 0.6, "wave")
    a.write(b(5) + 1.2)


# ---------- second set: other looks and ideas ----------

def neon():
    a = Ad("neon", 124, "disco", ["Em9", "Am9", "Dmaj7", "Gmaj7", "Em9", "Am9", "Dmaj7", "Gmaj7", "Em9", "Em9"], theme="dark")
    b = a.b
    beat = 60 / 124
    words = ["Plan.", "Shop.", "Cook.", "Lift.", "Repeat."]
    a.scene("kinetic", 0, words=words, every=round(beat * 2, 3), colors=["#FFFFFF", "#E8698A", "#FFFFFF", "#6FE0C8", "#E8698A"])
    a.scene("plan", b(2.5), "Your week, planned", ["planned"], "zoom")
    a.scene("groceries", b(4), "Shopping, sorted", ["sorted"], "slide")
    a.scene("workout", b(5.5), "Records, broken", ["broken"], "slide")
    a.scene("title", b(7), "All in one bowl", ["one", "bowl"], "zoom", titleTop=300)
    a.at(0, "offL")
    # lands on each word as it slams in
    spots = [(300, 1330, 460), (780, 1330, 460), (300, 1330, 460), (780, 1330, 460), (540, 1300, 520)]
    for i, sp in enumerate(spots):
        t0 = i * beat * 2
        a.jump(max(0.0, t0 - 0.05) if i else 0.0, t0 + 0.45, sp, 260 if i else 200)
        a.fx(t0, "pop")
    a.do(0, "mood happy"); a.do(beat * 6 + 0.4, "mood flex"); a.do(beat * 8 + 0.4, "mood celebrate")
    a.jump(b(2.5) - 0.2, b(2.5) + 0.4, "left", 220); a.do(b(2.5) + 0.5, "mood happy", "look 0.5 -0.9"); a.fx(b(2.5) + 0.15, "type", 22, 30)
    a.walk(b(4) - 0.4, b(4) + 0.6, "right")
    for i in range(5): a.fx(b(4) + 0.35 + i * 0.22, "coin")
    a.jump(b(5.5) - 0.2, b(5.5) + 0.4, "right", 220)
    for i in range(3): a.fx(b(5.5) + 0.55 + i * 0.4, "tap")
    a.jump(b(5.5) + 1.45, b(5.5) + 1.85, "badge", 200); a.do(b(5.5) + 1.75, "mood flex"); a.fx(b(5.5) + 1.75, "sparkle")
    a.jump(b(7) - 0.2, b(7) + 0.5, "hero", 240); a.do(b(7) + 0.5, "mood love"); a.do(b(7) + 1.4, "resize 0.8"); a.do(b(8), "wave")
    a.write(b(8) + 0.5)


def reasons():
    a = Ad("reasons", 118, "pop", ["F", "C", "Dm7", "Bbmaj7", "F", "C", "Dm7", "Bbmaj7", "F"], theme="sticker")
    b = a.b
    a.scene("title", 0, "3 reasons Nourlo beats your notes app", ["nourlo"], titleSize=110, titleTop=260)
    a.scene("listicle", b(1.5), "", items=[["🗓️", "It plans your whole week"], ["🛒", "It shops to your budget"], ["💪", "It cheers every PR"]], every=round(b(1), 3), cut="slide")
    a.scene("title", b(5.5), "Your notes app could never", ["never"], "zoom", titleTop=300)
    a.at(0, (540, 1300, 700)); a.do(0, "mood cheeky"); a.do(1.0, "hop")
    a.jump(b(1.5) - 0.2, b(1.5) + 0.4, (850, 1560, 400), 260)
    for i in range(3):
        t = b(1.5) + 0.2 + i * b(1)
        a.fx(t, "pop"); a.do(t + 0.1, "hop")
    a.do(b(1.5) + 0.3 + 2 * b(1), "mood flex"); a.fx(b(1.5) + 0.4 + 2 * b(1), "sparkle")
    a.jump(b(5.5) - 0.2, b(5.5) + 0.5, "talk", 240); a.do(b(5.5) + 0.5, "mood cheeky"); a.say(b(5.5) + 0.9, b(6.5) + 0.6, "Told you 😌")
    a.do(b(7), "mood love", "wave")
    a.write(b(7) + 0.6)


def pov():
    a = Ad("pov", 86, "lofi", ["Dm9", "G9", "Cmaj7", "Am7", "Dm9", "G9", "Cmaj7", "Cmaj7"])
    b = a.b
    a.scene("title", 0, "POV: it's Sunday and the fridge is empty", ["empty"], titleSize=100, titleTop=260)
    a.scene("groceries", b(1.5), "Nourlo writes the list", ["list"], "slide")
    a.scene("plan", b(3), "and the whole week", ["week"], "slide")
    a.scene("title", b(4.5), "Monday you is grateful", ["grateful"], "rise", titleTop=300)
    a.at(0, "big"); a.do(0, "mood worried", "look 0 -1"); a.do(2.2, "mood happy", "look none")
    a.say(1.6, b(1.5) - 0.2, "I got you 🫡")
    a.jump(b(1.5) - 0.2, b(1.5) + 0.4, "right", 220)
    for i in range(5): a.fx(b(1.5) + 0.35 + i * 0.22, "coin")
    a.walk(b(3) - 0.4, b(3) + 0.6, "left"); a.fx(b(3) + 0.15, "type", 22, 30); a.fx(b(3) + 1.0, "click"); a.do(b(3) + 1.2, "hop")
    a.jump(b(4.5) - 0.2, b(4.5) + 0.5, "talk", 220); a.do(b(4.5) + 0.5, "mood love"); a.say(b(4.5) + 1.0, b(5.5) + 0.4, "You're welcome 💕", "left")
    a.write(b(5.5) + 0.6)


def catch():
    a = Ad("catch", 116, "pop", ["Ab", "Eb", "Fm7", "Db", "Ab", "Eb", "Fm7", "Db", "Ab"], theme="sunset")
    b = a.b
    a.scene("title", 0, "Every bite, caught", ["caught"], titleSize=124)
    a.scene("day", b(3.5), "and counted", ["counted"], "rise")
    a.scene("title", b(5), "Food logging that's actually fun", ["fun"], "zoom", titleTop=300)
    foods = ["🍳", "🥑", "🍌", "🍗", "🥦", "🍓", "🍚", "🥛", "🍎", "🧀"]
    every = 0.55
    a.overlay("rain", 0.6, items=foods, every=every)
    xs = [300, 760, 420, 820, 250, 640, 860, 380, 700, 540]
    a.at(0, (540, 1500, 500)); a.do(0, "mood happy", "look 0 -1")
    for i, x in enumerate(xs):
        land = 0.6 + 0.9 + i * every
        a.walk(land - 0.42, land - 0.02, (x, 1500, 500)); a.fx(land, "pop")
        if i % 3 == 2: a.do(land, "resize 0.5")
    a.do(b(3.5) - 0.2, "mood love", "look none")
    a.jump(b(3.5) - 0.1, b(3.5) + 0.5, "mid", 200)
    a.jump(b(5) - 0.2, b(5) + 0.5, "hero", 240); a.do(b(5) + 0.5, "mood celebrate"); a.do(b(6), "mood love", "wave")
    a.write(b(6) + 0.7)


def runner():
    a = Ad("runner", 128, "disco", ["Fm9", "Bbm9", "Eb9", "Abmaj7", "Fm9", "Bbm9", "Eb9", "Abmaj7", "Fm9"], theme="dark")
    b = a.b
    a.scene("title", 0, "Nourlo's on a roll", ["roll"], titleSize=120)
    speed, y = 360, 1300
    run_end = b(4)
    a.scene("track", 1.2, "Breakfast, lunch, snack…", ["snack"], items=["🥚", "🍌", "🥦", "🍗", "🍚", "🥑", "🍓", "🥛", "🍎", "🧀"], speed=speed, y=y, until=run_end, cut="dissolve")
    a.scene("workout", b(4), "Then hits a PR", ["pr"], "slide")
    a.scene("title", b(6), "Unstoppable. Like you.", ["unstoppable"], "zoom", titleTop=300)
    size = 380
    top = y - 10 - size * 0.36
    a.at(0, "offL"); a.do(0, "mood happy")
    a.walk(0.1, 1.2, (400, 1500, 460))
    # platform i passes x=400 at 1.2 + (780 + i*360)/speed
    t = 1.2 + 780 / speed
    a.jump(t - 0.55, t - 0.05, (400, top, size), 260); a.fx(t - 0.05, "pop")
    for i in range(1, 8):
        ti = 1.2 + (780 + i * 360) / speed
        if ti > run_end - 0.3: break
        a.jump(ti - 0.7, ti - 0.12, (400 + (8 if i % 2 else -8), top, size), 220)
        if i % 3 == 0: a.do(ti - 0.1, "mood celebrate")
        if i % 3 == 1: a.do(ti - 0.1, "mood happy")
    a.jump(b(4) - 0.2, b(4) + 0.4, "right", 260)
    for i in range(3): a.fx(b(4) + 0.55 + i * 0.4, "tap")
    a.jump(b(4) + 1.45, b(4) + 1.85, "badge", 200); a.do(b(4) + 1.75, "mood flex"); a.fx(b(4) + 1.75, "sparkle")
    a.jump(b(6) - 0.2, b(6) + 0.5, "hero", 240); a.do(b(6) + 0.6, "resize 0.9"); a.do(b(6) + 1.6, "hop"); a.do(b(7) + 0.2, "mood love", "wave")
    a.write(b(7) + 0.5)


def quiz():
    a = Ad("quiz", 104, "song", ["Fmaj7", "Dm9", "Bbmaj7", "Csus", "Fmaj7", "Am7", "Bbmaj7", "Csus", "Fadd9"], (1, 8), theme="paper")
    b = a.b
    a.scene("quiz", 0, "Which lunch fits €3?", ["€3"], options=[["🍔", "Takeaway burger"], ["🍛", "Chicken, rice & veg"]], pick=1, pickAt=round(b(1.5), 3))
    a.scene("groceries", b(2.5), "Nourlo shops smart", ["smart"], "slide")
    a.scene("budget", b(4), "and keeps change", ["change"], "slide")
    a.scene("title", b(5.5), "Eat well for less", ["less"], "zoom", titleTop=300)
    a.at(0, (540, 1500, 440)); a.do(0, "mood thinking", "look -0.6 -0.8"); a.do(1.3, "look 0.6 -0.8"); a.do(2.3, "look -0.6 -0.8")
    a.do(b(1.5), "mood happy", "look 0.6 -0.8"); a.fx(b(1.5), "success"); a.do(b(1.5) + 0.2, "hop")
    a.say(b(1.5) + 0.5, b(2.5) - 0.2, "€2.80 and tastier 😋", "left")
    a.jump(b(2.5) - 0.2, b(2.5) + 0.4, "left", 220)
    for i in range(5): a.fx(b(2.5) + 0.35 + i * 0.22, "coin")
    a.walk(b(4) - 0.4, b(4) + 0.6, "right"); a.do(b(4) + 1.3, "mood love"); a.fx(b(4) + 1.3, "sparkle")
    a.jump(b(5.5) - 0.2, b(5.5) + 0.5, "hero", 220); a.do(b(5.5) + 0.5, "mood happy"); a.do(b(6.5), "wave")
    a.write(b(6.5) + 0.6)


def versus():
    a = Ad("versus", 132, "garage", ["Bbmaj9", "Am7", "Gm9", "C13", "Bbmaj9", "Am7", "Gm9", "C13", "Fmaj9", "Fmaj9"])
    b = a.b
    a.scene("versus", 0, "Your week", ["week"], left=["Takeaway again", "No idea what's in the fridge", "Over budget", "Skipped the gym"],
            right=["Meals planned", "Cooked from stock", "€1.40 to spare", "New PR"], titleTop=170)
    a.scene("plan", b(3), "Nourlo does the thinking", ["thinking"], "slide")
    a.scene("timer", b(5), "You do the living", ["living"], "slide")
    a.scene("title", b(7), "Be the right side", ["right"], "zoom", titleTop=300)
    a.at(0, (900, 1650, 380)); a.do(0, "mood worried")
    a.walk(1.0, 2.2, (540, 1650, 380)); a.do(2.2, "mood happy", "hop"); a.fx(2.2, "success")
    a.jump(b(3) - 0.2, b(3) + 0.4, "left", 260); a.fx(b(3) + 0.15, "type", 22, 30); a.fx(b(3) + 1.0, "click"); a.do(b(3) + 1.2, "hop")
    a.jump(b(5) - 0.2, b(5) + 0.4, "low", 240); a.do(b(5) + 0.5, "walk 1.3"); a.do(b(7) - 0.3, "walk 0"); a.fx(b(5) + 0.9, "beep")
    a.jump(b(7) - 0.2, b(7) + 0.5, "hero", 220); a.do(b(7) + 0.5, "mood flex"); a.do(b(8), "mood love", "wave")
    a.write(b(8) + 0.5)


def wake():
    a = Ad("wake", 90, "lofi", ["Ebmaj7", "Cm7", "Fm9", "Bb9", "Ebmaj7", "Cm7", "Fm9", "Ebmaj7"])
    b = a.b
    a.scene("notifs", 0, "", items=[["Breakfast?", "Two taps and it's logged.", "🍳"], ["Leg day", "30 min, your stats, ready to go.", "🦵"],
                                     ["€6.40 left", "Enough for Friday's dinner.", "💸"], ["New record!", "Bench press, 62.5 kg.", "🏆"]])
    a.scene("title", b(3), "Nourlo keeps you on track", ["track"], "rise", titleTop=300)
    a.at(0, (860, 2150, 520)); a.do(0, "mood sleepy")
    a.glide(1.0, 1.8, (860, 1720, 520)); a.do(1.8, "mood happy", "look -0.5 -1")
    for i in range(4): a.fx(0.5 + i * 0.6, "beep")
    a.do(0.5 + 3 * 0.6 + 0.2, "mood flex")
    a.jump(b(3) - 0.2, b(3) + 0.5, "hero", 240); a.do(b(3) + 0.5, "mood love"); a.do(b(4), "wave")
    a.write(b(4) + 0.4)


def countdown():
    a = Ad("countdown", 120, "disco", ["Am9", "Am9", "Dm9", "G9", "Cmaj7", "Fmaj7", "Dm9", "E7", "Am9"], (2, 8), theme="sticker")
    b = a.b
    a.scene("countdown", 0, "", every=1.0, then="FLEX!")
    a.scene("workout", b(2), "Log the sets", ["sets"], "slide")
    a.scene("progress", b(4), "See the gains", ["gains"], "slide")
    a.scene("title", b(6), "Nourlo spots you", ["spots"], "zoom", titleTop=300)
    a.at(0, (540, 1450, 640)); a.do(0, "mood happy")
    for i in range(3): a.do(i + 0.05, "resize -0.6"); a.fx(i, "beep")
    a.do(3.0, "mood flex"); a.fx(3.0, "sparkle"); a.do(3.6, "resize 0.9")
    a.jump(b(2) - 0.2, b(2) + 0.4, "right", 260)
    for i in range(3): a.fx(b(2) + 0.55 + i * 0.4, "tap")
    a.jump(b(2) + 1.45, b(2) + 1.85, "badge", 200); a.do(b(2) + 1.75, "mood celebrate"); a.fx(b(2) + 1.75, "sparkle")
    a.walk(b(4) - 0.4, b(4) + 0.6, "left"); a.do(b(4) + 1.4, "mood flex"); a.fx(b(4) + 1.25, "success")
    a.jump(b(6) - 0.2, b(6) + 0.5, "hero", 240); a.do(b(6) + 0.5, "mood flex"); a.do(b(6) + 1.4, "resize 0.8"); a.do(b(7) + 0.2, "mood love", "wave")
    a.write(b(7) + 0.5)


def hello():
    # Nourlo introduces itself, straight to camera.
    a = Ad("hello", 100, "song", ["Fmaj7", "Am7", "Dm9", "Bbmaj7", "Csus", "Fmaj7", "Am7", "Bbmaj7", "Fadd9"], (2, 8))
    b = a.b
    a.scene("title", 0, "", cut="none")
    a.scene("end", 0)  # placeholder removed below
    a.scenes.pop()
    a.overlay("float", 0, items=["🍓", "🥑", "🍌", "🥦", "🍳", "🫐", "🥕", "🍎", "🥛", "🍚"])
    a.at(0, "offR"); a.walk(0.2, 1.6, (540, 1250, 760)); a.do(1.7, "mood happy", "wave")
    lines = [("Hi! I'm Nourlo 👋", "happy"), ("I plan your meals", "thinking"), ("I fit your groceries to your budget", "love"),
             ("I count every calorie", "happy"), ("I even lift 💪", "flex"), ("Download me?", "cheeky")]
    t = 1.8
    for text, mood in lines:
        a.do(t, f"mood {mood}"); a.say(t, t + 1.7, text, "right" if mood != "flex" else "left")
        if mood == "flex": a.do(t + 0.6, "resize 0.9")
        if mood == "thinking": a.do(t, "look -0.6 -0.8"); a.do(t + 1.5, "look none")
        t += 2.0
    a.do(t, "mood love")
    a.write(t + 0.2)


def cookbook():
    a = Ad("cookbook", 92, "lofi", ["Gmaj7", "Em7", "Am9", "D9", "Gmaj7", "Em7", "Am9", "Gmaj7"], theme="paper")
    b = a.b
    a.scene("kinetic", 0, words=["1,500", "recipes", "offline", "free"], every=round(b(0.5), 3), colors=["#C2410C", "#111114", "#111114", "#C2410C"])
    a.scene("stock", b(2), "Cook what you have", ["have"], "slide")
    a.scene("recipe", b(4), "Nutrition, worked out", ["worked"], "rise")
    a.scene("title", b(6), "Dinner, solved", ["solved"], "zoom", titleTop=300)
    a.overlay("float", 0, items=["🍅", "🧄", "🥕", "🍋", "🌶️", "🥔", "🧅", "🥬", "🍄", "🫑"])
    a.at(0, (540, 1500, 520)); a.do(0, "mood happy"); a.do(b(0.5), "hop"); a.do(b(1), "mood love"); a.do(b(1.5), "hop")
    a.jump(b(2) - 0.1, b(2) + 0.5, (220, 800, 380), 300); a.fx(b(2) + 0.5, "pop")
    a.jump(b(2) + 0.9, b(2) + 1.4, (540, 800, 380), 200); a.fx(b(2) + 1.4, "pop")
    a.jump(b(2) + 1.8, b(2) + 2.3, (860, 800, 380), 200); a.fx(b(2) + 2.3, "pop")
    a.jump(b(3) + 0.4, b(3) + 1.0, "left", 220); a.do(b(3) + 1.0, "mood love")
    a.glide(b(4) - 0.3, b(4) + 0.4, "right"); a.fx(b(4) + 1.55, "tap"); a.fx(b(4) + 1.8, "success"); a.do(b(4) + 1.8, "mood celebrate")
    a.jump(b(6) - 0.2, b(6) + 0.5, "talk", 220); a.do(b(6) + 0.5, "mood happy"); a.say(b(6) + 0.9, b(7), "Shakshuka tonight? 🍳"); a.do(b(7) + 0.2, "wave")
    a.write(b(7) + 0.6)


def challenge():
    a = Ad("challenge", 120, "pop", ["Bb", "F", "Gm7", "Eb", "Bb", "F", "Gm7", "Eb", "Bb"], theme="sunset")
    b = a.b
    a.scene("kinetic", 0, words=["€40", "7 days", "21 meals", "Challenge?"], every=round(b(0.5), 3), colors=["#FFFFFF", "#FFFFFF", "#FFFFFF", "#111114"])
    a.scene("groceries", b(2), "Accepted.", ["accepted"], "zoom")
    a.scene("budget", b(4), "€1.40 to spare", ["spare"], "slide")
    a.scene("title", b(6), "Challenge complete", ["complete"], "zoom", titleTop=300)
    a.at(0, (540, 1500, 540)); a.do(0, "mood worried")
    for i in range(4): a.fx(i * b(0.5), "pop"); a.do(i * b(0.5) + 0.05, "resize 0.4")
    a.do(b(1.6), "mood cheeky"); a.say(b(1.6), b(2) + 0.3, "Easy 😎")
    a.jump(b(2) - 0.1, b(2) + 0.5, "right", 240)
    for i in range(5): a.fx(b(2) + 0.35 + i * 0.22, "coin")
    a.walk(b(4) - 0.4, b(4) + 0.6, "left"); a.do(b(4) + 1.3, "mood love"); a.fx(b(4) + 1.3, "sparkle")
    a.jump(b(6) - 0.2, b(6) + 0.5, "hero", 240); a.do(b(6) + 0.5, "mood celebrate"); a.do(b(7) + 0.2, "mood flex")
    a.write(b(7) + 0.6)


def tour():
    # The real app on a phone; Nourlo stands beside it and explains.
    a = Ad("tour", 128, "garage", ["Bbmaj9", "Am7", "Gm9", "C13", "Bbmaj9", "Am7", "Gm9", "C13", "Bbmaj9", "Am7", "Gm9", "C13", "Fmaj9", "Fmaj9"], theme="dark")
    b = a.b
    a.scene("title", 0, "Take a look inside", ["inside"], titleSize=120)
    shots = [("Say it. It's logged.", ["logged"], 41.2), ("Plans from your kitchen", ["kitchen"], 66.5), ("Cook what you have", ["have"], 82.4),
             ("Groceries on budget", ["budget"], 111.6), ("Train anywhere", ["anywhere"], 120.6)]
    lines = ["Two eggs and a banana? Done.", "Missing something? One tap.", "1,500 recipes for your stock", "Fitted to your budget", "Workouts sized to your time"]
    a.at(0, "big"); a.do(0, "mood happy"); a.do(0.8, "wave")
    for i, (label, mark, src) in enumerate(shots):
        t0 = b(1 + i * 2)
        a.scene("phone", t0, label, mark, "slide" if i else "zoom", **{"from": src, "top": 330, "scale": 0.8}, titleTop=150, titleSize=80)
        spot = (930, 1640, 360) if i % 2 == 0 else (150, 1640, 360)
        a.jump(t0 - 0.25, t0 + 0.35, spot, 300)
        a.do(t0 + 0.4, "look %s -0.6" % ("-0.9" if i % 2 == 0 else "0.9"))
        a.say(t0 + 0.6, t0 + b(2) - 0.4, lines[i], "left" if i % 2 == 0 else "right")
        if i == 4: a.do(t0 + 1.2, "mood flex")
    a.scene("title", b(11), "Meet Nourlo", ["nourlo"], "zoom", titleTop=300, titleSize=130)
    a.jump(b(11) - 0.2, b(11) + 0.5, "hero", 260); a.do(b(11) + 0.5, "mood love", "look none"); a.do(b(12), "wave")
    a.write(b(12) + 0.4)


FIRST = (gym, kitchen, budget, voice, plan, day, buddy, morning)
SECOND = (tour, neon, reasons, pov, catch, runner, quiz, versus, wake, countdown, hello, cookbook, challenge)

if __name__ == "__main__":
    import sys
    OUT.mkdir(exist_ok=True)
    wanted = set(sys.argv[1:])
    for make in FIRST + SECOND:
        if not wanted or make.__name__ in wanted:
            make()
