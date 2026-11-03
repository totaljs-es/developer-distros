"""Delegate to Ubuntu's native bootloader, allowing disks without udev by-id links."""
import importlib.util
from pathlib import Path
import sysconfig

_NATIVE = None


def native_paths():
    multiarch = sysconfig.get_config_var('MULTIARCH')
    paths = []
    if multiarch:
        paths.append(Path('/usr/lib') / multiarch / 'calamares/modules/bootloader/main.py')
    paths.append(Path('/usr/lib/calamares/modules/bootloader/main.py'))
    return paths


def native_module():
    global _NATIVE
    if _NATIVE is None:
        path = next((path for path in native_paths() if path.is_file()), None)
        if path is None:
            raise RuntimeError('The native Calamares bootloader module is missing')
        spec = importlib.util.spec_from_file_location('totaljs_native_bootloader', path)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        if hasattr(module, 'get_disk_id'):
            original = module.get_disk_id

            def disk_id(device_name, efi):
                try:
                    return original(device_name, efi)
                except FileNotFoundError as error:
                    if error.filename != '/dev/disk/by-id':
                        raise
                    # Ubuntu already skips optional debconf preseeding when no
                    # stable by-id alias matches. An absent directory is the
                    # same case (e.g. a VirtualBox disk without a serial).
                    return None

            module.get_disk_id = disk_id
        _NATIVE = module
    return _NATIVE


def pretty_name():
    return native_module().pretty_name()


def run():
    return native_module().run()
