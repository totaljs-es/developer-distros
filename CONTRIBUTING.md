# Contributing

Thank you for helping. Issues and pull requests are welcome.

## Before you start

- **Bugs and ideas:** open an issue and say which edition you use (desktop or server), whether it is a virtual machine or a computer, and what you expected to happen.
- **A change:** open a pull request against `main`. A small, focused change is easier to review than a large one.

## How the repository is organised

`packages/<name>/` is one package: a `control` file, the maintainer scripts and `files/` (what it installs). `docs/layer.md` lists them and explains the rules they follow, such as
never shipping a file that another package of Ubuntu owns, and never touching what the person edited. `iso/ubuntu/` has the installer, and `tools/package-repo/` builds the repository and tests it.

## Checks

```bash
node scripts/check.js
```

It validates the JSON files, the syntax of every shell script and that the documentation names files that exist. It needs Node.js 20 or newer. The rest is tested in GitHub Actions
(`package-repo` installs the packages in a clean Ubuntu 26.04 and starts the desktop; `iso-ubuntu` installs the system in QEMU), so a change to a package is only done when those pass.

## Style

- Documentation and comments are in English, short and plain: say what a thing does and why, not the history of how it was made.
- Shell scripts use `set -euo pipefail`, quote every variable, and do not hide errors.
- A package does not assume a user name, does not download anything big in its `postinst`, and does not hardcode an architecture.
- The look of the desktop (colors, icons, spacing) follows what is already there: ask before changing it.

## License

By contributing you agree that your work is under the license of the repository: MIT for the code and CC BY-SA 4.0 for the artwork (see [`LICENSE`](LICENSE) and [`LICENSE-ARTWORK`](LICENSE-ARTWORK)).
