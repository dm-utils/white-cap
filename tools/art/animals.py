"""Builds the cutout animals from code: one SVG per part plus a rig file (stdlib only).

Change a number, run the script, get the animal. Part names are stable (game code binds to them):
body, head, eye_l, eye_r, mouth, claw_l, claw_r, limb_fl, limb_fr, limb_bl, limb_br, limb_top, tail, shell, accessory.
Every part is drawn in the same 200 x 200 animal space, so a part's pivot is simply a point in that space.
Each part's SVG is then cropped to its own bounds (viewBox) and the rig records where that box sits ("box"),
so an eye costs an eye's worth of texture, not a whole canvas (budget: one animal <= 1024 x 1024).
Colours come from data/palette.json; a look (skin) is the same parts with another palette.

Output:  assets/animals/<id>/<part>.svg   and   data/rigs/<id>.json
Usage:   python -I tools/art/animals.py
"""
import json
import math
import os
import re

ROOT = os.path.join(os.path.dirname(__file__), "..", "..")
PALETTE = json.load(open(os.path.join(ROOT, "data", "palette.json"), encoding="utf-8"))
SIZE = 200
ORIGIN = (100, 172)  # the animal's feet: where it stands on the ground
STROKE = 7  # thick outline (styleguide: animals pop from the island)


def svg(body: str, box: tuple) -> str:
    x, y, w, h = box
    return (f'<svg xmlns="http://www.w3.org/2000/svg" width="{w}" height="{h}" viewBox="{x} {y} {w} {h}">'
            f'<g stroke-linejoin="round" stroke-linecap="round">{body}</g></svg>\n')


def _attr(el: str, name: str, default: float = 0.0) -> float:
    m = re.search(rf'\b{name}="(-?[\d.]+)"', el)
    return float(m.group(1)) if m else default


def _path_points(d: str) -> list:
    """Every point a path visits plus its control points (a curve stays inside them); arcs as their radius box."""
    pts, x, y, sx, sy = [], 0.0, 0.0, 0.0, 0.0
    for cmd, args in re.findall(r"([MLQAZmlqaz])([^MLQAZmlqaz]*)", d):
        n = [float(v) for v in re.findall(r"-?[\d.]+", args)]
        if cmd in "Zz":
            x, y = sx, sy
            continue
        step = {"M": 2, "L": 2, "Q": 4, "A": 7}[cmd.upper()]
        rel = cmd.islower()
        for i in range(0, len(n), step):
            a = n[i:i + step]
            if cmd.upper() == "A":
                ex, ey = (x + a[5], y + a[6]) if rel else (a[5], a[6])
                r = max(a[0], a[1])
                pts += [(x - r, y - r), (x + r, y + r), (ex - r, ey - r), (ex + r, ey + r)]
                x, y = ex, ey
                continue
            coords = [(a[j] + (x if rel else 0), a[j + 1] + (y if rel else 0)) for j in range(0, step, 2)]
            pts += coords
            x, y = coords[-1]
            if cmd.upper() == "M" and i == 0:
                sx, sy = x, y
    return pts


def bounds(body: str) -> tuple:
    """Integer box (x, y, w, h) around everything in a part, strokes included, plus a 2-unit margin."""
    lo_x = lo_y = 1e9
    hi_x = hi_y = -1e9
    for el in re.findall(r"<(?:ellipse|circle|path)[^>]*>", body):
        half = _attr(el, "stroke-width") / 2 if "stroke=" in el else 0.0
        if el.startswith("<path"):
            pts = _path_points(re.search(r'\bd="([^"]+)"', el).group(1))
        else:
            cx, cy = _attr(el, "cx"), _attr(el, "cy")
            rx = _attr(el, "r") if el.startswith("<circle") else _attr(el, "rx")
            ry = _attr(el, "r") if el.startswith("<circle") else _attr(el, "ry")
            pts = [(cx - rx, cy - ry), (cx + rx, cy + ry)]
        for px, py in pts:
            lo_x, lo_y = min(lo_x, px - half), min(lo_y, py - half)
            hi_x, hi_y = max(hi_x, px + half), max(hi_y, py + half)
    x0, y0 = math.floor(lo_x) - 2, math.floor(lo_y) - 2
    return x0, y0, math.ceil(hi_x) + 2 - x0, math.ceil(hi_y) + 2 - y0


