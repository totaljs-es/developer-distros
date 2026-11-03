"""Online target installation jobs. Calamares owns partitioning and accounts."""
import os
from pathlib import Path
import platform
import shutil
import subprocess
import tempfile
from urllib.parse import urlsplit
from urllib.request import urlopen

KEY_FINGERPRINT = '95454694523B8D18A376F7D5D722BA35C8427B40'
REPOSITORY = 'https://totaljs-es.github.io/developer-distros/repo'


def configuration(config):
    base, arch = config.get('base'), config.get('architecture')
    if base not in ('ubuntu', 'arch') or arch not in ('amd64', 'arm64'):
        raise ValueError('Unsupported base or architecture')
    repository = config.get('repository', REPOSITORY).rstrip('/')
    url = urlsplit(repository)
    if any(char.isspace() or ord(char) < 32 for char in repository) or url.scheme != 'https' or not url.hostname or url.username or url.password or url.query or url.fragment:
        raise ValueError('The package repository must be an HTTPS URL without credentials or parameters')
    return base, arch, repository


def target_path(value):
    if not isinstance(value, str) or not value:
        raise ValueError('Calamares has not provided a target mount point')
    path = Path(value)
    # mount's own mkdtemp prefix; never accept /, a symlink or a host directory.
    if not path.is_absolute() or path.resolve() != path or not path.name.startswith('calamares-root-'):
        raise ValueError('Invalid Calamares target mount point')
    if not os.path.ismount(path) or path.stat().st_dev == Path('/').stat().st_dev:
        raise ValueError('The target must be a separate mounted filesystem')
    return path


def target_file(root, relative, contents, mode=0o644):
    root = root.resolve()
    if Path(relative).is_absolute() or '..' in Path(relative).parts:
        raise ValueError('Invalid relative target path')
    path = root / relative
    if not path.parent.resolve().is_relative_to(root):
        raise ValueError('Target path escapes the installed system')
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.is_symlink():
        path.unlink()
    path.write_text(contents, encoding='utf-8')
    path.chmod(mode)


def command(args, **kwargs):
    env = dict(os.environ, DEBIAN_FRONTEND='noninteractive', LC_ALL='C',
               PATH='/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin')
    return subprocess.run(args, check=True, env=env, **kwargs)


def download(url):
    with urlopen(url, timeout=30) as response:
        if urlsplit(response.url).scheme != 'https':
            raise ValueError('Repository redirected to an insecure address')
        data = response.read(8 * 1024 * 1024 + 1)
    if len(data) > 8 * 1024 * 1024:
        raise ValueError('Repository metadata exceeds the expected size')
    return data


def repository_key(repository):
    key = download(repository + '/totaljs-developer.gpg')
    with tempfile.TemporaryDirectory(prefix='totaljs-repository-') as directory:
        folder = Path(directory)
        keyfile = folder / 'key.gpg'
        keyfile.write_bytes(key)
        result = command(['gpg', '--batch', '--no-options', '--homedir', str(folder),
                          '--with-colons', '--show-keys', str(keyfile)],
                         capture_output=True, text=True)
        fingerprints = [line.split(':')[9] for line in result.stdout.splitlines()
                        if line.startswith('fpr:')]
        primary_keys = sum(line.startswith('pub:') for line in result.stdout.splitlines())
        if primary_keys != 1 or not fingerprints or fingerprints[0] != KEY_FINGERPRINT:
            raise ValueError('The repository signing key is not the Total.js key')
    return key


