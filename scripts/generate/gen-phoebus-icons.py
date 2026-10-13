#!/usr/bin/env python3
"""Generate Phoebus's app icons: one Icon Composer bundle per icon in
Icons/source/set.json, written to Icons/LiquidGlass/<pack>/<id>/<id>.icon,
and the catalog scripts/lgrender reads, Icons/LiquidGlass/icons.json.

Every bundle shares the foreground layers in Icons/source/layers and the
foreground groups in Icons/source/foreground.json (Glass, Flat or Light).
Only the backdrop differs: a day look (the default appearance) and a night
look (dark), each the original sunburst, a cream fill, iOS's own dark
background or a colourway. A colourway repaints the sunburst's wedges
(Icons/source/sunburst-wedges.json) between a gap and a ray gradient, with
a soft glow behind the head and, at night, the halo in the glow colour.
Backdrop layers are switched by opacity per appearance; all of them are
off in tinted, so tinted and clear share one mono look.

Usage: gen-phoebus-icons.py   (no arguments; run from anywhere)
"""

import json
import math
import shutil
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
ICONS = ROOT / "Icons"
SOURCE = ICONS / "source"
LAYERS = SOURCE / "layers"

APPEARANCES = ["default", "dark", "clear-light", "clear-dark"]

CX = CY = 512.0
RAY_LENGTH = 1100
GRADIENT_RADIUS = 760.0  # about the corner distance


def hex_rgb(h):
    return [int(h[i:i + 2], 16) for i in (1, 3, 5)]


def rgb_hex(c):
    return "#%02x%02x%02x" % tuple(int(round(min(max(v, 0), 255))) for v in c)


def mix(a, b, t):
    return [x + (y - x) * t for x, y in zip(a, b)]


def percentile(values, q):
    # numpy's default (linear) percentile.
    s = sorted(values)
    pos = (len(s) - 1) * q / 100
    lo = math.floor(pos)
    hi = min(lo + 1, len(s) - 1)
    return s[lo] + (s[hi] - s[lo]) * (pos - lo)


def wedge_weights(wedges):
    """How far each wedge leans to the ray colour, from the light
    sunburst's stretch k (its light rays, k < 1, become the lighter rays)."""
    inv = [1 / w["k"] for w in wedges]
    lo, hi = percentile(inv, 8), percentile(inv, 92)
    w = [min(max((v - lo) / (hi - lo), 0), 1) for v in inv]
    # Pushed towards the ends so rays read as rays.
    return [min(max((v - 0.5) * 1.35 + 0.5, 0), 1) for v in w]


def rays_svg(p, wedges):
    gap0, gap1 = map(hex_rgb, p["gap"])
    ray0, ray1 = map(hex_rgb, p["ray"])
    offsets = [0.0, 0.35, 0.7, 1.0]
    ease = [0.0, 0.42, 0.78, 1.0]  # how far each stop has gone from centre to rim colour
    defs, body, seen = [], [], {}
    for wedge, weight in zip(wedges, wedge_weights(wedges)):
        key = round(weight, 2)
        if key not in seen:
            gid = "w%d" % len(seen)
            seen[key] = gid
            stops = "".join('<stop offset="%.2f" stop-color="%s"/>'
                            % (o, rgb_hex(mix(mix(gap0, gap1, e), mix(ray0, ray1, e), key)))
                            for o, e in zip(offsets, ease))
            defs.append('    <radialGradient id="%s" gradientUnits="userSpaceOnUse" cx="%g" cy="%g" r="%g">%s'
                        '</radialGradient>' % (gid, CX, CY, GRADIENT_RADIUS, stops))
        a0, a1 = math.radians(wedge["a0"]) - 0.0015, math.radians(wedge["a1"]) + 0.0015
        steps = max(2, int((a1 - a0) / math.radians(5)) + 1)
        angles = [a0 + (a1 - a0) * i / (steps - 1) for i in range(steps)]
        points = [(CX, CY)] + [(CX + RAY_LENGTH * math.cos(t), CY + RAY_LENGTH * math.sin(t)) for t in angles]
        body.append('  <path d="M%s Z" fill="url(#%s)"/>'
                    % (" L".join("%.2f %.2f" % q for q in points), seen[key]))
    colour, alpha = p["glow"]
    defs.append('    <radialGradient id="glow" gradientUnits="userSpaceOnUse" cx="%g" cy="%g" r="560">'
                '<stop offset="0" stop-color="%s" stop-opacity="%.3f"/>'
                '<stop offset="0.35" stop-color="%s" stop-opacity="%.3f"/>'
                '<stop offset="0.7" stop-color="%s" stop-opacity="%.3f"/>'
                '<stop offset="1" stop-color="%s" stop-opacity="0"/></radialGradient>'
                % (CX, CY - 20, colour, alpha, colour, alpha * 0.55, colour, alpha * 0.15, colour))
    body.append('  <rect width="1024" height="1024" fill="url(#glow)"/>')
    return ('<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">\n'
            '  <defs>\n%s\n  </defs>\n  <rect width="1024" height="1024" fill="%s"/>\n%s\n</svg>\n'
            % ("\n".join(defs), p["gap"][1], "\n".join(body)))