def eye(x, y, r, look=(2, 1)):
    o, w, p = PALETTE["outline"], PALETTE["eye"], PALETTE["pupil"]
    return (f'<circle cx="{x}" cy="{y}" r="{r}" fill="{w}" stroke="{o}" stroke-width="{STROKE * 0.7:.1f}"/>'
            f'<circle cx="{x + look[0]}" cy="{y + look[1]}" r="{r * 0.48:.1f}" fill="{p}"/>'
            f'<circle cx="{x + look[0] - r * 0.25:.1f}" cy="{y + look[1] - r * 0.25:.1f}" r="{r * 0.14:.1f}" fill="#fff"/>')


def crab(c):
    o = PALETTE["outline"]
    legs = lambda side: "".join(
        f'<path d="M{100 + side * dx} {124 + i * 10} L{100 + side * (dx + 34)} {150 + i * 14}" stroke="{o}" stroke-width="{STROKE}" fill="none"/>'
        for i, dx in enumerate((48, 42)))
    claw = lambda side: (
        f'<path d="M{100 + side * 50} 112 L{100 + side * 66} 86" stroke="{o}" stroke-width="{STROKE}" fill="none"/>'
        f'<path d="M{100 + side * 70} 50 a26 26 0 1 {1 if side > 0 else 0} 0 52 l{-side * 6} -14 a12 12 0 1 {0 if side > 0 else 1} 0 -24 z" '
        f'fill="{c["base"]}" stroke="{o}" stroke-width="{STROKE}"/>')
    stalk = lambda x: f'<path d="M{x} 92 L{x} 62" stroke="{o}" stroke-width="{STROKE}" fill="none"/>' + eye(x, 54, 14)
    return {
        "limb_bl": (legs(-1), (54, 128), -2),
        "limb_br": (legs(1), (146, 128), -2),
        "body": (f'<ellipse cx="100" cy="122" rx="64" ry="44" fill="{c["base"]}" stroke="{o}" stroke-width="{STROKE}"/>'
                 f'<ellipse cx="100" cy="136" rx="44" ry="18" fill="{c["shade"]}"/>'
                 f'<circle cx="74" cy="106" r="6" fill="{c["accent"]}"/><circle cx="128" cy="102" r="4" fill="{c["accent"]}"/>', (100, 160), 0),
        "eye_l": (stalk(84), (84, 94), 1),
        "eye_r": (stalk(116), (116, 94), 1),
        "mouth": (f'<path d="M88 128 Q100 138 112 128" stroke="{o}" stroke-width="{STROKE * 0.7:.1f}" fill="none"/>', (100, 130), 1),
        "claw_l": (claw(-1), (50, 112), 2),
        "claw_r": (claw(1), (150, 112), 2),
    }


def octopus(c):
    o = PALETTE["outline"]

    def tentacle(x0, bend):
        d = f"M{x0} 118 Q{x0 + bend} 150 {x0 + bend * 0.4:.0f} 176"
        return (f'<path d="{d}" stroke="{o}" stroke-width="{STROKE + 16}" fill="none"/>'
                f'<path d="{d}" stroke="{c["base"]}" stroke-width="16" fill="none"/>')
    return {
        "limb_bl": (tentacle(64, -22), (64, 118), -2),
        "limb_br": (tentacle(136, 22), (136, 118), -2),
        "limb_fl": (tentacle(88, -10), (88, 122), -1),
        "limb_fr": (tentacle(112, 10), (112, 122), -1),
        "body": (f'<ellipse cx="100" cy="86" rx="62" ry="58" fill="{c["base"]}" stroke="{o}" stroke-width="{STROKE}"/>'
                 f'<ellipse cx="100" cy="112" rx="44" ry="18" fill="{c["shade"]}"/>'
                 f'<circle cx="72" cy="56" r="8" fill="{c["accent"]}"/><circle cx="126" cy="48" r="5" fill="{c["accent"]}"/>', (100, 140), 0),
        "eye_l": (eye(82, 88, 15), (82, 88), 1),
        "eye_r": (eye(118, 88, 15), (118, 88), 1),
        "mouth": (f'<path d="M90 114 Q100 122 110 114" stroke="{o}" stroke-width="{STROKE * 0.7:.1f}" fill="none"/>', (100, 116), 1),
    }


