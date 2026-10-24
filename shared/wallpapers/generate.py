#!/usr/bin/env python3
"""Generates the wallpapers of the Total.js Developer Distros as SVG.

    python3 shared/wallpapers/generate.py [out-dir]

Only the standard library. The wallpapers are drawn with code so that they are reproducible, small and can be made for any size:
the canvas is 3840 x 2160 (16:9) and the compositions are in that space; export them with Inkscape (see export.sh).
"""
import math
import os
import random
import re
import sys

W, H = 3840, 2160
GREEN = '#66b639'      # the green of the logo of Total.js
LIGHT = '#9ad959'      # its light side
DEEP = '#2e5a1a'
INK = '#0b0f0d'        # the graphite of the dark wallpapers

HERE = os.path.dirname(os.path.abspath(__file__))
BRANDING = os.path.join(HERE, '..', 'branding')
MASCOT = os.environ.get('MASCOT', os.path.join(BRANDING, 'mascot.png'))
MASCOT_HREF = MASCOT   # main() makes it relative to the folder of the SVGs, so that they do not carry the path of a computer
LOGO_FILE = os.environ.get('LOGO', os.path.join(BRANDING, 'logo-totaljs.svg'))

# The official logo of Total.js (shared/branding/logo-totaljs.svg) is used as it is: its group and its definitions are copied
# into each wallpaper. It lives in a box of 126 x 126 where the hexagon is 95.5 wide and 104.9 high, centered on 63,63.
_logo = open(LOGO_FILE).read()
LOGO_BODY = _logo[_logo.index('<g\n   transform="translate(-343.241'):_logo.index('<defs')]
LOGO_DEFS = _logo[_logo.index('>', _logo.index('<defs')) + 1:_logo.index('</defs>')]
LOGO_H = 104.862
_path = _logo[_logo.index('<path', _logo.index('id="g8"')):]
LOGO_SHAPE = re.search(r'd="([^"]+)"', _path).group(1)         # the hexagon with the hole of the logo
LOGO_OUTLINE = LOGO_SHAPE[:LOGO_SHAPE.index(' z') + 2]          # only its outside
# From the coordinates of that path to the box of 126 x 126: x' = 0.3708 + 0.278352 * x. Its center is 224.9, 224.9 and it is 376.7 high.
PATH_CENTER, PATH_H = 224.9, 376.7
PATH_TO_BOX = 'translate(0.3708,0.3708) scale(0.278352)'


_light = re.findall(r'<path\s+d="([^"]+)"\s+style="fill:#9ad959"', _logo)
LOGO_LIGHT = _light[0], _light[1]      # the arrow, and the light side
# in the logo the arrow is drawn 6.686 units higher (in the coordinates of its path) than the side
LOGO_ARROW_SHIFT = -6.686


def logo_flat(cx, cy, height, opacity, extra=''):
    """The logo as three flat shapes, without its inner shadows: for the out-of-focus lights, where the shadows would be lost."""
    k = height / PATH_H
    return (f'<g opacity="{opacity:.3f}" {extra} transform="translate({cx:.1f},{cy:.1f}) scale({k:.4f}) translate(-{PATH_CENTER},-{PATH_CENTER})">'
            f'<path d="{LOGO_SHAPE}" fill-rule="evenodd" fill="{GREEN}"/>'
            f'<path d="{LOGO_LIGHT[1]}" fill="{LIGHT}"/>'
            f'<path d="{LOGO_LIGHT[0]}" transform="translate(0,{LOGO_ARROW_SHIFT})" fill="{LIGHT}"/></g>\n')


def logo(cx, cy, height):
    """The logo, with its colors, centered on cx, cy and `height` pixels high."""
    k = height / LOGO_H
    # the file of the logo says evenodd in the style of its root: without it the hole is filled
    return f'<g style="fill-rule:evenodd;clip-rule:evenodd" transform="translate({cx:.1f},{cy:.1f}) scale({k:.4f}) translate(-63,-63)">{LOGO_BODY}</g>'


def logo_echo(cx, cy, height, color, opacity, width):
    """The silhouette of the logo as a line: an echo of it, `height` pixels high."""
    k = height / PATH_H
    return (f'<path d="{LOGO_OUTLINE}" transform="translate({cx:.1f},{cy:.1f}) scale({k:.4f}) translate(-{PATH_CENTER},-{PATH_CENTER})" '
            f'fill="none" stroke="{color}" stroke-opacity="{opacity}" stroke-width="{width / k:.2f}" stroke-linejoin="round"/>\n')


