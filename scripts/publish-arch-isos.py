#!/usr/bin/env python3
"""Publish existing Arch CI ISOs with source metadata and fresh x86 boot checks.

Runs in GitHub Actions with its repository-scoped GITHUB_TOKEN via gh.
Does not build images, read local credentials, or publish Ubuntu images.
"""
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys

TARGETS = {
    'aarch64': ('arch-iso-arm.yml', 'totaljs-developer-arch-aarch64-iso'),
    'x86_64': ('arch-iso.yml', 'totaljs-developer-arch-x86_64-iso'),
}


def api(repository, endpoint):
    return json.loads(subprocess.check_output(['gh', 'api', f'repos/{repository}/{endpoint}'], text=True))


def eligible(run, architecture, repository, jobs):
    if run.get('status') != 'completed' or run.get('head_branch') != 'main':
        return False
    if (run.get('head_repository') or {}).get('full_name') != repository:
        return False
    if architecture == 'aarch64':
        return run.get('conclusion') == 'success'
    # A prior boot-harness failure is allowed only because this script repeats
    # that check before publication. A failed image build is never accepted.
    return any(job['name'] == 'build' and job['conclusion'] == 'success' for job in jobs)


def select(repository, architecture):
    workflow, artifact_name = TARGETS[architecture]
    runs = api(repository, f'actions/workflows/{workflow}/runs?status=completed&per_page=20')['workflow_runs']
    for run in runs:
        jobs = api(repository, f"actions/runs/{run['id']}/jobs?per_page=100")['jobs']
        if not eligible(run, architecture, repository, jobs):
            continue
        artifacts = api(repository, f"actions/runs/{run['id']}/artifacts?per_page=100")['artifacts']
        matching = [artifact for artifact in artifacts if artifact['name'] == artifact_name and not artifact['expired']]
        if len(matching) == 1:
            return run, matching[0]
    return None


def sha256(path):
    digest = hashlib.sha256()
    with path.open('rb') as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b''):
            digest.update(chunk)
    return digest.hexdigest()


def prepare(repository, architecture, run, artifact, workspace, destination):
    folder = workspace / architecture
    folder.mkdir(parents=True, exist_ok=True)
    subprocess.run(['gh', 'run', 'download', str(run['id']), '--repo', repository,
                    '--name', artifact['name'], '--dir', str(folder / 'download')], check=True)
    images = list((folder / 'download').rglob('*.iso'))
    if len(images) != 1:
        raise ValueError(f'{architecture}: expected exactly one ISO, found {len(images)}')
    image = images[0]
    if image.is_symlink() or not image.name.startswith('totaljs-developer-arch-') or not image.name.endswith(f'-{architecture}.iso'):
        raise ValueError('unexpected ISO filename: ' + image.name)
    # Read the volume metadata and filesystem from the downloaded image itself.
    label = subprocess.check_output(['python3', 'arch/iso/read-label.py', str(image)], text=True).strip()
    if not label.startswith('TOTALJS_'):
        raise ValueError('unexpected ISO label: ' + label)
    required = (['/arch/boot/aarch64/Image', '/arch/boot/aarch64/initramfs-linux.img', '/arch/aarch64/airootfs.sfs']
                if architecture == 'aarch64' else ['/arch/boot/x86_64/vmlinuz-linux', '/arch/boot/x86_64/initramfs-linux.img'])
    for path in required:
        subprocess.run(['xorriso', '-indev', str(image), '-ls', path], check=True,
                       stdout=subprocess.DEVNULL)
    if architecture == 'x86_64':
        env = dict(os.environ, WORK_DIR=str(folder / 'check'), BOOT_TIMEOUT='900')
        subprocess.run(['bash', 'arch/iso/test-boot.sh', str(image)], check=True, env=env, timeout=960)
    destination.mkdir(parents=True, exist_ok=True)
    final = destination / image.name
    shutil.move(image, final)
    return {
        'architecture': architecture, 'filename': final.name,
        'sha256': sha256(final), 'size': final.stat().st_size, 'volume_label': label,
        'source_commit': run['head_sha'], 'build_run': run['html_url'],
        'artifact_id': artifact['id'], 'artifact_digest': artifact.get('digest'),
        'validation': ('UEFI live boot passed in the original ARM workflow' if architecture == 'aarch64'
                       else 'Extracted kernel/initramfs live boot passed again before publication; firmware menus and disk installation not tested'),
    }


def publish(tag, repository, revision):
    if not re.fullmatch(r'arch-\d{4}\.\d{2}\.\d{2}(?:[.-][A-Za-z0-9]+)*', tag):
        raise ValueError('use an arch-YYYY.MM.DD tag; v* tags are reserved for Ubuntu')
    existing = subprocess.run(['gh', 'release', 'view', tag, '--repo', repository],
                              stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    if existing.returncode == 0:
        raise ValueError('release already exists; refusing to replace its files')
    destination = Path('dist/arch-release')
    if destination.exists():
        raise ValueError('release output already exists; use a clean workspace')
    workspace = Path('build/release-arch')
    results, excluded = [], []
    for architecture in TARGETS:
        selection = select(repository, architecture)
        if selection is None:
            excluded.append(f'{architecture}: no eligible, unexpired CI artifact')
            continue
        run, artifact = selection
        try:
            results.append(prepare(repository, architecture, run, artifact, workspace, destination))
        except (subprocess.SubprocessError, OSError, ValueError) as error:
            print(f'::warning::{architecture} was not published: {error}', flush=True)
            # Remove an unvalidated image if a later verification failed.
            if destination.exists():
                for path in destination.glob(f'*-{architecture}.iso'):
                    path.unlink()
            excluded.append(f'{architecture}: validation failed; see the publishing workflow logs')
    if not results:
        raise ValueError('no ISO passed publication checks')
    manifest = {'tag': tag, 'publisher_commit': revision, 'images': results, 'excluded': excluded}
    (destination / 'SOURCE.json').write_text(json.dumps(manifest, indent=2) + '\n')
    (destination / 'SHA256SUMS').write_text(''.join(f"{item['sha256']}  {item['filename']}\n" for item in results))
    notes = [
        '# Total.js Developer — Arch preview', '',
        'Installation images for the desktop and server editions. An internet connection is required: the installer downloads Arch/Arch Linux ARM and the current signed Total.js packages.', '',
        '| Architecture | Base | Validation |', '| --- | --- | --- |',
    ]
    for item in results:
        base = 'Arch Linux ARM' if item['architecture'] == 'aarch64' else 'Arch Linux'
        notes.append(f"| {item['architecture']} | {base} | {item['validation']} |")
    notes += ['', *[f"- {item['architecture']} build: [{item['source_commit'][:12]}]({item['build_run']})" for item in results]]
    if excluded:
        notes += ['', 'Not included in this release:', *['- ' + reason for reason in excluded]]
    notes += ['', '## Install', '',
              f'Instructions: https://github.com/{repository}/blob/{revision}/docs/install-arch.md', '',
              'Use a UEFI virtual machine for aarch64. After installation, remove the ISO and boot from the disk. The boot animation is not yet verified across VM graphics backends; its absence alone does not establish an installation failure.', '',
              '## Verify the download', '', '```sh', 'sha256sum -c SHA256SUMS --ignore-missing', '```', '',
              'SOURCE.json records the original CI build and the ISO checksums. These are preview images maintained by Total.js Developer, not official Arch Linux or Arch Linux ARM releases. No endorsement or support by those projects is implied. Ubuntu installer images are not part of this release.']
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
