#!/usr/bin/env python3
"""Update the installer's media checks after replacing GRUB and the seed.

Usage: update-md5.py ORIGINAL GRUB SEED OUTPUT [REMOVED_DIRECTORY ...]
The signed SHA256SUMS of the downloaded base ISO are verified separately.
"""
import hashlib
from pathlib import Path
import sys


def update(original, grub, seed, output, removed):
    replaced = {'boot/grub/grub.cfg': Path(grub)}
    for path in sorted(Path(seed).rglob('*')):
        if path.is_file():
            replaced['nocloud/' + path.relative_to(seed).as_posix()] = path
    lines = []
    for line in Path(original).read_text().splitlines():
        fields = line.split(maxsplit=1)
        if len(fields) != 2:
            raise ValueError('invalid md5sum.txt entry: ' + line)
        name = fields[1].removeprefix('*').removeprefix('./')
        if name in replaced or name.startswith('nocloud/'):
            continue
        if any(name == directory or name.startswith(directory + '/') for directory in removed):
            continue
        lines.append(line)
    for name, path in sorted(replaced.items()):
        digest = hashlib.md5(path.read_bytes()).hexdigest()
        lines.append(digest + '  ./' + name)
    Path(output).write_text('\n'.join(lines) + '\n')


if __name__ == '__main__':
    update(*sys.argv[1:5], [part.strip('/') for part in sys.argv[5:]])