def logo_shape(cx, cy, height, color, opacity, extra=''):
    """The hexagon with the hole of the logo, in one color (for the out-of-focus lights)."""
    k = height / PATH_H
    return (f'<path d="{LOGO_SHAPE}" fill-rule="evenodd" fill="{color}" fill-opacity="{opacity:.3f}" {extra} '
            f'transform="translate({cx:.1f},{cy:.1f}) scale({k:.4f}) translate(-{PATH_CENTER},-{PATH_CENTER})"/>\n')


def hexagon(cx, cy, r, rotate=0.0):
    """The points of a hexagon with a vertex at the top, like the logo."""
    pts = []
    for k in range(6):
        a = math.radians(30 + 60 * k + rotate)
        pts.append((cx + r * math.cos(a), cy + r * math.sin(a)))
    return ' '.join('%.1f,%.1f' % p for p in pts)


def svg(body, defs='', light=False, with_logo=False):
    if with_logo:
        defs += LOGO_DEFS
    return f'''<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="{W}" height="{H}" viewBox="0 0 {W} {H}">
<defs>
{defs}
<filter id="grain" x="0" y="0" width="100%" height="100%">
<feTurbulence type="fractalNoise" baseFrequency="0.85" numOctaves="2" seed="11" result="n"/>
<feColorMatrix in="n" type="matrix" values="1 0 0 0 0  1 0 0 0 0  1 0 0 0 0  0 0 0 0 {0.05 if light else 0.07}"/>
</filter>
</defs>
{body}
<rect width="{W}" height="{H}" filter="url(#grain)"/>
</svg>
'''


def signal():
    """The logo in the middle, lit from behind, and its silhouette repeated outwards as rings that fade."""
    cx, cy = 2650, 1080
    rings = ''
    for h, op, w in [(1010, .34, 5), (1290, .24, 4), (1620, .16, 4), (2000, .10, 3), (2450, .06, 3)]:
        rings += logo_echo(cx, cy, h, GREEN, op, w)
    defs = f"""<radialGradient id="bg" cx="0.69" cy="0.5" r="0.75"><stop offset="0" stop-color="#1b2a20"/><stop offset="0.55" stop-color="#101612"/><stop offset="1" stop-color="{INK}"/></radialGradient>
<radialGradient id="core" cx="0.5" cy="0.5" r="0.5"><stop offset="0" stop-color="{LIGHT}" stop-opacity="0.42"/><stop offset="0.45" stop-color="{GREEN}" stop-opacity="0.16"/><stop offset="1" stop-color="{GREEN}" stop-opacity="0"/></radialGradient>"""
    body = f"""<rect width="{W}" height="{H}" fill="url(#bg)"/>
<circle cx="{cx}" cy="{cy}" r="760" fill="url(#core)"/>
{rings}{logo(cx, cy, 700)}
"""
    return svg(body, defs, with_logo=True)


def lattice():
    """A honeycomb that fades from the lower right, where the logo is, with a few cells lit around it."""
    r = 96
    dx, dy = math.sqrt(3) * r, 1.5 * r
    rnd = random.Random(7)
    cells, lit = '', ''
    fx, fy = 3000, 1480   # the logo, and the focus of the light
    maxd = math.hypot(W, H) * 0.8
    for row in range(-2, int(H / dy) + 3):
        for col in range(-2, int(W / dx) + 3):
            cx = col * dx + (dx / 2 if row % 2 else 0)
            cy = row * dy
            dist = math.hypot(cx - fx, cy - fy)
            if dist < 520:   # the logo has its own space
                continue
            d = dist / maxd
            fade = max(0.0, 1 - d)
            if fade <= 0.02:
                continue
            cells += f'<polygon points="{hexagon(cx, cy, r - 5)}" fill="none" stroke="#ffffff" stroke-opacity="{0.02 + 0.10 * fade ** 1.6:.3f}" stroke-width="2.5" stroke-linejoin="round"/>\n'
            near = dist < 900
            if rnd.random() < 0.07 * fade ** 1.2 + (0.30 if near else 0):
                a = 0.05 + 0.40 * fade ** 1.5 * rnd.random()
                lit += f'<polygon points="{hexagon(cx, cy, r - 5)}" fill="{GREEN}" fill-opacity="{a:.3f}" stroke="{LIGHT}" stroke-opacity="{min(0.9, a * 1.6):.3f}" stroke-width="2.5" stroke-linejoin="round"/>\n'
    defs = f"""<linearGradient id="bg" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="{INK}"/><stop offset="1" stop-color="#16201a"/></linearGradient>
<radialGradient id="core" cx="0.5" cy="0.5" r="0.5"><stop offset="0" stop-color="{LIGHT}" stop-opacity="0.30"/><stop offset="0.5" stop-color="{GREEN}" stop-opacity="0.12"/><stop offset="1" stop-color="{GREEN}" stop-opacity="0"/></radialGradient>"""
    return svg(f'<rect width="{W}" height="{H}" fill="url(#bg)"/>\n{cells}{lit}<circle cx="{fx}" cy="{fy}" r="700" fill="url(#core)"/>\n{logo(fx, fy, 620)}', defs, with_logo=True)