def gull(c):
    o = PALETTE["outline"]
    leg = lambda x: (f'<path d="M{x} 150 L{x - 2} 172" stroke="{c["legs"]}" stroke-width="{STROKE}" fill="none"/>'
                     f'<path d="M{x - 12} 174 L{x + 8} 174" stroke="{c["legs"]}" stroke-width="{STROKE}" fill="none"/>')
    return {
        "limb_bl": (leg(86), (86, 150), -2),
        "limb_br": (leg(108), (108, 150), -2),
        "tail": (f'<path d="M58 118 L24 104 L32 134 Z" fill="{c["accent"]}" stroke="{o}" stroke-width="{STROKE}"/>', (58, 122), -1),
        "body": (f'<ellipse cx="94" cy="124" rx="54" ry="40" fill="{c["base"]}" stroke="{o}" stroke-width="{STROKE}"/>'
                 f'<ellipse cx="96" cy="140" rx="34" ry="14" fill="{c["shade"]}"/>', (94, 162), 0),
        "limb_fl": (f'<path d="M64 112 Q96 92 128 120 Q100 140 64 130 Z" fill="{c["accent"]}" stroke="{o}" stroke-width="{STROKE}"/>', (70, 116), 1),
        "head": (f'<circle cx="132" cy="80" r="32" fill="{c["base"]}" stroke="{o}" stroke-width="{STROKE}"/>', (124, 108), 2),
        "accessory": (f'<path d="M156 74 L192 84 L156 94 Z" fill="{c["beak"]}" stroke="{o}" stroke-width="{STROKE}"/>', (156, 84), 3),
        "eye_r": (eye(140, 72, 10, (2, 0)), (140, 72), 3),
    }


def puffer(c):
    o = PALETTE["outline"]
    sp = c["spines"]
    cx, cy, r = 100, 108, 58
    spikes = "".join(
        f'<path d="M{cx + (r - 4) * math.cos(a - 0.17):.1f} {cy + (r - 4) * math.sin(a - 0.17):.1f} '
        f'L{cx + (r + 17) * math.cos(a):.1f} {cy + (r + 17) * math.sin(a):.1f} '
        f'L{cx + (r - 4) * math.cos(a + 0.17):.1f} {cy + (r - 4) * math.sin(a + 0.17):.1f} Z" '
        f'fill="{sp}" stroke="{o}" stroke-width="{STROKE * 0.8:.1f}"/>'
        for a in (i * math.tau / 14 + 0.2 for i in range(14)))
    fin = lambda side: (f'<path d="M{100 + side * 44} 124 Q{100 + side * 78} 126 {100 + side * 66} 152 '
                        f'Q{100 + side * 50} 150 {100 + side * 38} 138 Z" fill="{c["shade"]}" stroke="{o}" stroke-width="{STROKE}"/>')
    return {
        "tail": (f'<path d="M46 108 L16 92 Q10 110 16 128 L46 118 Z" fill="{c["shade"]}" stroke="{o}" stroke-width="{STROKE}"/>', (46, 112), -1),
        "limb_fl": (fin(-1), (62, 128), -2),
        "limb_fr": (fin(1), (138, 128), -2),
        "body": (spikes +
                 f'<circle cx="{cx}" cy="{cy}" r="{r}" fill="{c["base"]}" stroke="{o}" stroke-width="{STROKE}"/>'
                 f'<ellipse cx="{cx}" cy="{cy + 30}" rx="40" ry="22" fill="{c["accent"]}"/>'
                 f'<circle cx="70" cy="76" r="6" fill="{c["accent"]}"/><circle cx="126" cy="72" r="4" fill="{c["accent"]}"/>', (100, 160), 0),
        "eye_l": (eye(78, 98, 14), (78, 98), 1),
        "eye_r": (eye(122, 98, 14), (122, 98), 1),
        "mouth": (f'<ellipse cx="100" cy="124" rx="9" ry="7" fill="{o}"/>'
                  f'<ellipse cx="100" cy="126" rx="5" ry="3" fill="{c["shade"]}"/>', (100, 124), 1),
    }


