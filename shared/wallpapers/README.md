# Wallpapers

Twelve wallpapers for the desktop of the Total.js Developer Distros, drawn with code so that they are reproducible, small and can be made for any size. All of them use the official logo of Total.js (`../branding/logo-totaljs.svg`), the green of the logo and a graphite background, with a fine grain that keeps the dark gradients from showing bands.

| | |
|---|---|
| `signal` | The logo in the middle, lit from behind, and its silhouette repeated outwards as rings that fade |
| `lattice` | A honeycomb that fades from the lower right, where the logo is |
| `contour` | Contour lines, like a map of a hill, with the logo at the top |
| `horizon` | Night, with the land in layers and the logo above the horizon |
| `mascot` | The logo out of focus, and the mascot (`../branding/mascot.png`) in the corner |
| `daylight` | The light one |
| `ember` | Warm ribbons of light on aubergine, with the logo at the start of them |
| `aubergine` | Soft lights of aubergine, magenta and orange, with the logo calm in the middle |
| `sunrise` | Bands of light around the logo, from aubergine to orange |
| `prism` | Sharp facets in blue, lit around the logo |
| `blueprint` | A technical drawing: a grid, marks and the construction lines of the logo |
| `syntax` | The shape of code, in bars, like an editor out of focus, with a calm place for the logo |

The first six are the identity of Total.js (graphite and the green of the logo). The last six are for people who like the colors of the two distros that Total.js runs on: `ember`, `aubergine` and `sunrise` use an aubergine and orange palette (Ubuntu), `prism`, `blueprint` and `syntax` a blue one (Arch). They take the **colors only**: the logos and marks of Ubuntu and Arch are not used, and the desktop of the distros stays the same on both.

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
