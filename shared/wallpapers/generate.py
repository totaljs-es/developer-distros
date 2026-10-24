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
# Colors that remind of Ubuntu (aubergine and orange) and of Arch (blue): the palettes only, never their logos, which are marks
AUBERGINE, PLUM, PURPLE, ORANGE, AMBER, MAGENTA = '#2c001e', '#5e2750', '#77216f', '#e95420', '#f2874b', '#ad2b6b'
NAVY, DEEP_BLUE, BLUE, ICE = '#08131f', '#0d3a5c', '#1793d1', '#7cc4ec'

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


def logo_echo(cx, cy, height, color, opacity, width, dash=''):
    """The silhouette of the logo as a line: an echo of it, `height` pixels high."""
    k = height / PATH_H
    return (f'<path d="{LOGO_OUTLINE}" transform="translate({cx:.1f},{cy:.1f}) scale({k:.4f}) translate(-{PATH_CENTER},-{PATH_CENTER})" '
            f'fill="none" stroke="{color}" stroke-opacity="{opacity}" stroke-width="{width / k:.2f}" stroke-linejoin="round"'
            + (' stroke-dasharray="' + ' '.join('%.2f' % (float(v) / k) for v in dash.split()) + '"' if dash else '') + '/>\n')


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


def _mix(a, b, t):
    """The color between two #rrggbb colors; t = 0 is a, t = 1 is b."""
    t = max(0.0, min(1.0, t))
    pa, pb = [int(a[i:i + 2], 16) for i in (1, 3, 5)], [int(b[i:i + 2], 16) for i in (1, 3, 5)]
    return '#%02x%02x%02x' % tuple(round(pa[i] + (pb[i] - pa[i]) * t) for i in range(3))


def ember():
    """Ubuntu-like: ribbons of warm light on aubergine, and the logo at the start of them."""
    rnd = random.Random(31)
    ribbons = ''
    palette = [ORANGE, AMBER, MAGENTA, PURPLE, '#c34113', '#f4a261']
    for i in range(11):
        base = 1500 - i * 90 + rnd.uniform(-30, 30)
        a1, a2 = rnd.uniform(110, 230), rnd.uniform(40, 90)
        f1, f2 = rnd.uniform(0.0007, 0.0013), rnd.uniform(0.002, 0.004)
        p1, p2, q = rnd.uniform(0, 6.28), rnd.uniform(0, 6.28), rnd.uniform(0, 6.28)
        top, bottom = [], []
        for x in range(1300, W + 32, 32):
            fade = min(1.0, (x - 1300) / 900)
            y = base - (x - 1300) * 0.22 + a1 * math.sin(x * f1 + p1) + a2 * math.sin(x * f2 + p2)
            th = (30 + 120 * (0.5 + 0.5 * math.sin(x * 0.0011 + q))) * fade
            top.append((x, y))
            bottom.append((x, y + th))
        pts = top + bottom[::-1]
        color = palette[i % len(palette)]
        ribbons += f'<polygon points="{" ".join("%d,%.1f" % p for p in pts)}" fill="{color}" fill-opacity="{rnd.uniform(0.10, 0.42):.3f}"/>\n'
        ribbons += f'<polyline points="{" ".join("%d,%.1f" % p for p in top)}" fill="none" stroke="{color}" stroke-opacity="0.55" stroke-width="2.5"/>\n'
    defs = f"""<linearGradient id="bg" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#1a0013"/><stop offset="0.55" stop-color="{AUBERGINE}"/><stop offset="1" stop-color="#4a0d3b"/></linearGradient>
<radialGradient id="warm" cx="0.5" cy="0.5" r="0.5"><stop offset="0" stop-color="{AMBER}" stop-opacity="0.50"/><stop offset="0.5" stop-color="{ORANGE}" stop-opacity="0.16"/><stop offset="1" stop-color="{ORANGE}" stop-opacity="0"/></radialGradient>"""
    body = f'<rect width="{W}" height="{H}" fill="url(#bg)"/>\n<circle cx="1050" cy="1100" r="900" fill="url(#warm)"/>\n{ribbons}{logo(1050, 1100, 640)}'
    return svg(body, defs, with_logo=True)