def preflight(config, storage):
    base, arch, repository = configuration(config)
    machine = {'aarch64': 'arm64', 'arm64': 'arm64', 'x86_64': 'amd64'}.get(platform.machine())
    if machine != arch or os.geteuid() != 0:
        raise ValueError('Installation must run as root on the selected native architecture')
    if arch == 'arm64' and not Path('/sys/firmware/efi').is_dir():
        raise ValueError('ARM installation requires UEFI firmware')
    for variable in Path('/sys/firmware/efi/efivars').glob('SecureBoot-*'):
        data = variable.read_bytes()
        if len(data) > 4 and data[4] == 1:
            raise ValueError('This experimental boot chain has not been signed for Secure Boot')
    for tool in ['gpg', 'gpgv', 'chroot', 'mount', 'findmnt',
                 'debootstrap' if base == 'ubuntu' else 'pacstrap']:
        if not shutil.which(tool):
            raise ValueError('The live image is missing ' + tool)
    edition = storage.value('packagechooser_packagechooser')
    if edition not in ('desktop', 'server'):
        raise ValueError('Choose Desktop or Server before installing')
    partitions = storage.value('partitions') or []
    roots = [part for part in partitions if part.get('mountPoint') == '/']
    if partitions and (len(roots) != 1 or roots[0].get('fs', '').lower() != 'ext4'):
        raise ValueError('This experimental installer requires an ext4 root filesystem')
    if any(part.get('luksMapperName') or (part.get('fsName') or '').lower().startswith('luks')
           for part in partitions):
        raise ValueError('Encrypted installations are not supported by this experimental profile yet')
    # Verify signed metadata before the partition job changes a disk.
    key = repository_key(repository)
    with tempfile.TemporaryDirectory(prefix='totaljs-metadata-') as directory:
        folder = Path(directory)
        keyfile = folder / 'key.gpg'
        keyfile.write_bytes(key)
        if base == 'ubuntu':
            metadata = folder / 'InRelease'
            metadata.write_bytes(download(repository + '/ubuntu/dists/resolute/InRelease'))
            command(['gpgv', '--homedir', str(folder), '--keyring', str(keyfile), str(metadata)])
        else:
            package_arch = 'aarch64' if arch == 'arm64' else 'x86_64'
            url = repository + '/arch/' + package_arch + '/totaljs-developer.db'
            metadata = folder / 'repository.db'
            signature = folder / 'repository.sig'
            metadata.write_bytes(download(url))
            signature.write_bytes(download(url + '.sig'))
            command(['gpgv', '--homedir', str(folder), '--keyring', str(keyfile), str(signature), str(metadata)])


def mount_runtime(root, run_command):
    # Bootstrap tools manage their own mounts. Attach the target's runtime only
    # after they finish, so their cleanup cannot remove Calamares' mounts.
    for relative in ['proc', 'sys', 'dev', 'run']:
        path = root / relative
        if not path.resolve().is_relative_to(root.resolve()):
            raise ValueError('Target runtime directory escapes the installed system')
        path.mkdir(parents=True, exist_ok=True)
    run_command(['mount', '-t', 'proc', 'proc', str(root / 'proc')])
    run_command(['mount', '-t', 'sysfs', 'sys', str(root / 'sys')])
    run_command(['mount', '--rbind', '/dev', str(root / 'dev')])
    run_command(['mount', '--make-rslave', str(root / 'dev')])
    run_command(['mount', '-t', 'tmpfs', 'tmpfs', str(root / 'run')])
    if Path('/run/udev').is_dir():
        (root / 'run/udev').mkdir(parents=True, exist_ok=True)
        run_command(['mount', '--bind', '/run/udev', str(root / 'run/udev')])
    if Path('/sys/firmware/efi/efivars').is_dir():
        path = root / 'sys/firmware/efi/efivars'
        path.mkdir(parents=True, exist_ok=True)
        run_command(['mount', '-t', 'efivarfs', 'efivarfs', str(path)])
    # The native umount module enumerates and unmounts all mounts under the target.


