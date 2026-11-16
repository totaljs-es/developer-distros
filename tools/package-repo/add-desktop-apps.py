"""Add verified desktop app releases to the APT pool and architecture indexes."""

import hashlib
from pathlib import Path
import subprocess
import sys
import tempfile
from urllib.request import urlretrieve


ASSETS = (
    ('code-app', 'v1.0.1', 'TotalJSCode-linux-amd64.deb', 'total-js-code', '1.0.1', 'amd64',
     '298968bbc822da738dfc097de75a2155ec329f0f59de5f1ced8476eeecb2e0ef'),
    ('code-app', 'v1.0.1', 'TotalJSCode-linux-arm64.deb', 'total-js-code', '1.0.1', 'arm64',
     'f4ead49076a1499f1d17135e639d3f25d7c38e85e3c436561cd3c394eddedd7f'),
    ('totalmail-app', 'v1.0.0', 'TotalMail-1.0.0-linux-amd64.deb', 'total-mail', '1.0.0', 'amd64',
     '0c84c43ba60c26ec277958fb30aa290b5b2229716c33b6d9c7035adc73cdff55'),
)


def control_fields(stanza):
    return dict(line.split(': ', 1) for line in stanza.splitlines()
                if not line.startswith((' ', '\t')) and ': ' in line)


def import_apps(repository, indexes):
    with tempfile.TemporaryDirectory(dir=repository) as directory:
        pending = []
        for project, tag, asset, name, version, arch, expected in ASSETS:
            targets = [index for index in indexes if index.parent.name == f'binary-{arch}']
            if not targets:
                continue
            archive = Path(directory) / asset
            urlretrieve(f'https://github.com/totaljs-es/{project}/releases/download/{tag}/{asset}', archive)
            digest = hashlib.sha256(archive.read_bytes()).hexdigest()
            if digest != expected:
                raise ValueError(f'SHA-256 mismatch for {asset}')
            controls = subprocess.check_output(['bsdtar', '-xOf', archive, 'control.tar.gz'])
            control = subprocess.check_output(['bsdtar', '-xOf', '-', './control'], input=controls).decode().strip()
            fields = control_fields(control)
            if (fields['Package'], fields['Version'], fields['Architecture']) != (name, version, arch):
                raise ValueError(f'Unexpected package metadata for {asset}')
            relative = f'pool/main/t/{name}/{name}_{version}_{arch}.deb'
            stanza = f'{control}\nFilename: {relative}\nSize: {archive.stat().st_size}\nSHA256: {digest}'
            pending.append((archive, repository / relative, targets, name, stanza))

        for archive, destination, targets, name, stanza in pending:
            destination.parent.mkdir(parents=True, exist_ok=True)
            archive.replace(destination)
            for index in targets:
                entries = index.read_text().strip().split('\n\n')
                entries = [entry for entry in entries if control_fields(entry).get('Package') != name]
                index.write_text('\n\n'.join([*entries, stanza]) + '\n\n')


if __name__ == '__main__':
    import_apps(Path(sys.argv[1]), [Path(index) for index in sys.argv[2:]])
