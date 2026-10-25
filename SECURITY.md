# Security

## Reporting a vulnerability

Please **do not open a public issue** for a security problem. Write to **hola@totaljs.es** with:

- what you found and where (the package, the file or the service),
- how to reproduce it, and which edition and version you used,
- what you think the impact is.

We will answer as soon as we can, work on a fix, and credit you when it is published if you want us to.

## What is covered

The latest release, and the packages of the repository at <https://totaljs-es.github.io/developer-distros/>. The software that the packages install (Ubuntu, Node.js, Docker, PostgreSQL, Firefox...)
has its own security teams: report problems of those to them.

## Things you should know

- The repository is signed with one key (`repo/totaljs-developer.gpg`). `apt` checks the signature of everything it installs from it.
- The services of the development environment (the reverse proxy, Code, Flow, PostgreSQL, pgAdmin) are meant for **your own machine or network**. PostgreSQL is not published outside the machine and the
  password of pgAdmin is different on each system. Anyone in the group `docker` can control Docker, which is equivalent to being the administrator: add only people that you trust.
- The firewall `ufw` is installed and is **not enabled** by default; `docs/using.md` says how to enable it.
