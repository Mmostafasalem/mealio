"""Reads Wikibooks Cookbook recipe pages (wikitext) into plain data: summary,
ingredient lines (quantity, unit, the linked ingredient page, the text) and steps."""
import html
import re

FRACTIONS = {"½": 0.5, "¼": 0.25, "¾": 0.75, "⅓": 1 / 3, "⅔": 2 / 3, "⅛": 0.125, "⅜": 0.375, "⅝": 0.625, "⅞": 0.875, "⅕": 0.2}
UNITS = {
    "cup": "cup", "cups": "cup", "c": "cup", "tablespoon": "tbsp", "tablespoons": "tbsp", "tbsp": "tbsp", "tbs": "tbsp", "tbl": "tbsp", "t": "tbsp",
    "teaspoon": "tsp", "teaspoons": "tsp", "tsp": "tsp", "ounce": "oz", "ounces": "oz", "oz": "oz", "pound": "lb", "pounds": "lb", "lb": "lb", "lbs": "lb",
    "gram": "g", "grams": "g", "g": "g", "gr": "g", "kilogram": "kg", "kilograms": "kg", "kg": "kg", "milliliter": "ml", "milliliters": "ml",
    "millilitre": "ml", "millilitres": "ml", "ml": "ml", "liter": "l", "liters": "l", "litre": "l", "litres": "l", "l": "l", "dl": "dl",
    "clove": "clove", "cloves": "clove", "can": "can", "cans": "can", "tin": "can", "tins": "can", "pinch": "pinch", "dash": "pinch",
    "slice": "slice", "slices": "slice", "stick": "stick", "sticks": "stick", "bunch": "bunch", "bunches": "bunch", "handful": "handful", "sprig": "sprig", "sprigs": "sprig",
    "piece": "piece", "pieces": "piece", "fl oz": "floz", "pint": "pint", "pints": "pint", "quart": "quart", "quarts": "quart",
    "package": "package", "packages": "package", "pkg": "package", "head": "head", "heads": "head", "stalk": "stalk", "stalks": "stalk",
    "large": "large", "medium": "medium", "small": "small", "big": "large",
    "cl": "cl", "ball": "ball", "ea": "piece", "each": "piece", "bulb": "piece", "fillet": "piece", "fillets": "piece", "chop": "piece", "chops": "piece",
    "breast": "piece", "breasts": "piece", "thigh": "piece", "thighs": "piece", "leg": "piece", "legs": "piece",
}
SECTION_ING = re.compile(r"^==+\s*ingredients?\b.*?==+\s*$", re.I | re.M)
SECTION_STEPS = re.compile(r"^==+\s*(procedure|directions?|method|instructions?|preparation|steps)\b.*?==+\s*$", re.I | re.M)
TOP_SECTION = re.compile(r"^==[^=].*?==\s*$", re.M)


def unlink(text):
    text = html.unescape(text)
    text = re.sub(r"\[\[(?:Image|File|Category):[^\]]*\]\]", "", text, flags=re.I)
    text = re.sub(r"\[\[[^\]|]*\|([^\]]*)\]\]", r"\1", text)
    text = re.sub(r"\[\[([^\]]*)\]\]", lambda m: m.group(1).split(":")[-1], text)
    text = re.sub(r"\[https?://\S+ ([^\]]*)\]", r"\1", text)
    text = re.sub(r"'''?", "", text)
    text = re.sub(r"<ref[^>]*>.*?</ref>|<ref[^/]*/>", "", text, flags=re.S)
    text = re.sub(r"<[^>]+>", "", text)
    text = re.sub(r"\{\{[^}]*\}\}", "", text)
    return re.sub(r"\s+", " ", text).strip()


def summary(text):
    m = re.search(r"\{\{\s*recipe\s*summary(.*?)\}\}", text, re.I | re.S)
    out = {}
    if m:
        for line in m.group(1).split("|"):
            if "=" in line:
                k, v = line.split("=", 1)
                out[k.strip().lower()] = unlink(v)
    return out


def section(text, header):
    m = header.search(text)
    if not m:
        return ""
    rest = text[m.end():]
    nxt = TOP_SECTION.search(rest)
    level = len(re.match(r"^(=+)", m.group(0)).group(1))
    # stop at the next heading of the same or a higher level
    for h in re.finditer(r"^(=+)[^=].*?=+\s*$", rest, re.M):
        if len(h.group(1)) <= level:
            return rest[:h.start()]
    return rest


