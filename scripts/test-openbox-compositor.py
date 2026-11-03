#!/usr/bin/env python3
"""Exercise backend selection and the narrow upgrade with disposable fixtures."""
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
BIN = ROOT / "packages/totaljs-openbox/files/usr/bin/totaljs-picom-backend"
MIGRATE = ROOT / "packages/totaljs-openbox/files/usr/lib/totaljs-openbox/migrate-autostart"
OLD = 'if systemd-detect-virt --quiet 2>/dev/null; then BACKEND="--backend xrender --no-vsync"; else BACKEND="--backend glx"; fi'
NEW = 'if [ "$(totaljs-picom-backend)" = xrender ]; then BACKEND="--backend xrender --no-vsync"; else BACKEND="--backend glx"; fi'

class CompositorTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.base = Path(self.tmp.name)
        self.sysfs = self.base / "sys"
        self.sysfs.mkdir()
        self.stub = self.base / "systemd-detect-virt"
        self.env = dict(os.environ, PATH=str(self.base) + os.pathsep + os.environ["PATH"])
        self.detect(False)

    def detect(self, virtual):
        self.stub.write_text("#!/bin/sh\nexit " + ("0" if virtual else "1") + "\n")
        self.stub.chmod(0o755)

    def backend(self):
        return subprocess.check_output(["sh", str(BIN), str(self.sysfs)], env=self.env, text=True).strip()

    def test_physical_machine_keeps_glx(self):
        self.assertEqual(self.backend(), "glx")

    def test_systemd_vm_uses_xrender(self):
        self.detect(True)
        self.assertEqual(self.backend(), "xrender")

    def test_virtualbox_module_with_systemd_none(self):
        (self.sysfs / "module/vboxguest").mkdir(parents=True)
        self.assertEqual(self.backend(), "xrender")

    def test_virtualbox_pci_before_module_load(self):
        vendor = self.sysfs / "bus/pci/devices/0000:00:01.0/vendor"
        vendor.parent.mkdir(parents=True)
        vendor.write_text("0x80ee\n")
        self.assertEqual(self.backend(), "xrender")

    def test_other_pci_vendor_keeps_glx(self):
        vendor = self.sysfs / "bus/pci/devices/0000:00:01.0/vendor"
        vendor.parent.mkdir(parents=True)
        vendor.write_text("0x8086\n")
        self.assertEqual(self.backend(), "glx")

    @unittest.skipUnless(sys.platform.startswith("linux"), "maintainer script uses Linux sed")
    def test_upgrade_preserves_content_mode_owner_and_is_idempotent(self):
        file = self.base / "autostart"
        file.write_text("# personal setting\n" + OLD + "\nmy-own-app &\n")
        file.chmod(0o750)
        before = file.stat()
        subprocess.run(["sh", str(MIGRATE), str(file)], check=True)
        self.assertEqual(file.read_text(), "# personal setting\n" + NEW + "\nmy-own-app &\n")
        after = file.stat()
        self.assertEqual((after.st_mode, after.st_uid, after.st_gid), (before.st_mode, before.st_uid, before.st_gid))
        subprocess.run(["sh", str(MIGRATE), str(file)], check=True)
        self.assertEqual(file.stat().st_mtime_ns, after.st_mtime_ns)

    def test_custom_backend_and_symlink_are_untouched(self):
        file = self.base / "autostart"
        file.write_text("picom --backend egl --daemon\n")
        subprocess.run(["sh", str(MIGRATE), str(file)], check=True)
        self.assertEqual(file.read_text(), "picom --backend egl --daemon\n")
        target = self.base / "target"
        target.write_text(OLD)
        file.unlink()
        file.symlink_to(target)
        subprocess.run(["sh", str(MIGRATE), str(file)], check=True)
        self.assertTrue(file.is_symlink())
        self.assertEqual(target.read_text(), OLD)

if __name__ == "__main__":
    unittest.main()