def halo_svg(p):
    return (LAYERS / "halo.svg").read_text().replace('fill="#ff9614"', 'fill="%s"' % p["glow"][0])


def svg(defs, body):
    return ('<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">\n'
            '  <defs>\n%s\n  </defs>\n%s\n</svg>\n' % (defs, body))


def laurel_path():
    text = (LAYERS / "laurel-silhouette.svg").read_text()
    return text.split('<path d="', 1)[1].split('"', 1)[0]


def laurel_edge_svg(colour, width, sigma):
    """A dark outline under the laurels, so they separate from a backdrop
    of the same brightness."""
    return svg('    <filter id="e" filterUnits="userSpaceOnUse" x="0" y="0" width="1024" height="1024">'
               '<feGaussianBlur stdDeviation="%g"/></filter>' % sigma,
               '  <path d="%s" fill="%s" stroke="%s" stroke-width="%g" stroke-linejoin="round" filter="url(#e)"/>'
               % (laurel_path(), colour, colour, 2 * width))


def laurel_vignette_svg(colour, opacity, centres):
    """The backdrop darkened behind each laurel branch."""
    defs, body = [], []
    for i, (cx, cy) in enumerate(centres):
        defs.append('    <radialGradient id="v%d" gradientUnits="userSpaceOnUse" cx="0" cy="0" r="1" '
                    'gradientTransform="translate(%.1f %.1f) scale(190 300)">'
                    '<stop offset="0" stop-color="%s" stop-opacity="%.2f"/>'
                    '<stop offset="0.55" stop-color="%s" stop-opacity="%.2f"/>'
                    '<stop offset="1" stop-color="%s" stop-opacity="0"/></radialGradient>'
                    % (i, cx, cy, colour, opacity, colour, opacity * 0.6, colour))
        body.append('  <rect width="1024" height="1024" fill="url(#v%d)"/>' % i)
    return svg("\n".join(defs), "\n".join(body))


def p3(hex_srgb, alpha=1.0):
    """sRGB hex to an Icon Composer display-p3 colour string."""
    def lin(v):
        return v / 12.92 if v <= 0.04045 else ((v + 0.055) / 1.055) ** 2.4

    def enc(v):
        v = min(max(v, 0.0), 1.0)
        return 12.92 * v if v <= 0.0031308 else 1.055 * v ** (1 / 2.4) - 0.055

    r, g, b = (lin(v / 255) for v in hex_rgb(hex_srgb))
    # Linear sRGB to linear Display P3, both D65.
    p = (0.8225 * r + 0.1774 * g, 0.0332 * r + 0.9669 * g, 0.0171 * r + 0.0724 * g + 0.9108 * b)
    return "display-p3:%.5f,%.5f,%.5f,%.5f" % (enc(p[0]), enc(p[1]), enc(p[2]), alpha)


def specialize(node, change):
    """Applies change to every `*-specializations` list in an icon.json tree."""
    if isinstance(node, dict):
        for key, value in node.items():
            if key.endswith("-specializations") and isinstance(value, list):
                node[key] = change(value)
            else:
                specialize(value, change)
    elif isinstance(node, list):
        for item in node:
            specialize(item, change)
    return node


def light_only(entries):
    """The day look in every appearance: the dark entries go."""
    return [e for e in entries if e.get("appearance") != "dark"]


def dark_only(entries):
    """The night look in every appearance: the dark entry is the default too."""
    dark = next((e for e in entries if e.get("appearance") == "dark"), None)
    if dark is None:
        return entries
    rest = [e for e in entries if "appearance" in e]
    return [{"value": dark["value"]}] + rest


def visible(layer):
    """Whether a layer shows in any appearance."""
    opacities = layer.get("opacity-specializations")
    return opacities is None or any(e["value"] != 0 for e in opacities)


def backdrop_layer(name, image, default, dark):
    return {"image-name": image, "name": name, "glass": False, "hidden": False,
            "position": {"scale": 1, "translation-in-points": [0, 0]},
            "opacity-specializations": [{"value": default}, {"appearance": "dark", "value": dark},
                                        {"appearance": "tinted", "value": 0}]}


