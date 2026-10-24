#!/usr/bin/env python3
"""Draws the choreography of totaljs/totaljs.script on a sheet, frame by frame, to see it without booting anything.

    python3 shared/plymouth/preview.py [out.svg]

It repeats the formulas of the script (the script is the source of truth) with the images of the theme, at 1920 x 1080.
It is a preview of the movement, not a test of the script: Plymouth runs the script.
"""
import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
THEME = os.path.join(HERE, 'totaljs')
W, H = 1920, 1080
UNIT = H / 1080


def clamp01(v):
    return 0.0 if v < 0 else 1.0 if v > 1 else v


def ramp(t, a, b):
    return clamp01((t - a) / (b - a))


def ease_out(u):
    v = 1 - clamp01(u)
    return 1 - v * v * v


def frame(t, boot_progress, shown_progress):
    """The elements of the screen at time t (seconds), as SVG."""
    cx, cy = W / 2, H / 2 - 36 * UNIT
    logo_h = 290 * UNIT
    side = logo_h * 1024 / 560
    ox, oy = cx - side / 2, cy - side / 2
    ring_points = 72
    radius = logo_h * 0.80
    dot = 20 * UNIT
    img = lambda name, x, y, w, op: f'<image x="{x:.1f}" y="{y:.1f}" width="{w:.1f}" height="{w:.1f}" opacity="{op:.3f}" href="{os.path.join(THEME, name)}"/>\n'

    u_body, u_side, u_arrow = ease_out(ramp(t, .10, 1.0)), ease_out(ramp(t, .30, 1.15)), ease_out(ramp(t, .55, 1.35))
    whole = ramp(t, 1.45, 1.85)
    parts = 1 - whole

    light = 0.12 + 0.22 * ramp(t, 0, 1.4)
    if t >= 1.4:
        light = 0.34 + 0.66 * (1 - ramp(t, 1.4, 2.2))
        if t >= 2.2:
            light = 0.40 + 0.12 * math.sin((t - 2.2) * 2 * math.pi / 3.2)
    float_y = 5 * UNIT * math.sin((t - 1.85) * 2 * math.pi / 4) if t > 1.85 else 0
    glow = side * 2.4

    out = img('glow.png', cx - glow / 2, cy - glow / 2, glow, light)
    out += img('body.png', ox + (1 - u_body) * 260 * UNIT, oy, side, ramp(t, .10, .55) * parts)
    out += img('side.png', ox - (1 - u_side) * 300 * UNIT, oy, side, ramp(t, .30, .70) * parts)
    out += img('arrow.png', ox - (1 - u_arrow) * 520 * UNIT, oy, side, ramp(t, .55, .90) * parts)
    out += img('logo.png', ox, oy + float_y, side, whole)

    ring_alpha = ramp(t, 1.2, 2.0)
    head = t / 2.6 * ring_points
    tail = ring_points * 0.32
    verts = [(cx + radius * math.cos(math.radians(-90 + 60 * j)), cy + radius * math.sin(math.radians(-90 + 60 * j))) for j in range(7)]
    for i in range(ring_points):
        where = i * 6 / ring_points
        edge = int(where)
        part = where - edge
        x = verts[edge][0] + (verts[edge + 1][0] - verts[edge][0]) * part - dot / 2
        y = verts[edge][1] + (verts[edge + 1][1] - verts[edge][1]) * part - dot / 2
        d = (head - i) % ring_points
        comet = (1 - d / tail) ** 2 if d < tail else 0
        lit = 0.55 if (i + 1) / ring_points <= shown_progress else 0
        out += img('dot-off.png', x, y, dot, 0.40 * ring_alpha)
        out += img('dot-on.png', x, y, dot, max(comet, lit) * ring_alpha)

    out += (f'<text x="{cx:.1f}" y="{cy + radius + 56 * UNIT + 22:.1f}" text-anchor="middle" font-family="Helvetica, Arial, sans-serif" '
            f'font-size="26" fill="#ebf7e6" opacity="{ramp(t, 1.5, 2.3):.3f}">Total.js Developer</text>\n')
    return out


def sheet(times, columns=3, cell=(640, 360), gap=16):
    cw, ch = cell
    rows = (len(times) + columns - 1) // columns
    width, height = columns * cw + (columns + 1) * gap, rows * (ch + 30) + gap
    svg = [f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}"><defs>'
           '<linearGradient id="bg" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#0a0f0d"/><stop offset="1" stop-color="#131b17"/></linearGradient></defs>'
           '<rect width="100%" height="100%" fill="#1a1d1b"/>']
    for n, (t, progress) in enumerate(times):
        c, r = n % columns, n // columns
        x, y = gap + c * (cw + gap), gap + r * (ch + 30)
        svg.append(f'<svg x="{x}" y="{y}" width="{cw}" height="{ch}" viewBox="0 0 {W} {H}"><rect width="{W}" height="{H}" fill="url(#bg)"/>{frame(t, progress, progress)}</svg>')
        svg.append(f'<text x="{x}" y="{y + ch + 20}" font-family="Helvetica, Arial, sans-serif" font-size="16" fill="#cfd8cf">t = {t:.2f} s'
                   + (f'   progress {int(progress * 100)} %' if progress else '') + '</text>')
    svg.append('</svg>')
    return '\n'.join(svg)


if __name__ == '__main__':
    out = sys.argv[1] if len(sys.argv) > 1 else os.path.join(HERE, 'preview.svg')
    moments = [(0.20, 0), (0.50, 0), (0.80, 0), (1.10, 0), (1.40, 0), (1.60, 0),
               (1.85, 0), (2.40, 0.10), (3.10, 0.30), (4.20, 0.55), (5.40, 0.80), (7.00, 1.0)]
    with open(out, 'w') as f:
        f.write(sheet(moments))
    print(out)
