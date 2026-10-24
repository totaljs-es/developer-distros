# Total.js Developer package repository

`build.sh` publishes the signed APT and Pacman metadata served by
`totalvm.totaljs.es` and copies the local bootstrap packages into the image
builder assets.

The private signing key lives outside the project in
`~/.config/totaljs/repository-signing`. Only the public key is published or
included in images.

```sh
tools/package-repo/build.sh
```

The `totaljs-developer-release` package configures trust, the package source and
the shared TotalVM runtime helpers. It must stay independent from desktop-only
packages so Server Edition installations can receive the same base updates
without pulling graphical tools.

`totaljs-desktop` owns narrowly scoped desktop migrations. Version `1.0.5-1`
adds a complete monochrome icon set to the managed Openbox root menu and
includes the volume-tray supervisor. The supervisor replaces any stale process
left by a previous graphical session,
then waits for Tint2 to own the notification area before launching `pasystray`.
It updates both `/etc/skel` and existing user profiles. Migrations must remain
idempotent and must not replace user projects, Compose files or unrelated
home-directory configuration.