def number(text):
    """Leading quantity: '2', '1/2', '2 ½', '1-2' (mean), '1.5'. Returns (value, rest)."""
    t = text.strip()
    for k, v in FRACTIONS.items():
        t = re.sub(r"(\d)\s*" + k, lambda m: f"{m.group(1)} {v}", t)
        t = t.replace(k, f"{v}")
    m = re.match(r"^(\d+(?:\.\d+)?)(?:\s+(\d+(?:\.\d+)?)/(\d+(?:\.\d+)?)|\s*/\s*(\d+)|\s+(0\.\d+))?\s*(?:(?:-|–|to)\s*(\d+(?:\.\d+)?(?:/\d+)?))?", t)
    if not m:
        return None, text
    v = float(m.group(1))
    if m.group(2):
        v += float(m.group(2)) / float(m.group(3))
    elif m.group(4):
        v = v / float(m.group(4))
    elif m.group(5):
        v += float(m.group(5))
    if m.group(6):
        hi = m.group(6)
        hi = float(hi.split("/")[0]) / float(hi.split("/")[1]) if "/" in hi else float(hi)
        if hi > v:
            v = (v + hi) / 2
    return v, t[m.end():]


def ingredient(line):
    raw = html.unescape(line.lstrip("*#:; ").strip())
    links = [l.split("|")[0].strip() for l in re.findall(r"\[\[([^\]]+)\]\]", raw)]
    targets = [l.split(":", 1)[1].strip() if l.lower().startswith("cookbook:") else l for l in links]
    text = unlink(raw)
    lead = re.sub(r"^(about|approximately|approx\.?|around|roughly|juice of|zest of|the juice of|the zest of)\s+", "", text, flags=re.I)
    qty, rest = number(lead)
    unit = None
    rest = re.sub(r"^\s*(scant|heaped|heaping|level|generous|good|rounded|about|approximately|approx\.?)\s+", "", rest, flags=re.I)
    m = re.match(r"^\(?\s*([a-zA-Z]+(?:\s+oz)?)\.?\)?\s+", rest + " ")
    if m and m.group(1).lower() in UNITS:
        unit = UNITS[m.group(1).lower()]
        rest = rest[m.end():] if m.end() <= len(rest) else ""
    # A bracket after a measure restates the whole amount: "2 lb (900 g)", "1 cup (240 ml)".
    # Before a container it is the container's size: "1 (15 oz) can". Before a
    # food it is the size of one piece: "2 (200 g) chicken breasts".
    size = re.match(r"^\(\s*(?:about\s+|approx\.?\s+)?(\d+(?:\.\d+)?)\s*(?:[-–]\s*\d+(?:\.\d+)?\s*)?"
                    r"(oz|ounces?|g|grams?|ml|kg|lbs?|pounds?|l|litres?|liters?)\b\.?[^)]*\)\s*"
                    r"((?:cans?|packages?|tins?|jars?|bags?|box(?:es)?|packets?)\b)?", rest, re.I)
    sized, given = None, None
    if size:
        amount, u = float(size.group(1)), size.group(2).lower()
        u = {"ounce": "oz", "ounces": "oz", "gram": "g", "grams": "g", "lbs": "lb", "pound": "lb", "pounds": "lb",
             "litre": "l", "litres": "l", "liter": "l", "liters": "l"}.get(u, u)
        # After a weight or volume ("15 oz (425 g) can", "2 lb (900 g)") the bracket restates the
        # whole amount, whatever follows; only a count ("2 (15 oz) cans") makes it a size each.
        measured = unit in ("g", "kg", "oz", "lb", "ml", "l", "dl", "cl", "cup", "tbsp", "tsp", "floz", "pint", "quart")
        if measured or (unit and not size.group(3)):
            given = (amount, u)
        else:
            sized = (amount, u)
            if size.group(3):
                unit = "can" if size.group(3).lower().startswith(("can", "tin", "jar")) else "package"
        rest = rest[size.end():]
    unit_targets = {"cup", "tablespoon", "teaspoon", "pinch", "clove", "ounce", "pound", "gram", "liter", "litre", "milliliter", "dash", "slice"}
    food_targets = [t for t in targets if t.lower().rstrip("s") not in unit_targets and t.lower() not in UNITS]
    name = re.sub(r"\(.*?\)", "", rest)
    name = re.split(r",| - | – |;| or ", name)[0]
    name = re.sub(r"^(of|a|an)\s+", "", name.strip(), flags=re.I).strip(" .:")
    return {"raw": text, "qty": qty, "unit": unit, "size": sized, "given": given, "link": food_targets[0] if food_targets else None,
            "linkText": food_targets, "name": name.lower()}


def parse(title, page):
    text = page["text"]
    ing_block = section(text, SECTION_ING)
    steps_block = section(text, SECTION_STEPS)
    ings = [ingredient(l) for l in ing_block.splitlines() if l.strip().startswith("*")]
    steps = [unlink(re.sub(r"^#+[*:]?\s*", "", l)) for l in steps_block.splitlines() if l.strip().startswith("#")]
    steps = [s for s in steps if len(s) > 3]
    return {"title": title.split(":", 1)[1], "summary": summary(text), "ingredients": ings, "steps": steps,
            "categories": [c.split(":", 1)[1] for c in page.get("categories", [])], "timestamp": page.get("timestamp")}
