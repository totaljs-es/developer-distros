#!/usr/bin/env python3
"""Installer contracts with temporary trees and command doubles; no disks are changed."""
import importlib.util
import itertools
import json
import os
from pathlib import Path
import subprocess
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]


def load(name, relative):
    spec = importlib.util.spec_from_file_location(name, ROOT / relative)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


renderer = load('renderer', 'shared/calamares/render.py')
jobs = load('jobs', 'shared/calamares/modules/totaljs/main.py')


def config(base='ubuntu', arch='amd64'):
    return {'base': base, 'architecture': arch}


class InstallerTests(unittest.TestCase):
    def test_profiles_share_pages_and_check_signatures_before_partitioning(self):
        with tempfile.TemporaryDirectory() as folder:
            sequences = []
            for base, arch, edition in itertools.product(['ubuntu', 'arch'], ['amd64', 'arm64'], ['desktop', 'server']):
                with self.subTest(base=base, arch=arch, edition=edition):
                    output = Path(folder) / f'{base}-{arch}-{edition}'
                    renderer.render(ROOT, output, base, arch, edition, mode='installer')
                    settings = json.loads((output / 'settings.conf').read_text())
                    sequences.append(settings['sequence'][0])
                    execute = settings['sequence'][1]['exec']
                    self.assertLess(execute.index('totaljs@preflight'), execute.index('partition'))
                    self.assertLess(execute.index('mount'), execute.index('totaljs@bootstrap'))
                    self.assertLess(execute.index('totaljs@bootstrap'), execute.index('users'))
                    self.assertLess(execute.index('users'), execute.index('totaljs@finalize'))
                    self.assertEqual(execute[-1], 'umount')
                    self.assertTrue(settings['prompt-install'])
                    self.assertNotIn('unpackfs', execute)
                    self.assertEqual('totaljs@arm-bootloader' in execute, base == 'arch' and arch == 'arm64')
                    partition = json.loads((output / 'modules/partition.conf').read_text())
                    roots = [item for item in partition['partitionLayout'] if item.get('mountPoint') == '/']
                    self.assertEqual(len(roots), 1)
                    self.assertEqual(roots[0]['filesystem'], 'ext4')
                    self.assertEqual(roots[0]['size'], '100%')
                    chooser = json.loads((output / 'modules/packagechooser.conf').read_text())
                    self.assertEqual(chooser['default'], edition)
                    self.assertEqual(chooser['method'], 'legacy')
                    users = json.loads((output / 'modules/users.conf').read_text())
                    self.assertFalse(users['doAutologin'])
                    self.assertFalse(users['setRootPassword'])
                    self.assertFalse((output / 'preview.json').exists())
                    self.assertEqual((output / 'modules/bootloader/main.py').is_file(), base == 'ubuntu')
            self.assertTrue(all(sequence == sequences[0] for sequence in sequences))

    def test_insecure_repository_is_rejected_before_output_exists(self):
        with tempfile.TemporaryDirectory() as folder:
            for repository in ['http://example.com/repo', 'https://user:secret@example.com/repo', 'https://example.com/?token=secret', 'https://example.com/repo\nInjected: value']:
                output = Path(folder) / 'output'
                with self.assertRaises(ValueError):
                    renderer.render(ROOT, output, 'ubuntu', 'amd64', 'desktop', mode='installer', repository=repository)
                self.assertFalse(output.exists())

    def test_host_paths_and_unmounted_targets_are_rejected(self):
        with tempfile.TemporaryDirectory(prefix='calamares-root-') as folder:
            for value in [None, '', '/', '/etc', 'relative', folder]:
                with self.subTest(value=value), self.assertRaises(ValueError):
                    jobs.target_path(value)
            link = Path(folder) / 'calamares-root-link'
            link.symlink_to('/etc')
            with self.assertRaises(ValueError):
                jobs.target_path(str(link))

    def test_target_directory_symlink_cannot_write_to_host(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder) / 'root'
            host = Path(folder) / 'host'
            root.mkdir()
            host.mkdir()
            (root / 'etc').symlink_to(host)
            with self.assertRaises(ValueError):
                jobs.target_file(root, 'etc/hostname', 'unexpected')
            self.assertEqual(list(host.iterdir()), [])

    def test_ubuntu_sources_precede_desktop_and_finalize_does_not_enable_autologin(self):
        with tempfile.TemporaryDirectory() as folder, patch.object(jobs, 'repository_key', return_value=b'test-key'):
            root, calls = Path(folder), []
            def recorder(args, **kwargs):
                calls.append(args)
                return SimpleNamespace(stdout='ext4 /dev/vda2')

            jobs.bootstrap(config(), root, 'desktop', 'efi', recorder)
            source_install = next(i for i, call in enumerate(calls) if 'totaljs-mozilla-source' in call)
            target_install = next(i for i, call in enumerate(calls) if 'totaljs-developer-desktop' in call)
            self.assertLess(source_install, target_install)
            bootstrap = next(i for i, call in enumerate(calls) if call[0] == 'debootstrap')
            runtime = next(i for i, call in enumerate(calls) if call[0] == 'mount')
            self.assertLess(bootstrap, runtime)
            self.assertLess(runtime, source_install)
            self.assertIn('grub-efi-amd64-bin', calls[target_install])
            include = next(arg for arg in calls[bootstrap] if arg.startswith('--include='))
            self.assertIn('gpgv', include.split('=', 1)[1].split(','))
            self.assertIn('/etc/ssl/certs/ca-certificates.crt', (root / 'etc/apt/apt.conf.d/90-totaljs-ca').read_text())
            updates = [call for call in calls if 'apt-get' in call and 'update' in call]
            self.assertTrue(all('--error-on=any' in call for call in updates))
            self.assertTrue((root / 'usr/sbin/policy-rc.d').exists())
            jobs.finalize(config(), root, 'desktop', recorder)
            self.assertFalse((root / 'usr/sbin/policy-rc.d').exists())
            self.assertEqual((root / 'etc/resolv.conf').readlink(), Path('../run/systemd/resolve/stub-resolv.conf'))
            self.assertTrue(any(call[-3:] == ['systemctl', 'enable', 'lightdm.service'] for call in calls))
            self.assertFalse((root / 'etc/lightdm/lightdm.conf.d/90-totaljs-live.conf').exists())

    def test_arch_arm_bootstraps_native_packages_and_full_signed_transaction(self):
        with tempfile.TemporaryDirectory() as folder, patch.object(jobs, 'repository_key', return_value=b'test-key'):
            root, calls = Path(folder), []

            def recorder(args, **kwargs):
                calls.append(args)
                if args[0] == 'findmnt':
                    return SimpleNamespace(stdout='ext4 /dev/vda2')
                if args[0] == 'pacstrap':
                    (root / 'etc').mkdir()
                    (root / 'tmp').mkdir()
                    (root / 'etc/pacman.conf').write_text('[options]\nArchitecture = auto\n')

            jobs.bootstrap(config('arch', 'arm64'), root, 'server', 'efi', recorder)
            pacstrap = next(call for call in calls if call[0] == 'pacstrap')
            self.assertIn('linux-aarch64', pacstrap)
            self.assertIn('-K', pacstrap)
            self.assertTrue(any('archlinuxarm' in call for call in calls))
            transaction = next(call for call in calls if 'totaljs-developer-server' in call)
            self.assertIn('-Syu', transaction)
            self.assertIn('SigLevel = Required DatabaseRequired', (root / 'etc/pacman.conf').read_text())
            self.assertFalse((root / 'tmp/totaljs-developer.gpg').exists())
            connection = root / 'etc/NetworkManager/system-connections/wifi.nmconnection'
            connection.parent.mkdir(parents=True)
            connection.write_text('[connection]\npermissions=user:live:;\n[802-11-wireless-security]\npsk=test-secret\n')
            jobs.finalize(config('arch', 'arm64'), root, 'server', recorder)
            self.assertTrue(any(call[-2:] == ['mkinitcpio', '-P'] for call in calls))
            self.assertFalse(any('lightdm.service' in call for call in calls))
            self.assertTrue(any('NetworkManager.service' in call for call in calls))
            self.assertIn('permissions=\n', connection.read_text())
            self.assertIn('psk=test-secret', connection.read_text())
            self.assertEqual(connection.stat().st_mode & 0o777, 0o600)
            self.assertFalse(any('test-secret' in str(call) for call in calls))

    def test_existing_system_is_not_bootstrapped_over(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            (root / 'etc').mkdir()
            (root / 'etc/os-release').write_text('existing')
            with patch.object(jobs, 'repository_key') as key, self.assertRaisesRegex(ValueError, 'existing system'):
                jobs.bootstrap(config(), root, 'desktop', 'efi')
            key.assert_not_called()

    def test_download_failure_stops_before_any_partition_command(self):
        values = {'packagechooser_packagechooser': 'desktop', 'partitions': [{'mountPoint': '/', 'fs': 'ext4'}]}
        storage = SimpleNamespace(value=values.get)
        with patch.object(jobs.platform, 'machine', return_value='x86_64'), \
             patch.object(jobs.os, 'geteuid', return_value=0), \
             patch.object(jobs.shutil, 'which', return_value='/usr/bin/tool'), \
             patch.object(jobs, 'repository_key', side_effect=OSError('network unavailable')), \
             patch.object(jobs.subprocess, 'run') as run, \
             self.assertRaisesRegex(OSError, 'network unavailable'):
            jobs.preflight(config(), storage)
        run.assert_not_called()

    def test_extra_primary_signing_keys_are_rejected(self):
        stdout = 'pub:::::::::\nfpr:::::::::' + jobs.KEY_FINGERPRINT + ':\npub:::::::::\nfpr:::::::::OTHER:\n'
        with patch.object(jobs, 'download', return_value=b'key'), \
             patch.object(jobs, 'command', return_value=SimpleNamespace(stdout=stdout)), \
             self.assertRaisesRegex(ValueError, 'signing key'):
            jobs.repository_key(jobs.REPOSITORY)

    def test_command_failure_is_not_ignored(self):
        with tempfile.TemporaryDirectory() as folder, patch.object(jobs, 'repository_key', return_value=b'test-key'):
            root, calls = Path(folder), []

            def fail(args, **kwargs):
                calls.append(args)
                raise subprocess.CalledProcessError(1, args)

            with self.assertRaises(subprocess.CalledProcessError):
                jobs.bootstrap(config(), root, 'desktop', 'efi', fail)
            self.assertEqual(len(calls), 1)


    def test_preflight_accepts_partitions_not_yet_exported_by_native_job(self):
        values = {'packagechooser_packagechooser': 'server', 'partitions': None}
        storage = SimpleNamespace(value=values.get)
        with patch.object(jobs.platform, 'machine', return_value='x86_64'), \
             patch.object(jobs.os, 'geteuid', return_value=0), \
             patch.object(jobs.shutil, 'which', return_value='/usr/bin/tool'), \
             patch.object(jobs, 'repository_key', return_value=b'test-key'), \
             patch.object(jobs, 'download', return_value=b'signed-metadata'), \
             patch.object(jobs, 'command') as run:
            jobs.preflight(config(), storage)
        self.assertEqual(run.call_count, 1)
        self.assertEqual(run.call_args.args[0][0], 'gpgv')

    def test_arch_preflight_uses_the_published_canonical_database_and_signature(self):
        storage = SimpleNamespace(value={'packagechooser_packagechooser': 'server'}.get)
        with patch.object(jobs.platform, 'machine', return_value='x86_64'), \
             patch.object(jobs.os, 'geteuid', return_value=0), \
             patch.object(jobs.shutil, 'which', return_value='/usr/bin/tool'), \
             patch.object(jobs, 'repository_key', return_value=b'test-key'), \
             patch.object(jobs, 'download', return_value=b'signed-metadata') as download, \
             patch.object(jobs, 'command') as run:
            jobs.preflight(config(base='arch'), storage)
        self.assertEqual([call.args[0] for call in download.call_args_list], [
            jobs.REPOSITORY + '/arch/x86_64/totaljs-developer.db',
            jobs.REPOSITORY + '/arch/x86_64/totaljs-developer.db.sig',
        ])
        self.assertEqual(run.call_count, 1)
        self.assertEqual(run.call_args.args[0][0], 'gpgv')

    def test_bootstrap_rejects_actual_unsupported_filesystem_before_writing(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            with patch.object(jobs, 'repository_key') as key, \
                 patch.object(jobs, 'command', return_value=SimpleNamespace(stdout='xfs /dev/vda2')) as run:
                with self.assertRaisesRegex(ValueError, 'unencrypted ext4'):
                    jobs.bootstrap(config(), root, 'server', 'efi', run)
                key.assert_not_called()
            self.assertEqual(list(root.iterdir()), [])


class LiveBootPlumbingTests(unittest.TestCase):
    def boot(self, arch, marker, autodetect_vars=False, missing_vars=False, acceleration="tcg"):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            binaries = root / 'bin'
            binaries.mkdir()
            helper = '''#!/usr/bin/env python3
import json, os, pathlib, sys, time
args = sys.argv[1:]
pathlib.Path(os.environ['FAKE_ARGS']).write_text(json.dumps(args))
log = args[args.index('-serial') + 1].removeprefix('file:')
pathlib.Path(log).write_text(os.environ['FAKE_MARKER'])
time.sleep(5)
'''
            for emulator in ['qemu-system-x86_64', 'qemu-system-aarch64']:
                path = binaries / emulator
                path.write_text(helper)
                path.chmod(0o755)
            image = root / 'live.iso'
            firmware = root / ('OVMF_CODE_4M.fd' if autodetect_vars else 'firmware.fd')
            image.write_bytes(b'test double')
            firmware.write_bytes(b'test double')
            variables = root / ('OVMF_VARS_4M.fd' if autodetect_vars else 'firmware-vars.fd')
            variables.write_bytes(b'pristine variables')
            env = dict(os.environ, PATH=str(binaries) + os.pathsep + os.environ['PATH'],
                       ARCH=arch, QEMU_ACCEL=acceleration, WORK_DIR=str(root / 'work'), BOOT_TIMEOUT='3',
                       QEMU_MEMORY='4096', QEMU_FIRMWARE=str(firmware), QEMU_FIRMWARE_VARS=str(variables),
                       UEFI='1', MARKER_PATTERN='TOTALJS-CALAMARES-READY',
                       FAKE_MARKER=marker, FAKE_ARGS=str(root / 'arguments.json'))
            if autodetect_vars:
                env.pop('QEMU_FIRMWARE_VARS', None)
            if missing_vars:
                variables.unlink()
            result = subprocess.run(['bash', str(ROOT / 'iso/own/test-boot.sh'), str(image)],
                                    env=env, capture_output=True, text=True, timeout=10)
            if not missing_vars:
                self.assertEqual(variables.read_bytes(), b'pristine variables')
            if arch == 'amd64' and result.returncode == 0:
                self.assertEqual((root / 'work/uefi-vars.fd').read_bytes(), b'pristine variables')
            arguments = root / 'arguments.json'
            return result, json.loads(arguments.read_text()) if arguments.exists() else None

    def test_both_architectures_boot_and_use_graphical_readiness_marker(self):
        for arch in ['amd64', 'arm64']:
            with self.subTest(arch=arch):
                result, args = self.boot(arch, 'TOTALJS-CALAMARES-READY\n')
                self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
                self.assertEqual(args[args.index('-m') + 1], '4096')
                self.assertEqual(args[args.index('-machine') + 1], 'virt' if arch == 'arm64' else 'q35')
                self.assertEqual('-bios' in args, arch == 'arm64')
                if arch == 'amd64':
                    self.assertTrue(any('if=pflash' in arg and 'readonly=on' in arg for arg in args))
                    self.assertTrue(any('unit=1' in arg and 'uefi-vars.fd' in arg for arg in args))
                self.assertEqual('virtio-gpu-pci' in args, arch == 'arm64')

    def test_kvm_selects_the_host_cpu_on_both_architectures(self):
        for architecture in ['amd64', 'arm64']:
            with self.subTest(architecture=architecture):
                result, args = self.boot(architecture, 'TOTALJS-CALAMARES-READY\n', acceleration='kvm')
                self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
                self.assertEqual(args[args.index('-accel') + 1], 'kvm')
                self.assertEqual(args[args.index('-cpu') + 1], 'host')

    def test_ovmf_4m_finds_matching_variables_and_uses_flash(self):
        result, args = self.boot('amd64', 'TOTALJS-CALAMARES-READY\n', autodetect_vars=True)
        self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
        self.assertNotIn('-bios', args)
        self.assertTrue(any('OVMF_CODE_4M.fd' in arg and 'readonly=on' in arg for arg in args))
        self.assertTrue(any('uefi-vars.fd' in arg and 'unit=1' in arg for arg in args))

    def test_missing_ovmf_variables_fail_before_starting_qemu(self):
        result, args = self.boot('amd64', 'TOTALJS-CALAMARES-READY\n', missing_vars=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('Matching OVMF variables', result.stderr)
        self.assertIsNone(args)

    def test_linux_boot_alone_does_not_count_as_installer_ready(self):
        result, _ = self.boot('amd64', 'TOTALJS-LIVE-OK Total.js Developer\n')
        self.assertNotEqual(result.returncode, 0)


if __name__ == '__main__':
    unittest.main()
