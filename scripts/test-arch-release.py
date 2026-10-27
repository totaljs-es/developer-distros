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
        artifact = {'name': 'totaljs-developer-arch-aarch64-iso', 'expired': True}
        def api(repo, path):
            if '/workflows/' in path:
                return {'workflow_runs': [run_record()]}
            if '/jobs?' in path:
                return {'jobs': []}
            return {'artifacts': [artifact]}
        with patch.object(release, 'api', side_effect=api):
            self.assertIsNone(release.select(REPO, 'aarch64'))

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
                        raise subprocess.CalledProcessError(1, ['boot-check'])
                    destination.mkdir(parents=True)
                    name = 'totaljs-developer-arch-2026.10.27-aarch64.iso'
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
                    create = command.call_args.args[0]
                    self.assertIn('--prerelease', create)
                    self.assertFalse(any(arg.endswith('-x86_64.iso') for arg in create))
            finally:
                os.chdir(previous)


if __name__ == '__main__':
    unittest.main()
