#!/usr/bin/env python3
"""Exercise live-source staging and build refusal without mounting or installing."""
from pathlib import Path
import os
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class ArchCalamaresTests(unittest.TestCase):
    def stage(self, destination, architecture):
        return subprocess.run(['bash', str(ROOT / 'arch/calamares/stage-live.sh'),
                               str(destination), architecture], capture_output=True, text=True)

    def test_staged_sources_are_shared_and_hook_runs_inside_the_live_root(self):
        with tempfile.TemporaryDirectory() as folder:
            for architecture in ['amd64', 'arm64']:
                target = Path(folder) / architecture
                result = self.stage(target, architecture)
                self.assertEqual(result.returncode, 0, result.stderr)
                source = target / 'usr/share/totaljs-live/source'
                for relative in ['shared/calamares/render.py', 'shared/calamares/setup-live.sh',
                                 'shared/branding/logo-totaljs.svg', 'shared/branding/toto/LICENSE.md',
                                 'shared/branding/toto/toto-welcome.png']:
                    self.assertEqual((source / relative).read_bytes(), (ROOT / relative).read_bytes())
                wrapper = target / 'usr/lib/totaljs-live/configure-installer'
                self.assertTrue(os.access(wrapper, os.X_OK))
                self.assertIn('setup-live.sh arch ' + architecture, wrapper.read_text())
                hook = (target / 'etc/pacman.d/hooks/99-totaljs-live-installer.hook').read_text()
                self.assertIn('When = PostTransaction', hook)
                self.assertIn('Exec = /usr/lib/totaljs-live/configure-installer', hook)
                # Staging never configures the host or executes the installer.
                self.assertFalse((target / 'usr/share/totaljs-installer').exists())
                marker = source / 'keep'
                marker.write_text('preserve')
                self.assertNotEqual(self.stage(target, architecture).returncode, 0)
                self.assertEqual(marker.read_text(), 'preserve')

    def test_package_collection_accepts_arch_arm_compression(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            binaries = root / 'bin'
            binaries.mkdir()
            commands = {
                'id': '#!/bin/sh\necho 1000\n',
                'makepkg': "#!/bin/sh\npackage=\"$PWD/$(basename \"$PWD\")-1-1-any.pkg.tar.xz\"\nif [ \"${1:-}\" = --packagelist ]; then printf '%s\\n' \"$package\"; else printf 'package' > \"$package\"; fi\n",
            }
            for name, contents in commands.items():
                path = binaries / name
                path.write_text(contents)
                path.chmod(0o755)
            output = root / 'packages'
            result = subprocess.run(['bash', str(ROOT / 'arch/calamares/build-packages.sh'), str(output)],
                                    env=dict(os.environ, PATH=str(binaries) + os.pathsep + os.environ['PATH']),
                                    capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(sorted(path.name for path in output.iterdir()),
                             ['calamares-1-1-any.pkg.tar.xz', 'ckbcomp-1-1-any.pkg.tar.xz'])

    def test_host_root_and_unknown_architecture_are_rejected(self):
        self.assertNotEqual(self.stage('/', 'arm64').returncode, 0)
        with tempfile.TemporaryDirectory() as folder:
            target = Path(folder) / 'must-not-exist'
            self.assertNotEqual(self.stage(target, 'unknown').returncode, 0)
            self.assertFalse(target.exists())

    def test_invalid_build_flags_cannot_remove_existing_builds(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            for relative, output in [('arch/iso/build.sh', 'arch-iso'),
                                     ('arch/iso-arm/build.sh', 'arch-iso-arm')]:
                script = root / relative
                script.parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(ROOT / relative, script)
                marker = root / 'build' / output / 'keep'
                marker.parent.mkdir(parents=True)
                marker.write_text('preserve')
                result = subprocess.run(['bash', str(script)],
                                        env=dict(os.environ, KEY_FILE='unused', CALAMARES='invalid'),
                                        capture_output=True, text=True)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn('CALAMARES must be', result.stderr)
                self.assertEqual(marker.read_text(), 'preserve')

    def test_package_input_inside_disposable_build_is_rejected(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            script = root / 'arch/iso/build.sh'
            script.parent.mkdir(parents=True)
            shutil.copyfile(ROOT / 'arch/iso/build.sh', script)
            packages = root / 'build/arch-iso/packages'
            packages.mkdir(parents=True)
            marker = packages / 'keep'
            marker.write_text('preserve')
            result = subprocess.run(['bash', str(script)],
                                    env=dict(os.environ, KEY_FILE='unused', CALAMARES='1',
                                             CALAMARES_PACKAGES=str(packages)),
                                    capture_output=True, text=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn('outside the disposable', result.stderr)
            self.assertEqual(marker.read_text(), 'preserve')


if __name__ == '__main__':
    unittest.main()
