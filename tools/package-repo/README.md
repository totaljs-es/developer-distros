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

## The packages of the layer

`packages/<name>/` has the source of a package: `control`, the maintainer scripts, `files/` (what it installs, as it is) and, optionally, `include`: lines `<path in this repository> <path in the package>`, for what the repository already has and must not be copied twice (the splash theme of `shared/plymouth`, the wallpapers of `shared/wallpapers`). `build.sh` builds all of them. `test-install.sh` installs them in a clean Ubuntu and checks them.

## Where the repository is served from

`build.sh` writes the repository to `build/site/repo` (not committed) and the address that the packages will update from is written inside them. Both can be set:

```sh
BASE_URL=https://packages.example.org/repo tools/package-repo/build.sh
```

| Variable | Default | What it is |
|---|---|---|
| `BASE_URL` | `https://totaljs-es.github.io/developer-distros/repo` | The address inside the packages: where every installed system will look for updates. Set the final one before a release. |
| `REPO_OUT` | `build/site/repo` | Where the repository is written. `WEBSITE_ROOT` writes into `public/repo` of a website, as before. |
| `SUITES` | `resolute` | The Ubuntu series (26.04 is the one of this repository; the images of TotalVM, on 24.04, keep their own repository at totalvm.totaljs.es). The package writes the source of APT with the series of the system it is installed on. |
| `DEB_ARCHES` | `arm64 amd64` | The architectures of the APT indexes. The packages are `Architecture: all`, so they are the same files. |
| `ARCH_DIRS` | `aarch64 x86_64` | The directories of Pacman (`$arch` of pacman). Same files, same database and signatures. |
| `TOTALJS_REPO_GNUPGHOME`, `TOTALJS_REPO_KEY` | the key of Total.js on this computer | What signs the repository. |

The key of Total.js is never in GitHub. The workflow `package-repo` builds the repository with a throwaway key and uses it with the real APT of the runner: `apt-get update`, the install (the package writes its own source), the removal, and the series `resolute`.

## Publish it with GitHub Pages

```sh
tools/package-repo/build.sh
PAGES_CNAME=packages.example.org tools/package-repo/publish-pages.sh          # prepares build/pages
PAGES_CNAME=packages.example.org tools/package-repo/publish-pages.sh --push   # and publishes it
```

Each publication is a **complete** repository, built from everything that is in `packages/`: to add or update a package, change it (and its `Version` in `control`), run `build.sh` and `publish-pages.sh`, and publish the branch. Nothing is added by hand to the branch `pages`, and the versions that are no longer built are no longer in it. `publish-pages.sh` leaves the prepared branch in `build/pages` and also as the branch `pages` of this repository (replacing it), so it can be published with the tool that publishes `main` when the terminal has no credentials. **Do the work in `main`**: while the branch `pages` is checked out the folder has only the files of the repository of packages.

The branch `pages` has a single commit that is replaced each time (a repository is a set of signed files, and the old versions of binary files would only make the repository grow). In the settings of the repository, *Pages* serves the branch `pages` from `/`. `PAGES_CNAME` is only for a custom domain, which also needs a `CNAME` record in its DNS.

An installed system with the old address (`totalvm.totaljs.es/repo`) keeps updating from it. The version 1.0.9 of `totaljs-developer-release` writes its source with the new address, so those systems move to it the first time they install that version.
