# Wallpapers

Six wallpapers for the desktop of the Total.js Developer Distros, drawn with code so that they are reproducible, small and can be made for any size. All of them use the official logo of Total.js (`../branding/logo-totaljs.svg`), the green of the logo and a graphite background, with a fine grain that keeps the dark gradients from showing bands.

| | |
|---|---|
| `signal` | The logo in the middle, lit from behind, and its silhouette repeated outwards as rings that fade |
| `lattice` | A honeycomb that fades from the lower right, where the logo is |
| `contour` | Contour lines, like a map of a hill, with the logo at the top |
| `horizon` | Night, with the land in layers and the logo above the horizon |
| `mascot` | The logo out of focus, and the mascot (`../branding/mascot.png`) in the corner |
| `daylight` | The light one |

## Files

- `4k/*.jpg`: the wallpapers at 3840 x 2160 (16:9), JPEG quality 90. These are the ones that go into the distros.
- `svg/*.svg`: the source of each one. They are generated: do not edit them by hand.
- `generate.py`: draws the SVGs (Python 3, standard library only). The compositions are in the space of 3840 x 2160.
- `export.sh`: runs the generator and makes the JPEGs with Inkscape and `sips` (macOS) or ImageMagick.

## Change one

Change `generate.py` and run:

```bash
shared/wallpapers/export.sh        # all of them, 3840 pixels wide
JPEG_QUALITY=85 shared/wallpapers/export.sh
```

`node scripts/check.js` checks that `svg/` is what `generate.py` makes, so a change that is not exported does not pass.

## Other proportions

The compositions are for 16:9. A 16:10 screen or an ultra-wide one needs its own composition (the logo and the rings are placed for 16:9), not a crop: it is a new function in `generate.py`.

## License

To be decided together with the rest of the artwork of the repository (see the README of the repository).