def bootstrap(config, root, edition, firmware, run_command=command):
    base, arch, repository = configuration(config)
    if edition not in ('desktop', 'server'):
        raise ValueError('Invalid edition')
    if (root / 'etc/os-release').exists():
        raise ValueError('The root partition contains an existing system; choose to format it')
    filesystem = run_command(['findmnt', '-n', '-o', 'FSTYPE,SOURCE', '--target', str(root)],
                             capture_output=True, text=True).stdout.strip().split()
    if len(filesystem) != 2 or filesystem[0] != 'ext4' or filesystem[1].startswith('/dev/mapper/'):
        raise ValueError('The experimental target must be an unencrypted ext4 root without LVM')
    key = repository_key(repository)

    def inside(*args):
        run_command(['chroot', str(root), '/usr/bin/env', 'DEBIAN_FRONTEND=noninteractive',
                     'PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin', *args])

    if base == 'ubuntu':
        mirror = 'https://ports.ubuntu.com/ubuntu-ports' if arch == 'arm64' else 'https://archive.ubuntu.com/ubuntu'
        target_file(root, 'usr/sbin/policy-rc.d', '#!/bin/sh\nexit 101\n', 0o755)
        run_command(['debootstrap', '--variant=minbase', '--arch=' + arch,
                     '--include=ca-certificates,gpgv,locales,sudo,systemd-sysv,dbus',
                     'resolute', str(root), mirror])
        mount_runtime(root, run_command)
        target_file(root, 'etc/apt/sources.list', '')
        security = mirror if arch == 'arm64' else 'https://security.ubuntu.com/ubuntu'
        target_file(root, 'etc/apt/sources.list.d/ubuntu.sources',
                    f'Types: deb\nURIs: {mirror}\nSuites: resolute resolute-updates\n'
                    'Components: main restricted universe multiverse\nSigned-By: /usr/share/keyrings/ubuntu-archive-keyring.gpg\n\n'
                    f'Types: deb\nURIs: {security}\nSuites: resolute-security\n'
                    'Components: main restricted universe multiverse\nSigned-By: /usr/share/keyrings/ubuntu-archive-keyring.gpg\n')
        keyfile = root / 'usr/share/keyrings/totaljs-developer-archive-keyring.gpg'
        keyfile.parent.mkdir(parents=True, exist_ok=True)
        keyfile.write_bytes(key)
        target_file(root, 'etc/apt/sources.list.d/totaljs-developer.sources',
                    f'Types: deb\nURIs: {repository}/ubuntu\nSuites: resolute\nComponents: main\n'
                    'Signed-By: /usr/share/keyrings/totaljs-developer-archive-keyring.gpg\n')
        # debootstrap/pacstrap and native Calamares jobs use the live resolver only during installation.
        target_file(root, 'etc/resolv.conf', Path('/etc/resolv.conf').read_text())
        target_file(root, 'etc/apt/apt.conf.d/90-totaljs-ca',
                    'Acquire::https::CaInfo "/etc/ssl/certs/ca-certificates.crt";\n')
        inside('apt-get', 'update', '--error-on=any')
        sources = ['totaljs-developer-release', 'totaljs-docker-source']
        if edition == 'desktop':
            sources += ['totaljs-mozilla-source', 'totaljs-chrome-source']
        inside('apt-get', 'install', '-y', *sources)
        inside('apt-get', 'update', '--error-on=any')
        grub = 'grub-efi-' + arch + '-bin' if firmware == 'efi' else 'grub-pc-bin'
        inside('apt-get', 'install', '-y', 'linux-image-generic', 'linux-firmware', 'initramfs-tools',
               'grub2-common', grub, 'efibootmgr', 'netplan.io', 'network-manager', 'systemd-resolved', 'systemd-timesyncd',
               'kbd', 'console-setup', 'tzdata', 'totaljs-developer-' + edition)
    else:
        kernel = 'linux-aarch64' if arch == 'arm64' else 'linux'
        run_command(['pacstrap', '-K', str(root), 'base', kernel, 'linux-firmware',
                     'grub', 'efibootmgr', 'sudo', 'networkmanager', 'openssh', 'python'])
        mount_runtime(root, run_command)
        target_file(root, 'etc/resolv.conf', Path('/etc/resolv.conf').read_text())
        keyfile = root / 'tmp/totaljs-developer.gpg'
        keyfile.write_bytes(key)
        inside('pacman-key', '--init')
        inside('pacman-key', '--populate', 'archlinuxarm' if arch == 'arm64' else 'archlinux')
        inside('pacman-key', '--add', '/tmp/totaljs-developer.gpg')
        inside('pacman-key', '--lsign-key', KEY_FINGERPRINT)
        # The release package owns its Include file; keep the bootstrap source separate.
        pacman = root / 'etc/pacman.conf'
        target_file(root, 'etc/pacman.conf', pacman.read_text() +
                    '\n[totaljs-developer]\nSigLevel = Required DatabaseRequired\n'
                    f'Server = {repository}/arch/$arch\n')
        inside('pacman', '-Syu', '--noconfirm', 'totaljs-developer-release', 'totaljs-developer-' + edition)
        keyfile.unlink()