def aubergine():
    """Ubuntu-like: soft lights of aubergine, magenta and orange, with the logo calm in the middle."""
    # each light is a radial gradient (no filter): it fades to nothing, so the colors do not turn brown where they meet
    lights = [(3000, 1900, 1500, ORANGE, .62), (700, 1800, 1300, MAGENTA, .55), (500, 300, 1300, PURPLE, .70), (1900, 700, 1000, '#9b3a78', .30),
              (3300, 450, 1100, PLUM, .55), (2200, 2000, 900, AMBER, .28)]
    defs = f'''<radialGradient id="bg" cx="0.5" cy="0.5" r="0.85"><stop offset="0" stop-color="#34082a"/><stop offset="1" stop-color="#1a0013"/></radialGradient>
<radialGradient id="halo" cx="0.5" cy="0.5" r="0.5"><stop offset="0" stop-color="#ffd9c0" stop-opacity="0.22"/><stop offset="1" stop-color="#ffd9c0" stop-opacity="0"/></radialGradient>'''
    glows = ''
    for i, (x, y, r, color, op) in enumerate(lights):
        defs += f'\n<radialGradient id="l{i}" cx="0.5" cy="0.5" r="0.5"><stop offset="0" stop-color="{color}" stop-opacity="{op}"/><stop offset="0.55" stop-color="{color}" stop-opacity="{op * 0.45:.3f}"/><stop offset="1" stop-color="{color}" stop-opacity="0"/></radialGradient>'
        glows += f'<circle cx="{x}" cy="{y}" r="{r}" fill="url(#l{i})"/>\n'
    body = f'<rect width="{W}" height="{H}" fill="url(#bg)"/>\n{glows}<circle cx="1920" cy="1080" r="640" fill="url(#halo)"/>\n{logo(1920, 1080, 560)}'
    return svg(body, defs, with_logo=True)


def sunrise():
    """Ubuntu-like: bands of light around a center that goes from aubergine to orange, with the logo in it."""
    cx, cy = 2700, 1500
    discs = ''
    radii = list(range(2900, 300, -220))
    for i, r in enumerate(radii):
        t = i / (len(radii) - 1)
        color = _mix(AUBERGINE, ORANGE, t * 1.12) if t < 0.89 else _mix(ORANGE, '#ffb86b', (t - 0.89) / 0.11)
        discs += f'<circle cx="{cx}" cy="{cy}" r="{r}" fill="{color}"/>\n'
    defs = f"""<radialGradient id="shade" cx="0.7" cy="0.69" r="0.95"><stop offset="0" stop-color="#000000" stop-opacity="0"/><stop offset="1" stop-color="#000000" stop-opacity="0.5"/></radialGradient>
<radialGradient id="halo" cx="0.5" cy="0.5" r="0.5"><stop offset="0" stop-color="#ffd0a0" stop-opacity="0.28"/><stop offset="1" stop-color="#ffd0a0" stop-opacity="0"/></radialGradient>"""
    body = f'<rect width="{W}" height="{H}" fill="{AUBERGINE}"/>\n{discs}<rect width="{W}" height="{H}" fill="url(#shade)" opacity="0.8"/>\n<circle cx="{cx}" cy="{cy}" r="560" fill="url(#halo)"/>\n{logo(cx, cy, 600)}'
    return svg(body, defs, with_logo=True)


def prism():
    """Arch-like: sharp facets in blue, cold and minimal, with the logo lit in them."""
    rnd = random.Random(13)
    cols, rows = 20, 11
    cw, ch = W / (cols - 1), H / (rows - 1)
    pts = [[(c * cw + (rnd.uniform(-.34, .34) * cw if 0 < c < cols - 1 else 0), r * ch + (rnd.uniform(-.34, .34) * ch if 0 < r < rows - 1 else 0))
            for c in range(cols)] for r in range(rows)]
    fx, fy = 2650, 1080
    faces = ''
    for r in range(rows - 1):
        for c in range(cols - 1):
            a, b, d, e = pts[r][c], pts[r][c + 1], pts[r + 1][c], pts[r + 1][c + 1]
            for tri in ((a, b, d), (b, e, d)) if (r + c) % 2 else ((a, b, e), (a, e, d)):
                mx, my = sum(p[0] for p in tri) / 3, sum(p[1] for p in tri) / 3
                near = max(0.0, 1 - math.hypot(mx - fx, my - fy) / 2300)
                t = 0.06 + 0.55 * near ** 1.4 + rnd.uniform(-0.05, 0.07)
                color = _mix(NAVY, BLUE, t)
                faces += f'<polygon points="{" ".join("%.1f,%.1f" % p for p in tri)}" fill="{color}" stroke="{color}" stroke-width="1.5" stroke-linejoin="round"/>\n'
    defs = f"""<radialGradient id="halo" cx="0.5" cy="0.5" r="0.5"><stop offset="0" stop-color="{ICE}" stop-opacity="0.45"/><stop offset="1" stop-color="{ICE}" stop-opacity="0"/></radialGradient>
<radialGradient id="vignette" cx="0.7" cy="0.5" r="0.85"><stop offset="0.55" stop-color="#000000" stop-opacity="0"/><stop offset="1" stop-color="#000000" stop-opacity="0.6"/></radialGradient>"""
    body = f'<rect width="{W}" height="{H}" fill="{NAVY}"/>\n{faces}<rect width="{W}" height="{H}" fill="url(#vignette)"/>\n<circle cx="{fx}" cy="{fy}" r="700" fill="url(#halo)"/>\n{logo(fx, fy, 700)}'
    return svg(body, defs, with_logo=True)