def contour():
    """Contour lines, like a map of a hill, and the logo at the top of it."""
    cx, cy = 2900, 1300
    out = ''
    for k in range(7, 62):
        R = 34 + k * 34
        pts = []
        for i in range(0, 361, 2):
            t = math.radians(i)
            n = (1 + 0.11 * math.sin(2 * t + 0.6 + k * 0.025) + 0.07 * math.sin(3 * t + 1.9 - k * 0.02)
                 + 0.04 * math.sin(5 * t + 0.2 + k * 0.045) + 0.02 * math.sin(9 * t + k * 0.1))
            pts.append((cx + R * n * math.cos(t) * 1.25, cy + R * n * math.sin(t) * 0.92))
        d = 'M' + ' L'.join('%.1f,%.1f' % p for p in pts) + ' Z'
        fade = max(0.0, 1 - R / 2000)
        strong = (k % 5 == 0)
        op = (0.10 + 0.40 * fade) if strong else (0.04 + 0.22 * fade)
        out += f'<path d="{d}" fill="none" stroke="{GREEN if fade > .25 else "#8fb08a"}" stroke-opacity="{op:.3f}" stroke-width="{3.2 if strong else 1.8}" stroke-linejoin="round"/>\n'
    defs = f"""<radialGradient id="bg" cx="0.75" cy="0.6" r="0.9"><stop offset="0" stop-color="#18261c"/><stop offset="0.6" stop-color="#0f1511"/><stop offset="1" stop-color="{INK}"/></radialGradient>
<radialGradient id="core" cx="0.5" cy="0.5" r="0.5"><stop offset="0" stop-color="{LIGHT}" stop-opacity="0.30"/><stop offset="0.5" stop-color="{GREEN}" stop-opacity="0.10"/><stop offset="1" stop-color="{GREEN}" stop-opacity="0"/></radialGradient>"""
    return svg(f'<rect width="{W}" height="{H}" fill="url(#bg)"/>\n<circle cx="{cx}" cy="{cy}" r="620" fill="url(#core)"/>\n{out}{logo(cx, cy, 420)}', defs, with_logo=True)


def horizon():
    """Night, with the land in layers and the logo rising behind the hills."""
    layers = []

    def ridge(y0, amp, seed, top, bottom):
        rnd = random.Random(seed)
        ph = [rnd.random() * 6.28 for _ in range(4)]
        pts = []
        for x in range(0, W + 16, 16):
            y = y0 + amp * (math.sin(x * 0.0011 + ph[0]) + 0.55 * math.sin(x * 0.0029 + ph[1]) + 0.28 * math.sin(x * 0.0068 + ph[2]) + 0.1 * math.sin(x * 0.015 + ph[3]))
            pts.append('%d,%.1f' % (x, y))
        i = len(layers)
        layers.append(f'<linearGradient id="r{i}" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="{top}"/><stop offset="1" stop-color="{bottom}"/></linearGradient>')
        return f'<polygon points="0,{H} {" ".join(pts)} {W},{H}" fill="url(#r{i})"/>\n'

    land = (ridge(1330, 70, 3, '#3d6b34', '#1f4027') + ridge(1440, 85, 5, '#2b4d30', '#16281b') + ridge(1560, 95, 8, '#1c3322', '#0f1b13')
            + ridge(1700, 80, 12, '#122017', '#090f0b') + ridge(1860, 60, 15, '#0b120d', '#050805'))
    defs = f"""<linearGradient id="sky" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="{INK}"/><stop offset="0.55" stop-color="#0f1a13"/><stop offset="0.82" stop-color="#27472d"/><stop offset="1" stop-color="#4c8a3a"/></linearGradient>
<radialGradient id="glow" cx="0.5" cy="0.5" r="0.5"><stop offset="0" stop-color="{LIGHT}" stop-opacity="0.50"/><stop offset="1" stop-color="{LIGHT}" stop-opacity="0"/></radialGradient>
{"".join(layers)}"""
    # the light rises behind the land: the logo is drawn before the ridges
    body = f'<rect width="{W}" height="{H}" fill="url(#sky)"/>\n'
    body += f'<circle cx="2380" cy="1010" r="900" fill="url(#glow)"/>\n'
    body += logo(2380, 870, 560)
    body += land
    return svg(body, defs, with_logo=True)