def finalize(config, root, edition, run_command=command):
    base, arch, _ = configuration(config)
    if edition not in ('desktop', 'server'):
        raise ValueError('Invalid edition')

    def inside(*args):
        run_command(['chroot', str(root), *args])

    # The person now exists (users module); /www permissions use the shared package helper.
    inside('/usr/lib/totaljs-developer/add-first-user')
    # NetworkManager also provides headless nmcli/nmtui: the live Wi-Fi
    # connection remains usable in Server without installing a desktop.
    services = ['NetworkManager', 'systemd-resolved', 'systemd-timesyncd']
    if edition == 'desktop':
        services += ['lightdm']
    target_file(root, 'etc/NetworkManager/conf.d/90-totaljs-resolved.conf',
                '[main]\ndns=systemd-resolved\n')
    if base == 'ubuntu':
        target_file(root, 'etc/NetworkManager/conf.d/10-globally-managed-devices.conf',
                    '[keyfile]\nunmanaged-devices=\n')
        target_file(root, 'etc/netplan/90-totaljs-installer.yaml',
                    'network:\n  version: 2\n  renderer: NetworkManager\n', 0o600)
    # The native networkcfg module copies connections. Remove a live-user-only
    # restriction if its username could not be inferred in the sudo session.
    for connection in (root / 'etc/NetworkManager/system-connections').glob('*'):
        if connection.is_file() and not connection.is_symlink():
            text = connection.read_text()
            if 'permissions=user:live:;' in text:
                target_file(root, str(connection.relative_to(root)),
                            text.replace('permissions=user:live:;', 'permissions='), 0o600)
    services += ['ssh' if base == 'ubuntu' else 'sshd']
    for service in services:
        inside('systemctl', 'enable', service + '.service')
    inside('systemctl', 'set-default', 'graphical.target' if edition == 'desktop' else 'multi-user.target')
    resolver = root / 'etc/resolv.conf'
    resolver.unlink(missing_ok=True)
    resolver.symlink_to('../run/systemd/resolve/stub-resolv.conf')
    if base == 'ubuntu':
        (root / 'usr/sbin/policy-rc.d').unlink(missing_ok=True)
        inside('update-initramfs', '-u', '-k', 'all')
    else:
        inside('mkinitcpio', '-P')


def arm_bootloader(root, run_command=command):
    # Arch Linux ARM's Image lives on the ESP (/boot), with a portable UEFI fallback.
    if not os.path.ismount(root / 'boot'):
        raise ValueError('The ARM EFI system partition must be mounted on /boot')
    result = run_command(['findmnt', '-n', '-o', 'UUID', '--target', str(root)],
                         capture_output=True, text=True)
    uuid = result.stdout.strip()
    if not uuid or any(char not in '0123456789abcdefABCDEF-' for char in uuid):
        raise ValueError('Cannot identify the installed root filesystem')
    efi = root / 'usr/lib/systemd/boot/efi/systemd-bootaa64.efi'
    if not efi.is_file() or not (root / 'boot/Image').is_file() or not (root / 'boot/initramfs-linux.img').is_file():
        raise ValueError('The ARM kernel, initramfs or UEFI loader is missing')
    destination = root / 'boot/EFI/BOOT/BOOTAA64.EFI'
    destination.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(efi, destination)
    target_file(root, 'boot/loader/loader.conf', 'default totaljs.conf\ntimeout 3\neditor no\n')
    target_file(root, 'boot/loader/entries/totaljs.conf',
                f'title Total.js Developer\nlinux /Image\ninitrd /initramfs-linux.img\n'
                f'options root=UUID={uuid} rw rootwait preempt=none\n')


def pretty_name():
    import libcalamares
    return {
        'preflight': 'Checking signed package repositories',
        'bootstrap': 'Downloading and installing Total.js Developer',
        'finalize': 'Configuring services and the initial ramdisk',
        'arm-bootloader': 'Installing the ARM UEFI bootloader',
    }.get(libcalamares.job.configuration.get('phase'), 'Preparing Total.js Developer')


def run():
    import libcalamares
    config, storage = libcalamares.job.configuration, libcalamares.globalstorage
    try:
        configuration(config)
        phase = config.get('phase')
        if phase == 'preflight':
            preflight(config, storage)
        else:
            root = target_path(storage.value('rootMountPoint'))
            edition = storage.value('packagechooser_packagechooser')
            if phase == 'bootstrap':
                bootstrap(config, root, edition, storage.value('firmwareType'))
            elif phase == 'finalize':
                finalize(config, root, edition)
            elif phase == 'arm-bootloader':
                arm_bootloader(root)
            else:
                raise ValueError('Unknown installer phase')
    except Exception as error:
        # Never inspect or log the account/password entries in GlobalStorage.
        return ('Total.js Developer installation stopped', str(error))
    return None
