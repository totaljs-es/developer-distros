#!/usr/bin/env python3
"""Draws the images of the boot splash (Plymouth theme `totaljs`) as SVG, from the official logo of Total.js.

    python3 shared/plymouth/generate.py [out-dir]

The logo is drawn in its three parts (the body, the light side and the arrow), so that the splash can put it together, and
once complete: the final image has the shadows of the official art. Everything lives in a square of 1024 x 1024 in which the
logo is 560 pixels high and centered, so that the script places all the images in the same spot.
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, '..', 'wallpapers'))
import generate as wp   # the logo, its paths and its colors

SIDE = 1024
LOGO = 560


def canvas(body, defs=''):
    return f'<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="{SIDE}" height="{SIDE}" viewBox="0 0 {SIDE} {SIDE}"><defs>{defs}</defs>{body}</svg>\n'


def piece(d, color, shift=0.0, evenodd=False):
    """One part of the logo, in the position that it has in the logo."""
    k = LOGO / wp.PATH_H
    rule = ' fill-rule="evenodd"' if evenodd else ''
    return canvas(f'<g transform="translate({SIDE / 2},{SIDE / 2}) scale({k:.5f}) translate(-{wp.PATH_CENTER},-{wp.PATH_CENTER})">'
                  f'<path d="{d}" transform="translate(0,{shift})" fill="{color}"{rule}/></g>')


def images():
    out = {}
    out['body'] = piece(wp.LOGO_SHAPE, wp.GREEN, evenodd=True)
    out['side'] = piece(wp.LOGO_LIGHT[1], wp.LIGHT)
    out['arrow'] = piece(wp.LOGO_LIGHT[0], wp.LIGHT, shift=wp.LOGO_ARROW_SHIFT)
    out['logo'] = canvas(f'<g style="fill-rule:evenodd;clip-rule:evenodd" transform="translate({SIDE / 2},{SIDE / 2}) scale({LOGO / wp.LOGO_H:.5f}) translate(-63,-63)">{wp.LOGO_BODY}</g>', wp.LOGO_DEFS)
    out['glow'] = canvas(f'<rect width="{SIDE}" height="{SIDE}" fill="url(#g)"/>',
                         f'<radialGradient id="g" cx="0.5" cy="0.5" r="0.5"><stop offset="0" stop-color="{wp.LIGHT}" stop-opacity="0.85"/>'
                         f'<stop offset="0.35" stop-color="{wp.GREEN}" stop-opacity="0.32"/><stop offset="1" stop-color="{wp.GREEN}" stop-opacity="0"/></radialGradient>')
    # the points of the ring: a dim one that is always there, and a lit one that the animation turns up and down
    for name, color, op in (('dot-off', '#5b6f63', 1.0), ('dot-on', wp.LIGHT, 1.0)):
        out[name] = (f'<svg xmlns="http://www.w3.org/2000/svg" width="32" height="32" viewBox="0 0 32 32"><defs><radialGradient id="d" cx="0.5" cy="0.5" r="0.5">'
                     f'<stop offset="0" stop-color="{color}" stop-opacity="{op}"/><stop offset="0.55" stop-color="{color}" stop-opacity="{op}"/>'
                     f'<stop offset="1" stop-color="{color}" stop-opacity="0"/></radialGradient></defs><circle cx="16" cy="16" r="16" fill="url(#d)"/></svg>\n')
    return out


if __name__ == '__main__':
    out = sys.argv[1] if len(sys.argv) > 1 else os.path.join(HERE, 'svg')
    os.makedirs(out, exist_ok=True)
    for name, text in images().items():
        with open(os.path.join(out, name + '.svg'), 'w') as f:
            f.write(text)
        print(os.path.join(out, name + '.svg'))