def otter(c):
    o = PALETTE["outline"]
    foot = lambda x, y: f'<ellipse cx="{x}" cy="{y}" rx="15" ry="10" fill="{c["shade"]}" stroke="{o}" stroke-width="{STROKE}"/>'
    return {
        "tail": (f'<path d="M52 134 Q20 152 12 128 Q14 112 34 116 Q46 118 58 118 Z" fill="{c["base"]}" stroke="{o}" stroke-width="{STROKE}"/>', (54, 126), -2),
        "limb_bl": (foot(74, 164), (74, 156), -2),
        "limb_br": (foot(112, 166), (112, 158), -2),
        "body": (f'<ellipse cx="96" cy="128" rx="58" ry="34" fill="{c["base"]}" stroke="{o}" stroke-width="{STROKE}"/>'
                 f'<ellipse cx="104" cy="142" rx="38" ry="18" fill="{c["accent"]}"/>'
                 f'<circle cx="62" cy="114" r="5" fill="{c["shade"]}"/><circle cx="82" cy="106" r="4" fill="{c["shade"]}"/>', (96, 160), 0),
        "limb_fl": (f'<ellipse cx="130" cy="154" rx="12" ry="10" fill="{c["base"]}" stroke="{o}" stroke-width="{STROKE}"/>', (130, 146), 1),
        "limb_fr": (f'<ellipse cx="148" cy="158" rx="12" ry="10" fill="{c["base"]}" stroke="{o}" stroke-width="{STROKE}"/>', (148, 150), 1),
        "head": (f'<circle cx="124" cy="66" r="8" fill="{c["shade"]}" stroke="{o}" stroke-width="{STROKE * 0.8:.1f}"/>'
                 f'<circle cx="156" cy="66" r="8" fill="{c["shade"]}" stroke="{o}" stroke-width="{STROKE * 0.8:.1f}"/>'
                 f'<circle cx="140" cy="94" r="33" fill="{c["base"]}" stroke="{o}" stroke-width="{STROKE}"/>'
                 f'<ellipse cx="154" cy="106" rx="19" ry="14" fill="{c["accent"]}"/>'
                 f'<ellipse cx="168" cy="100" rx="6" ry="4.5" fill="{o}"/>', (130, 120), 2),
        "eye_l": (eye(130, 86, 8, (1, 0)), (130, 86), 3),
        "eye_r": (eye(150, 84, 8, (1, 0)), (150, 84), 3),
        "mouth": (f'<path d="M150 112 Q158 119 168 112" stroke="{o}" stroke-width="{STROKE * 0.6:.1f}" fill="none"/>', (158, 114), 3),
    }


