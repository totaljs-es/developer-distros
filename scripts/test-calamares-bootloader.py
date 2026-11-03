#!/usr/bin/env python3
"""Check that the Ubuntu adapter delegates boot work and tolerates missing by-id."""
import errno
import importlib.util
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('totaljs_bootloader', ROOT / 'shared/calamares/modules/bootloader/main.py')
adapter = importlib.util.module_from_spec(spec)
spec.loader.exec_module(adapter)


class BootloaderAdapterTests(unittest.TestCase):
    def setUp(self):
        adapter._NATIVE = None

    def tearDown(self):
        adapter._NATIVE = None

    def native(self, folder):
        path = Path(folder) / 'native.py'
        path.write_text('''import os

def get_disk_id(device_name, efi):
    return os.listdir('/dev/disk/by-id')

def pretty_name():
    return 'Native bootloader'

def run():
    return get_disk_id('/dev/sda', False)
''')
        return path

    def test_no_by_id_directory_skips_only_optional_device_preseeding(self):
        with tempfile.TemporaryDirectory() as folder, \
             patch.object(adapter, 'native_paths', return_value=[self.native(folder)]):
            native = adapter.native_module()
            error = FileNotFoundError(errno.ENOENT, 'Not found', '/dev/disk/by-id')
            with patch.object(native.os, 'listdir', side_effect=error):
                self.assertIsNone(adapter.run())
            self.assertEqual(adapter.pretty_name(), 'Native bootloader')

    def test_other_errors_are_preserved(self):
        with tempfile.TemporaryDirectory() as folder, \
             patch.object(adapter, 'native_paths', return_value=[self.native(folder)]):
            native = adapter.native_module()
            for error in [FileNotFoundError(errno.ENOENT, 'Not found', '/other/path'),
                          PermissionError(errno.EACCES, 'Permission denied', '/dev/disk/by-id')]:
                with self.subTest(error=error), patch.object(native.os, 'listdir', side_effect=error), \
                     self.assertRaises(type(error)):
                    adapter.run()

    def test_existing_native_result_is_unchanged(self):
        with tempfile.TemporaryDirectory() as folder, \
             patch.object(adapter, 'native_paths', return_value=[self.native(folder)]):
            native = adapter.native_module()
            with patch.object(native.os, 'listdir', return_value=['disk-alias']):
                self.assertEqual(adapter.run(), ['disk-alias'])
            self.assertIs(adapter.native_module(), native)

    def test_missing_native_module_is_not_ignored(self):
        with patch.object(adapter, 'native_paths', return_value=[]), \
             self.assertRaisesRegex(RuntimeError, 'native.*missing'):
            adapter.run()


if __name__ == '__main__':
    unittest.main()
