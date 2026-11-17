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
        "top": (540, -400, 520), "badge": (800, 1300, 440)}


class Ad:
    def __init__(self, id, bpm, style, bars, drums=(1, None)):
        self.id, self.bpm, self.bar = id, bpm, 240 / bpm
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

    def fx(self, t, kind, *args):
        self.sfx.append([round(t, 3), kind, *args])

    def write(self, end_at, tail=2.6):
        self.scene("end", end_at)
        data = {"id": self.id, "dur": round(end_at + tail, 3), "bpm": self.bpm, "music": self.music,
                "scenes": self.scenes, "path": self.path, "rig": self.rig, "sfx": self.sfx}
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


if __name__ == "__main__":
    OUT.mkdir(exist_ok=True)
    for make in (gym, kitchen, budget, voice, plan, day, buddy, morning):
        make()
