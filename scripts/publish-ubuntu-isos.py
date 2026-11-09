#!/usr/bin/env python3
"""Publish existing Ubuntu live-ISO CI artifacts (iso/own) with source metadata.

Runs in GitHub Actions with its repository-scoped GITHUB_TOKEN via gh.
Does not build images or read local credentials. Tag format: ubuntu-YYYY.MM.DD.
"""
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys

WORKFLOW = 'iso-own.yml'
ARCHITECTURES = ('amd64', 'arm64')
MAX_SIZE = 2 * 1024 ** 3 - 1  # limit of a GitHub release asset


def iso_name(architecture):
    return f'totaljs-ubuntu-{architecture}.iso'


def api(repository, endpoint):
    return json.loads(subprocess.check_output(['gh', 'api', f'repos/{repository}/{endpoint}'], text=True))


def eligible(run, repository):
    return (run.get('status') == 'completed' and run.get('conclusion') == 'success'
            and run.get('head_branch') == 'main'
            and (run.get('head_repository') or {}).get('full_name') == repository)


def select(repository, architecture):
    runs = api(repository, f'actions/workflows/{WORKFLOW}/runs?status=completed&per_page=20')['workflow_runs']
    for run in runs:
        if not eligible(run, repository):
            continue
        artifacts = api(repository, f"actions/runs/{run['id']}/artifacts?per_page=100")['artifacts']
        matching = [a for a in artifacts if a['name'] == f'totaljs-ubuntu-{architecture}' and not a['expired']]
        if len(matching) == 1:
            return run, matching[0]
    return None


def sha256(path):
    digest = hashlib.sha256()
    with path.open('rb') as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b''):
            digest.update(chunk)
    return digest.hexdigest()


def recorded_checksum(sums, name):
    if not sums.exists():
        return None
    for line in sums.read_text().splitlines():
        parts = line.split(None, 1)
        if len(parts) == 2 and parts[1].lstrip('*').strip() == name:
            return parts[0]
    return None


def prepare(repository, architecture, run, artifact, workspace, destination):
    folder = workspace / architecture
    folder.mkdir(parents=True, exist_ok=True)
    download = folder / 'download'
    subprocess.run(['gh', 'run', 'download', str(run['id']), '--repo', repository,
                    '--name', artifact['name'], '--dir', str(download)], check=True)
    images = list(download.rglob('*.iso'))
    if len(images) != 1:
        raise ValueError(f'{architecture}: expected exactly one ISO, found {len(images)}')
    image = images[0]
    if image.is_symlink() or image.name != iso_name(architecture):
        raise ValueError('unexpected ISO filename: ' + image.name)
    if image.stat().st_size > MAX_SIZE:
        raise ValueError(f'{architecture}: larger than the 2 GiB limit of a release asset')
    for path in ('/live/vmlinuz', '/live/initrd', '/live/filesystem.squashfs'):
        subprocess.run(['xorriso', '-indev', str(image), '-ls', path], check=True, stdout=subprocess.DEVNULL)
    digest = sha256(image)
    recorded = recorded_checksum(download / 'SHA256SUMS', image.name)
    if recorded is not None and recorded != digest:
        raise ValueError(f'{architecture}: the checksum recorded by the build does not match the ISO')
    destination.mkdir(parents=True, exist_ok=True)
    final = destination / image.name
    shutil.move(str(image), final)
    return {
        'architecture': architecture, 'filename': final.name, 'sha256': digest, 'size': final.stat().st_size,
        'source_commit': run['head_sha'], 'build_run': run['html_url'],
        'artifact_id': artifact['id'], 'artifact_digest': artifact.get('digest'),
        'validation': 'Live boot (BIOS and UEFI on amd64, UEFI on arm64) and installer startup passed in the build workflow',
    }


def publish(tag, repository, revision):
    if not re.fullmatch(r'ubuntu-\d{4}\.\d{2}\.\d{2}(?:[.-][A-Za-z0-9]+)*', tag):
        raise ValueError('use an ubuntu-YYYY.MM.DD tag; v* tags are reserved for the legacy remastered ISO')
    existing = subprocess.run(['gh', 'release', 'view', tag, '--repo', repository],
                              stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    if existing.returncode == 0:
        raise ValueError('release already exists; refusing to replace its files')
    destination = Path('dist/ubuntu-release')
    if destination.exists():
        raise ValueError('release output already exists; use a clean workspace')
    workspace = Path('build/release-ubuntu')
    results, excluded = [], []
    for architecture in ARCHITECTURES:
        selection = select(repository, architecture)
        if selection is None:
            excluded.append(f'{architecture}: no eligible, unexpired CI artifact')
            continue
        run, artifact = selection
        try:
            results.append(prepare(repository, architecture, run, artifact, workspace, destination))
        except (subprocess.SubprocessError, OSError, ValueError) as error:
            print(f'::warning::{architecture} was not published: {error}', flush=True)
            if destination.exists():
                (destination / iso_name(architecture)).unlink(missing_ok=True)
            excluded.append(f'{architecture}: validation failed; see the publishing workflow logs')
    if not results:
        raise ValueError('no ISO passed publication checks')
    manifest = {'tag': tag, 'publisher_commit': revision, 'images': results, 'excluded': excluded}
    (destination / 'SOURCE.json').write_text(json.dumps(manifest, indent=2) + '\n')
    (destination / 'SHA256SUMS').write_text(''.join(f"{item['sha256']}  {item['filename']}\n" for item in results))
    notes = [
        '# Total.js Developer — Ubuntu preview', '',
        'Live installation image with a graphical installer. Choose the Desktop or the Server edition. An internet connection is required: the installer downloads Ubuntu 26.04 LTS packages and the current signed Total.js packages.', '',
        '| Architecture | Validation |', '| --- | --- |',
    ]
    for item in results:
        notes.append(f"| {item['architecture']} | {item['validation']} |")
    notes += ['', *[f"- {item['architecture']} build: [{item['source_commit'][:12]}]({item['build_run']})" for item in results]]
    if excluded:
        notes += ['', 'Not included in this release:', *['- ' + reason for reason in excluded]]
    notes += ['', '## Install', '',
              f'Instructions: https://github.com/{repository}/blob/{revision}/docs/install.md', '',
              'Use a UEFI virtual machine for arm64. After installation, remove the ISO and boot from the disk.', '',
              '## Verify the download', '', '```sh', 'sha256sum -c SHA256SUMS --ignore-missing', '```', '',
              'SOURCE.json records the original CI build and the ISO checksums. This is an independent live image built on Ubuntu packages with its own identity, not an official Ubuntu release, and it is not endorsed by Canonical. Ubuntu is a trademark of Canonical Ltd.']
    notes_file = workspace / 'notes.md'
    notes_file.parent.mkdir(parents=True, exist_ok=True)
    notes_file.write_text('\n'.join(notes) + '\n')
    assets = [str(destination / item['filename']) for item in results]
    assets += [str(destination / 'SHA256SUMS'), str(destination / 'SOURCE.json')]
    subprocess.run(['gh', 'release', 'create', tag, '--repo', repository, '--verify-tag',
                    '--target', revision, '--title', f'Total.js Developer — {tag} (preview)',
                    '--prerelease', '--notes-file', str(notes_file), *assets], check=True)
    print(json.dumps(manifest, indent=2))


if __name__ == '__main__':
    publish(sys.argv[1], os.environ['GITHUB_REPOSITORY'], os.environ['GITHUB_SHA'])