def seal(c):
    o = PALETTE["outline"]
    whisk = "".join(f'<path d="M166 {y} L{192} {y + dy}" stroke="{o}" stroke-width="{STROKE * 0.4:.1f}" fill="none"/>'
                    for y, dy in ((104, -6), (109, 2)))
    flip = lambda x: (f'<path d="M{x} 138 Q{x + 22} 150 {x + 14} 172 Q{x - 4} 166 {x - 8} 148 Z" '
                      f'fill="{c["shade"]}" stroke="{o}" stroke-width="{STROKE}"/>')
    return {
        "tail": (f'<path d="M52 140 Q16 122 12 144 Q22 146 30 156 Q20 164 14 176 Q48 176 58 156 Z" '
                 f'fill="{c["shade"]}" stroke="{o}" stroke-width="{STROKE}"/>', (54, 148), -1),
        "body": (f'<path d="M44 152 Q40 112 90 98 Q132 90 142 122 Q148 152 110 166 Q70 176 44 152 Z" '
                 f'fill="{c["base"]}" stroke="{o}" stroke-width="{STROKE}"/>'
                 f'<ellipse cx="104" cy="150" rx="36" ry="12" fill="{c["accent"]}"/>'
                 f'<circle cx="70" cy="120" r="5" fill="{c["shade"]}"/><circle cx="92" cy="112" r="4" fill="{c["shade"]}"/>', (96, 164), 0),
        "limb_fl": (flip(112), (116, 140), 1),
        "limb_fr": (flip(84), (88, 142), 1),
        "head": (f'<circle cx="138" cy="94" r="31" fill="{c["base"]}" stroke="{o}" stroke-width="{STROKE}"/>'
                 f'<ellipse cx="154" cy="106" rx="18" ry="13" fill="{c["accent"]}"/>'
                 f'<ellipse cx="166" cy="99" rx="7" ry="5" fill="{o}"/>', (128, 120), 2),
        "eye_l": (eye(130, 86, 9, (1, 0)), (130, 86), 3),
        "eye_r": (eye(150, 84, 9, (1, 0)), (150, 84), 3),
        "mouth": (whisk + f'<path d="M148 113 Q156 120 166 113" stroke="{o}" stroke-width="{STROKE * 0.6:.1f}" fill="none"/>', (158, 114), 3),
    }


def _claw(cx, cy, s, side, fill):
    o = PALETTE["outline"]
    sweep = 1 if side > 0 else 0
    return (f'<path d="M{cx} {cy} a{26 * s:.1f} {26 * s:.1f} 0 1 {sweep} 0 {52 * s:.1f} l{-side * 6 * s:.1f} {-14 * s:.1f} '
            f'a{12 * s:.1f} {12 * s:.1f} 0 1 {1 - sweep} 0 {-24 * s:.1f} z" fill="{fill}" stroke="{o}" stroke-width="{STROKE}"/>')


def hermit(c):
    o = PALETTE["outline"]
    legs = lambda side: "".join(
        f'<path d="M{x} {y} L{x + side * 10} {y + 24}" stroke="{o}" stroke-width="{STROKE}" fill="none"/>'
        for x, y in ((100 + side * 20 + 20, 150), (100 + side * 34 + 20, 152)))
    stalk = lambda x, y: f'<path d="M{x} {y + 26} L{x} {y + 6}" stroke="{o}" stroke-width="{STROKE}" fill="none"/>' + eye(x, y, 11)
    spiral = (f'<path d="M84 104 a6 6 0 1 1 8 4 a14 14 0 1 1 -22 -10 a24 24 0 1 1 28 34" stroke="{c["shell_line"]}" '
              f'stroke-width="{STROKE * 0.7:.1f}" fill="none"/>')
    return {
        "limb_bl": (legs(-1), (116, 150), -2),
        "limb_br": (legs(1), (150, 150), -2),
        "shell": (f'<circle cx="84" cy="102" r="56" fill="{c["shell"]}" stroke="{o}" stroke-width="{STROKE}"/>'
                  f'<path d="M50 126 Q84 160 126 124 Q118 152 84 156 Q56 152 50 126 Z" fill="{c["shell_shade"]}"/>' + spiral, (84, 108), -1),
        "body": (f'<ellipse cx="128" cy="140" rx="38" ry="26" fill="{c["base"]}" stroke="{o}" stroke-width="{STROKE}"/>'
                 f'<ellipse cx="130" cy="150" rx="26" ry="10" fill="{c["shade"]}"/>'
                 f'<circle cx="116" cy="130" r="4" fill="{c["accent"]}"/>', (128, 160), 0),
        "eye_l": (stalk(120, 92), (120, 114), 1),
        "eye_r": (stalk(140, 94), (140, 116), 1),
        "mouth": (f'<path d="M114 146 Q124 154 134 146" stroke="{o}" stroke-width="{STROKE * 0.7:.1f}" fill="none"/>', (124, 148), 1),
        "claw_l": (_claw(154, 150, 0.6, -1, c["base"]), (152, 158), 2),
        "claw_r": (_claw(162, 92, 0.8, 1, c["base"]), (160, 124), 2),
    }