def blueprint():
    """Arch-like: a technical drawing. A grid, marks, and the logo drawn on it with its construction lines."""
    cx, cy = 2550, 1080
    grid = ''
    for x in range(0, W + 1, 60):
        major = x % 300 == 0
        grid += f'<line x1="{x}" y1="0" x2="{x}" y2="{H}" stroke="{BLUE}" stroke-opacity="{0.20 if major else 0.075}" stroke-width="{2 if major else 1.2}"/>\n'
    for y in range(0, H + 1, 60):
        major = y % 300 == 0
        grid += f'<line x1="0" y1="{y}" x2="{W}" y2="{y}" stroke="{BLUE}" stroke-opacity="{0.20 if major else 0.075}" stroke-width="{2 if major else 1.2}"/>\n'
    marks = ''
    for x in range(300, W, 300):
        for y in range(300, H, 300):
            marks += f'<path d="M{x - 14},{y} H{x + 14} M{x},{y - 14} V{y + 14}" stroke="{ICE}" stroke-opacity="0.45" stroke-width="2.2"/>\n'
    construction = (f'<line x1="{cx}" y1="0" x2="{cx}" y2="{H}" stroke="{ICE}" stroke-opacity="0.30" stroke-width="2" stroke-dasharray="28 16"/>\n'
                    f'<line x1="0" y1="{cy}" x2="{W}" y2="{cy}" stroke="{ICE}" stroke-opacity="0.30" stroke-width="2" stroke-dasharray="28 16"/>\n'
                    f'<circle cx="{cx}" cy="{cy}" r="620" fill="none" stroke="{ICE}" stroke-opacity="0.30" stroke-width="2" stroke-dasharray="6 14"/>\n'
                    + logo_echo(cx, cy, 980, ICE, 0.42, 3, '34 18') + logo_echo(cx, cy, 1280, ICE, 0.24, 3, '34 18'))
    defs = f"""<radialGradient id="bg" cx="0.66" cy="0.5" r="0.9"><stop offset="0" stop-color="#0f2a42"/><stop offset="1" stop-color="{NAVY}"/></radialGradient>"""
    body = f'<rect width="{W}" height="{H}" fill="url(#bg)"/>\n{grid}{marks}{construction}{logo(cx, cy, 640)}'
    return svg(body, defs, with_logo=True)


def syntax():
    """Arch-like: the shape of code, in bars, like an editor out of focus. A dark place is left for the logo."""
    rnd = random.Random(44)
    colors = [ICE, BLUE, '#4fb3a9', '#8a7fd1', LIGHT, '#8aa0b3']
    bars = ''
    for row in range(0, int(H / 52)):
        y = 40 + row * 52
        x = 120 + rnd.choice([0, 0, 1, 2, 2, 3]) * 90
        for _ in range(rnd.randint(2, 7)):
            w = rnd.choice([60, 90, 140, 200, 280, 380])
            if x + w > W - 100:
                break
            bars += f'<rect x="{x}" y="{y}" width="{w}" height="22" rx="6" fill="{rnd.choice(colors)}" fill-opacity="{rnd.uniform(0.10, 0.30):.3f}"/>\n'
            x += w + rnd.choice([18, 18, 30])
        if rnd.random() < 0.12:
            continue
    defs = f"""<radialGradient id="calm" cx="0.5" cy="0.5" r="0.5"><stop offset="0" stop-color="{NAVY}" stop-opacity="0.97"/><stop offset="0.7" stop-color="{NAVY}" stop-opacity="0.85"/><stop offset="1" stop-color="{NAVY}" stop-opacity="0"/></radialGradient>
<radialGradient id="halo" cx="0.5" cy="0.5" r="0.5"><stop offset="0" stop-color="{ICE}" stop-opacity="0.28"/><stop offset="1" stop-color="{ICE}" stop-opacity="0"/></radialGradient>"""
    body = f'<rect width="{W}" height="{H}" fill="{NAVY}"/>\n{bars}<circle cx="2400" cy="1080" r="980" fill="url(#calm)"/>\n<circle cx="2400" cy="1080" r="620" fill="url(#halo)"/>\n{logo(2400, 1080, 640)}'
    return svg(body, defs, with_logo=True)



WALLPAPERS = {
    'signal': signal,
    'lattice': lattice,
    'contour': contour,
    'horizon': horizon,
    'mascot': mascot,
    'daylight': daylight,
    'ember': ember,
    'aubergine': aubergine,
    'sunrise': sunrise,
    'prism': prism,
    'blueprint': blueprint,
    'syntax': syntax,
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