def mascot():
    """The mascot in the corner, and the logo out of focus behind it, like the login screen but quiet."""
    rnd = random.Random(21)
    bok = ''
    for i in range(22):
        x, y = rnd.uniform(0, W), rnd.uniform(0, H)
        bok += logo_flat(x, y, rnd.uniform(170, 560), rnd.uniform(0.07, 0.26), f'filter="url(#{rnd.choice(["b1", "b2", "b3"])})"')
    defs = f"""<radialGradient id="bg" cx="0.8" cy="0.78" r="0.95"><stop offset="0" stop-color="#1d2c21"/><stop offset="0.5" stop-color="#101612"/><stop offset="1" stop-color="{INK}"/></radialGradient>
<filter id="b1" x="-30%" y="-30%" width="160%" height="160%"><feGaussianBlur stdDeviation="8"/></filter>
<filter id="b2" x="-30%" y="-30%" width="160%" height="160%"><feGaussianBlur stdDeviation="22"/></filter>
<filter id="b3" x="-30%" y="-30%" width="160%" height="160%"><feGaussianBlur stdDeviation="46"/></filter>
<radialGradient id="floor" cx="0.5" cy="0.5" r="0.5"><stop offset="0" stop-color="#000000" stop-opacity="0.55"/><stop offset="1" stop-color="#000000" stop-opacity="0"/></radialGradient>"""
    body = f"""<rect width="{W}" height="{H}" fill="url(#bg)"/>
{bok}
<ellipse cx="3290" cy="1860" rx="430" ry="60" fill="url(#floor)"/>
<image x="3020" y="1330" width="540" height="540" xlink:href="{MASCOT_HREF}" href="{MASCOT_HREF}"/>
"""
    return svg(body, defs)


def daylight():
    """The light one: for people who work with the lights on."""
    cx, cy = 2750, 1000
    rings = ''
    for h, op, w in [(1050, .55, 6), (1350, .36, 5), (1700, .24, 4), (2100, .15, 3), (2550, .09, 3)]:
        rings += logo_echo(cx, cy, h, GREEN, op, w)
    defs = f"""<linearGradient id="bg" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#f7f9f5"/><stop offset="1" stop-color="#dfe8dc"/></linearGradient>
<radialGradient id="warm" cx="0.5" cy="0.5" r="0.5"><stop offset="0" stop-color="{LIGHT}" stop-opacity="0.36"/><stop offset="1" stop-color="{LIGHT}" stop-opacity="0"/></radialGradient>"""
    body = f"""<rect width="{W}" height="{H}" fill="url(#bg)"/>
<circle cx="{cx}" cy="{cy}" r="940" fill="url(#warm)"/>
{rings}{logo(cx, cy, 720)}
"""
    return svg(body, defs, light=True, with_logo=True)


WALLPAPERS = {
    'signal': signal,
    'lattice': lattice,
    'contour': contour,
    'horizon': horizon,
    'mascot': mascot,
    'daylight': daylight,
}

if __name__ == '__main__':
    out = sys.argv[1] if len(sys.argv) > 1 else os.path.join(HERE, 'svg')
    os.makedirs(out, exist_ok=True)
    MASCOT_HREF = os.path.relpath(os.path.abspath(MASCOT), os.path.abspath(out))
    for name, fn in WALLPAPERS.items():
        path = os.path.join(out, name + '.svg')
        with open(path, 'w') as f:
            f.write(fn())
        print(path)
