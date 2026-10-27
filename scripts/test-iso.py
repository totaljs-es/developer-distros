#!/usr/bin/env python3
"""Regression checks for ISO plumbing. No real VM is started by these tests."""
import hashlib
import importlib.util
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('media', ROOT / 'iso/ubuntu/update-md5.py')
media = importlib.util.module_from_spec(spec)
spec.loader.exec_module(media)


class MediaChecks(unittest.TestCase):
    def test_replaced_added_and_removed_files(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            seed = root / 'seed'
            seed.mkdir()
            (seed / 'user-data').write_text('new seed')
            (seed / 'install-layer.sh').write_text('new installer')
            grub = root / 'grub.cfg'
            grub.write_text('new menu')
            original = root / 'original'
            original.write_text('0' * 32 + '  ./boot/grub/grub.cfg\n' +
                                '1' * 32 + '  ./pool/a.deb\n' +
                                '2' * 32 + '  ./dists/Release\n' +
                                '3' * 32 + '  ./nocloud/obsolete\n')
            for removed in ([], ['pool'], ['pool', 'dists']):
                output = root / 'updated'
                media.update(original, grub, seed, output, removed)
                entries = {line.split(maxsplit=1)[1]: line.split()[0]
                           for line in output.read_text().splitlines()}
                self.assertEqual(entries['./boot/grub/grub.cfg'], hashlib.md5(b'new menu').hexdigest())
                self.assertEqual(entries['./nocloud/user-data'], hashlib.md5(b'new seed').hexdigest())
                self.assertIn('./nocloud/install-layer.sh', entries)
                self.assertNotIn('./nocloud/obsolete', entries)
                self.assertEqual('./pool/a.deb' in entries, 'pool' not in removed)
                self.assertEqual('./dists/Release' in entries, 'dists' not in removed)


class ArchBootChecks(unittest.TestCase):
    def run_boot(self, mode):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            binaries = root / 'bin'
            binaries.mkdir()
            xorriso = binaries / 'xorriso'
            xorriso.write_text('''#!/usr/bin/env python3
import pathlib, sys
if '-pvd_info' in sys.argv:
    print("Volume Id    : 'TOTALJS_202610'")
else:
    dest = pathlib.Path(sys.argv[-1])
    dest.mkdir(exist_ok=True)
    for name in ['vmlinuz-linux', 'initramfs-linux.img']:
        (dest / name).touch()
''')
            qemu = binaries / 'qemu-system-x86_64'
            qemu.write_text('''#!/usr/bin/env python3
import os, sys, time
args = sys.argv[1:]
cmdline = args[args.index('-append') + 1]
assert 'archisolabel=TOTALJS_202610 ' in cmdline, cmdline
assert "'" not in cmdline, cmdline
mode = os.environ['FAKE_BOOT_MODE']
if mode == 'banner':
    print('Total.js Developer, installation medium', flush=True)
elif mode == 'getty':
    print('Reached target \\x1b[1mMulti-User System\\x1b[0m', flush=True)
    print('Started \\x1b[1mGetty on tty1\\x1b[0m', flush=True)
elif mode == 'partial':
    print('Reached target Multi-User System', flush=True)
else:
    print('ERROR: unable to find the live medium', flush=True)
# A long log after the marker reproduces early pipe closure with grep -q.
print('kernel log detail\\n' * 100000, flush=True)
time.sleep(1)
''')
            for executable in (xorriso, qemu):
                executable.chmod(0o755)
            iso = root / 'medium.iso'
            iso.touch()
            env = dict(os.environ, PATH=str(binaries) + os.pathsep + os.environ['PATH'],
                       FAKE_BOOT_MODE=mode, WORK_DIR=str(root / 'work'), BOOT_TIMEOUT='2')
            result = subprocess.run(['bash', str(ROOT / 'arch/iso/test-boot.sh'), str(iso)],
                                    env=env, text=True, capture_output=True, timeout=15)
            self.assertTrue((root / 'work/boot.log').is_file())
            return result

    def test_unquoted_label_and_long_banner_log(self):
        result = self.run_boot('banner')
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_coloured_systemd_and_getty(self):
        result = self.run_boot('getty')
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_partial_boot_is_not_success(self):
        self.assertNotEqual(self.run_boot('partial').returncode, 0)

    def test_missing_live_medium_is_failure(self):
        self.assertNotEqual(self.run_boot('error').returncode, 0)


if __name__ == '__main__':
    unittest.main()