def star(c):
    o = PALETTE["outline"]
    cx, cy = 100, 106
    tip, half = 76, 25

    def arm(deg):
        a = math.radians(deg)
        ux, uy = math.cos(a), math.sin(a)
        px, py = -uy, ux
        return (f'<path d="M{cx + px * half:.1f} {cy + py * half:.1f} L{cx + ux * tip:.1f} {cy + uy * tip:.1f} '
                f'L{cx - px * half:.1f} {cy - py * half:.1f} Z" fill="{c["base"]}" stroke="{o}" stroke-width="{STROKE}"/>'
                f'<circle cx="{cx + ux * tip * 0.62:.1f}" cy="{cy + uy * tip * 0.62:.1f}" r="4.5" fill="{c["accent"]}"/>')
    return {
        "limb_top": (arm(-90), (cx, cy), -1),
        "limb_fr": (arm(-18), (cx, cy), -1),
        "limb_br": (arm(54), (cx, cy), -1),
        "limb_bl": (arm(126), (cx, cy), -1),
        "limb_fl": (arm(198), (cx, cy), -1),
        "body": (f'<circle cx="{cx}" cy="{cy}" r="30" fill="{c["base"]}" stroke="{o}" stroke-width="{STROKE}"/>'
                 f'<ellipse cx="{cx}" cy="{cy + 14}" rx="18" ry="8" fill="{c["shade"]}"/>'
                 f'<circle cx="{cx - 14}" cy="{cy - 22}" r="4" fill="{c["accent"]}"/>', (100, 150), 0),
        "eye_l": (eye(88, 100, 10), (88, 100), 1),
        "eye_r": (eye(112, 100, 10), (112, 100), 1),
        "mouth": (f'<path d="M92 118 Q100 126 108 118" stroke="{o}" stroke-width="{STROKE * 0.7:.1f}" fill="none"/>', (100, 120), 1),
    }


BUILDERS = {"crab": crab, "octopus": octopus, "gull": gull, "puffer": puffer, "otter": otter, "seal": seal,
            "hermit": hermit, "star": star}
# every part hangs from the body unless listed here (the gull's eye and beak move with its head)
HEAD = {"eye_l": "head", "eye_r": "head", "mouth": "head"}
PARENTS = {"gull": {"accessory": "head", "eye_r": "head"}, "otter": HEAD, "seal": HEAD}


def build(animal: str, colours: dict, folder: str) -> list:
    parts = BUILDERS[animal](colours)
    os.makedirs(folder, exist_ok=True)
    rig = []
    for name, (body, pivot, z) in parts.items():
        box = bounds(body)
        with open(os.path.join(folder, f"{name}.svg"), "w", encoding="utf-8", newline="\n") as fh:
            fh.write(svg(body, box))
        parent = "" if name == "body" else PARENTS.get(animal, {}).get(name, "body")
        rig.append({"name": name, "pivot": list(pivot), "parent": parent, "z": z, "box": list(box)})
    return rig


def main() -> None:
    for animal in BUILDERS:
        folder = os.path.join(ROOT, "assets", "animals", animal)
        rig = build(animal, PALETTE["animals"][animal], folder)
        with open(os.path.join(ROOT, "data", "rigs", f"{animal}.json"), "w", encoding="utf-8", newline="\n") as fh:
            json.dump({"id": animal, "size": SIZE, "origin": list(ORIGIN), "parts": rig}, fh, indent=2)
            fh.write("\n")
        print(f"{animal}: {len(rig)} parts")
    for look, colours in PALETTE["looks"].items():
        animal = colours["animal"]
        merged = {**PALETTE["animals"][animal], **{k: v for k, v in colours.items() if k != "animal"}}
        build(animal, merged, os.path.join(ROOT, "assets", "looks", look))
        print(f"look {look}: parts recoloured")


if __name__ == "__main__":
    main()
