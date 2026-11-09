#!/usr/bin/env python3
"""Check the preview's isolation and shared assets without running an installer."""
import importlib.util
import itertools
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('calamares_preview', ROOT / 'shared/calamares/render.py')
preview = importlib.util.module_from_spec(spec)
spec.loader.exec_module(preview)


def read(path):
    return json.loads(path.read_text())


class PreviewTests(unittest.TestCase):
    def test_every_build_identity_is_non_installing_and_uses_shared_assets(self):
        with tempfile.TemporaryDirectory() as folder:
            for base, arch, edition in itertools.product(
                    ['ubuntu', 'arch'], ['amd64', 'arm64'], ['desktop', 'server']):
                with self.subTest(base=base, arch=arch, edition=edition):
                    output = Path(folder) / f'{base}-{arch}-{edition}'
                    preview.render(ROOT, output, base, arch, edition)
                    settings = read(output / 'settings.conf')
                    # No execution phase, disk discovery, user jobs or completion/reboot.
                    self.assertEqual(settings['sequence'], [{'show': ['welcome', 'locale', 'keyboard']}])
                    self.assertFalse(settings['dont-chroot'])
                    self.assertFalse(read(output / 'preview.json')['can_install'])
                    self.assertEqual(read(output / 'preview.json')['installation'], 'online')
                    self.assertFalse(read(output / 'modules/locale.conf')['adjustLiveTimezone'])
                    self.assertFalse(read(output / 'modules/keyboard.conf')['useLocale1'])
                    self.assertEqual(read(output / 'modules/welcome.conf')['geoip']['style'], 'none')
                    self.assertEqual(settings['modules-search'], ['local'])
                    self.assertTrue((output / 'qml').is_symlink())
                    self.assertEqual((output / 'qml').readlink(), Path('/usr/share/calamares/qml'))
                    brand = output / 'branding' / settings['branding']
                    metadata = read(brand / 'branding.desc')
                    self.assertEqual(metadata['componentName'], brand.name)
                    self.assertIn('Preview', metadata['strings']['productName'])
                    self.assertEqual(metadata['uploadServer']['type'], 'none')
                    for image in metadata['images'].values():
                        self.assertTrue((brand / image).is_file(), image)
                    self.assertTrue((brand / metadata['slideshow']).is_file())
                    for name, source in {
                        'logo-totaljs.svg': 'logo-totaljs.svg',
                        'totalvm.png': 'totalvm/totalvm.png',
                        'TOTALVM-README.md': 'totalvm/README.md',
                    }.items():
                        self.assertEqual((brand / name).read_bytes(), (ROOT / 'shared/branding' / source).read_bytes())

    def test_existing_directory_is_preserved(self):
        with tempfile.TemporaryDirectory() as folder:
            output = Path(folder)
            marker = output / 'user-configuration'
            marker.write_text('keep me')
            with self.assertRaisesRegex(ValueError, 'already exists'):
                preview.render(ROOT, output, 'ubuntu', 'amd64', 'desktop')
            self.assertEqual(marker.read_text(), 'keep me')
            self.assertEqual(list(output.iterdir()), [marker])

    def test_missing_sources_do_not_create_output(self):
        with tempfile.TemporaryDirectory() as folder:
            output = Path(folder) / 'output'
            with self.assertRaisesRegex(ValueError, 'Missing source'):
                preview.render(folder, output, 'arch', 'arm64', 'server')
            self.assertFalse(output.exists())

    def test_cli_rejects_unknown_architecture_before_writing(self):
        with tempfile.TemporaryDirectory() as folder:
            output = Path(folder) / 'output'
            result = subprocess.run([
                sys.executable, str(ROOT / 'shared/calamares/render.py'),
                '--base', 'ubuntu', '--arch', 'unknown', '--output', str(output),
            ], capture_output=True, text=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertFalse(output.exists())

    def test_output_inside_sources_is_rejected(self):
        output = ROOT / 'shared/calamares/branding/recursive-output'
        with self.assertRaisesRegex(ValueError, 'outside'):
            preview.render(ROOT, output, 'ubuntu', 'amd64', 'desktop')
        self.assertFalse(output.exists())


if __name__ == '__main__':
    unittest.main()
