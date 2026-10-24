# Boot splash

The Plymouth theme `totaljs` for the Total.js Developer Distros: what is on the screen while the system starts.

1. **The logo comes together.** Its body, its light side and its arrow slide in from three sides.
2. **A flash**, and the parts give way to the whole logo, the official art with its shadows.
3. **A ring in the shape of the logo** (72 points along a hexagon) lights up with the progress of the boot, and a point of light goes around it all the time, so the screen never looks stopped. Behind the logo a soft light breathes.
4. It also draws the **passphrase of an encrypted disk** (the prompt and its asterisks) and the **messages** of the system.

It is a `script` theme, the kind that every Plymouth has, and it scales to any screen: it is drawn for 1080 pixels of height. The seven images weigh 350 KB in total, because they go into the initramfs.

## Files

- `totaljs/`: the theme, as it is installed in `/usr/share/plymouth/themes/totaljs/`: `totaljs.plymouth`, `totaljs.script` and the images.
- `generate.py`: draws the images as SVG (`svg/`) from the official logo (`../branding/logo-totaljs.svg`), in its three parts and whole.
- `export.sh`: makes the PNGs of `totaljs/` with Inkscape.
- `preview.py`: draws the choreography on a sheet of twelve frames, to see the movement without booting anything. It repeats the formulas of the script, and **the script is the source of truth**.

## Change it

Change `totaljs/totaljs.script` (the movement) or `generate.py` (the images), and run:

```bash
shared/plymouth/export.sh
python3 shared/plymouth/preview.py preview.svg     # then open it, or export it with Inkscape
```

Keep `preview.py` in step with the script when a formula changes.

## Try it

The workflow `plymouth` installs the theme in an Ubuntu with Plymouth, shows it in a virtual screen and keeps screenshots of the moments of the animation. On a computer with Plymouth, as root: `plymouth-set-default-theme -R totaljs` and restart.

## What is not checked

The script was written without a Plymouth at hand to run it; the workflow is what runs it. The timing assumes that the refresh function is called about 50 times a second, as Plymouth documents.
