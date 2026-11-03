#!/usr/bin/env python3
"""Publication policy tests; no network requests, VM, or GitHub writes."""
import contextlib
import io
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('arch_release', ROOT / 'scripts/publish-arch-isos.py')
release = importlib.util.module_from_spec(spec)
spec.loader.exec_module(release)
REPO = 'totaljs-es/developer-distros'


def run_record(conclusion='success'):
    return {'id': 123, 'status': 'completed', 'conclusion': conclusion,
            'head_branch': 'main', 'head_repository': {'full_name': REPO}}


class PublicationPolicy(unittest.TestCase):
    def test_arm_requires_success_and_matching_source(self):
        self.assertTrue(release.eligible(run_record(), 'aarch64', REPO, []))
        self.assertFalse(release.eligible(run_record('failure'), 'aarch64', REPO, []))
        fork = run_record()
        fork['head_repository']['full_name'] = 'other/fork'
        self.assertFalse(release.eligible(fork, 'aarch64', REPO, []))

    def test_x86_requires_successful_build_even_when_rechecking_boot(self):
        record = run_record('failure')
        self.assertTrue(release.eligible(record, 'x86_64', REPO, [{'name': 'build', 'conclusion': 'success'}]))
        self.assertFalse(release.eligible(record, 'x86_64', REPO, [{'name': 'build', 'conclusion': 'failure'}]))

    def test_expired_artifacts_are_not_selected(self):
        artifact = {'name': 'totaljs-arch-arm64', 'expired': True}
        def api(repo, path):
            if '/workflows/' in path:
                return {'workflow_runs': [run_record()]}
            if '/jobs?' in path:
                return {'jobs': []}
            return {'artifacts': [artifact]}
        with patch.object(release, 'api', side_effect=api):
            self.assertIsNone(release.select(REPO, 'aarch64'))

    def test_public_prepare_preserves_exact_short_filenames(self):
        for architecture, filename in release.ISO_NAMES.items():
            with self.subTest(architecture=architecture), tempfile.TemporaryDirectory() as folder:
                root = Path(folder)
                record = dict(run_record(), head_sha='a' * 40, html_url='https://example.test/run')
                artifact = {'id': 456, 'name': release.TARGETS[architecture][1]}

                def command(args, **kwargs):
                    if args[:3] == ['gh', 'run', 'download']:
                        target = Path(args[args.index('--dir') + 1])
                        target.mkdir(parents=True)
                        (target / filename).write_bytes(b'validated image fixture')
                    return subprocess.CompletedProcess(args, 0)

                with patch.object(release.subprocess, 'run', side_effect=command), \
                     patch.object(release.subprocess, 'check_output', return_value='TOTALJS_202611'):
                    result = release.prepare(REPO, architecture, record, artifact,
                                             root / 'work', root / 'public')
                self.assertEqual(result['filename'], filename)
                self.assertEqual((root / 'public' / filename).read_bytes(), b'validated image fixture')
                self.assertEqual(result['sha256'], release.sha256(root / 'public' / filename))

    def test_private_and_wrong_architecture_images_are_never_prepared_for_publication(self):
        for filename in ['totalvm-arch-arm64.iso', 'totalvm-ubuntu-arm64.iso',
                         'totaljs-arch-amd64.iso']:
            with self.subTest(filename=filename), tempfile.TemporaryDirectory() as folder:
                root = Path(folder)

                def download(args, **kwargs):
                    target = Path(args[args.index('--dir') + 1])
                    target.mkdir(parents=True)
                    (target / filename).write_bytes(b'not a public ARM image')
                    return subprocess.CompletedProcess(args, 0)

                with patch.object(release.subprocess, 'run', side_effect=download) as command, \
                     patch.object(release.subprocess, 'check_output') as inspect:
                    with self.assertRaisesRegex(ValueError, 'unexpected ISO filename'):
                        release.prepare(REPO, 'aarch64', run_record(), {'name':'fixture'},
                                        root / 'work', root / 'public')
                    inspect.assert_not_called()
                    self.assertEqual(command.call_count, 1)
                self.assertFalse((root / 'public').exists())

    def test_ubuntu_tag_never_starts_publication(self):
        with patch.object(release.subprocess, 'run') as command:
            with self.assertRaises(ValueError):
                release.publish('v0.1.0', REPO, 'commit')
            command.assert_not_called()

    def test_failed_x86_is_excluded_without_blocking_valid_arm(self):
        previous = Path.cwd()
        with tempfile.TemporaryDirectory() as folder:
            try:
                os.chdir(folder)
                def prepare(repo, architecture, run, artifact, workspace, destination):
                    if architecture == 'x86_64':
                        (destination / 'totaljs-arch-amd64.iso').write_bytes(b'unvalidated fixture')
                        raise subprocess.CalledProcessError(1, ['boot-check'])
                    destination.mkdir(parents=True)
                    name = 'totaljs-arch-arm64.iso'
                    (destination / name).write_bytes(b'validated image fixture')
                    return {'architecture': architecture, 'filename': name,
                            'sha256': release.sha256(destination / name),
                            'source_commit': 'a' * 40, 'build_run': 'https://example.test/run',
                            'validation': 'fixture validation'}
                with patch.object(release, 'select', return_value=({}, {})), \
                     patch.object(release, 'prepare', side_effect=prepare), \
                     patch.object(release.subprocess, 'run', return_value=subprocess.CompletedProcess([], 1)) as command:
                    with contextlib.redirect_stdout(io.StringIO()):
                        release.publish('arch-2026.10.27', REPO, 'publisher')
                    manifest = json.loads(Path('dist/arch-release/SOURCE.json').read_text())
                    self.assertEqual([item['architecture'] for item in manifest['images']], ['aarch64'])
                    self.assertTrue(manifest['excluded'][0].startswith('x86_64:'))
                    self.assertFalse(Path('dist/arch-release/totaljs-arch-amd64.iso').exists())
                    create = command.call_args.args[0]
                    self.assertIn('--prerelease', create)
                    self.assertFalse(any(arg.endswith('totaljs-arch-amd64.iso') for arg in create))
            finally:
                os.chdir(previous)


if __name__ == '__main__':
    unittest.main()