class Generator:
    def __init__(self):
        self.set = json.loads((SOURCE / "set.json").read_text())
        self.foreground = json.loads((SOURCE / "foreground.json").read_text())
        self.wedges = json.loads((SOURCE / "sunburst-wedges.json").read_text())

    def art(self, look, files):
        """The rays and halo file names for a look, adding generated ones
        to files."""
        if look == "system":
            return None, None
        if look == "sunburst":
            return "sunburst.svg", None
        if look == "cream":
            return None, "halo.svg"
        p = self.set["colourways"][look]
        rays = "rays-%s.svg" % look
        files[rays] = rays_svg(p, self.wedges)
        halo = None
        if p.get("night"):
            halo = "halo-%s.svg" % look
            files[halo] = halo_svg(p)
        return rays, halo

    def fill(self, look, night=False):
        if look == "system":
            # Icon Composer's default dark background: iOS draws its own dark
            # icon gradient, the one behind the Phone app, so it follows the system.
            return "system-dark"
        if look == "sunburst":
            c = self.set["fills"]["sunburst"]
        elif look == "cream":
            c = self.set["fills"]["cream-night" if night else "cream"]
        else:
            c = self.set["colourways"][look]["gap"]
            if night:
                return {"solid": p3(c[1])}
        return {"linear-gradient": [p3(c[0]), p3(c[1])]}

    def bundle(self, icon):
        files = {}
        day, night = icon["day"], icon["night"]
        day_rays, day_halo = self.art(day, files)
        night_rays, night_halo = self.art(night, files)
        dim = icon.get("night_dim", 1)
        layers = []  # front to back: halos, then rays
        if day == night:
            if day_halo:
                layers.append(backdrop_layer("Halo", day_halo, 0.3, 0.22))
            if day_rays:
                layers.append(backdrop_layer("Rays", day_rays, 1, dim))
        else:
            if night_halo:
                layers.append(backdrop_layer("Halo (night)", night_halo, 0, 0.3))
            if day_halo:
                layers.append(backdrop_layer("Halo (day)", day_halo, 0.3, 0))
            if night_rays:
                layers.append(backdrop_layer("Rays (night)", night_rays, 0, 1))
            if day_rays:
                layers.append(backdrop_layer("Rays (day)", day_rays, 1, 0))
        groups = json.loads(json.dumps(self.foreground["styles"][icon["style"]]))
        groups.append({"name": "Backdrop", "hidden": False, "layers": layers,
                       "specular-specializations": [{"value": False}],
                       "shadow-specializations": [{"value": {"kind": "none", "opacity": 0}}],
                       "translucency-specializations": [{"value": {"enabled": False, "value": 0}}],
                       "lighting-specializations": [{"value": "combined"}]})
        fix = icon.get("laurel_fix")
        if fix:
            # Day only: a darker backdrop behind the laurels and an outline
            # under them, so they read on a backdrop as bright as they are.
            vignette = "laurel-vignette-%s.svg" % icon["id"]
            files[vignette] = laurel_vignette_svg(centres=self.set["laurel_centres"], **fix["vignette"])
            groups[-1]["layers"].insert(0, backdrop_layer("Laurel vignette", vignette, 1, 0))
            edge = "laurel-edge-%s.svg" % icon["id"]
            files[edge] = laurel_edge_svg(**fix["edge"])
            for g in groups:
                if g.get("name") == "Laurels":
                    g["layers"].append(backdrop_layer("Laurel edge", edge, 1, 0))
        doc = {"fill-specializations": [{"value": self.fill(day)},
                                        {"appearance": "dark",
                                         "value": self.fill(night, night=day != night or dim < 1)}],
               "groups": groups,
               "supported-platforms": self.foreground["supported-platforms"]}

        # The icon follows the system; the App Icon picker's Light and Dark
        # choices are variants that keep one look in every appearance. Their
        # tinted (mono) look is the icon's own.
        folder = ICONS / "LiquidGlass" / icon["group"] / icon["id"]
        self.write(folder / (icon["id"] + ".icon"), doc, files)
        for suffix, change in (("__apollo_light", light_only), ("__apollo_dark", dark_only)):
            variant = specialize(json.loads(json.dumps(doc)), change)
            for g in variant["groups"]:
                g["layers"] = [layer for layer in g["layers"] if visible(layer)]
            self.write(folder / (icon["id"] + suffix + ".icon"), variant, files)

    def write(self, path, doc, files):
        shutil.rmtree(path, ignore_errors=True)
        (path / "Assets").mkdir(parents=True)
        for g in doc["groups"]:
            for layer in g["layers"]:
                name = layer["image-name"]
                if name in files:
                    (path / "Assets" / name).write_text(files[name])
                else:
                    shutil.copyfile(LAYERS / name, path / "Assets" / name)
        (path / "icon.json").write_text(json.dumps(doc, indent=2) + "\n")

    def run(self):
        for icon in self.set["icons"]:
            self.bundle(icon)
        # Every icon has all four looks the App Icon picker previews.
        catalog = {"icons": [{"id": i["id"], "group": i["group"], "appearances": APPEARANCES}
                             for i in self.set["icons"]]}
        (ICONS / "LiquidGlass" / "icons.json").write_text(json.dumps(catalog, indent=2) + "\n")
        print("wrote %d icons" % len(self.set["icons"]))


if __name__ == "__main__":
    Generator().run()
