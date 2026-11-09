#!/usr/bin/env python3
"""Render shared Calamares preview or experimental online-installer profiles."""
import argparse
import json
from pathlib import Path
import shutil
from copy import deepcopy
import xml.etree.ElementTree as ET


SVG = 'http://www.w3.org/2000/svg'
XLINK = 'http://www.w3.org/1999/xlink'
ET.register_namespace('', SVG)
ET.register_namespace('xlink', XLINK)


def qt_compatible_logo(source, destination):
    """Preserve artwork; replace unsupported clipping with equivalent Qt SVG masks."""
    tree = ET.parse(source)
    root = tree.getroot()
    parents = {child: parent for parent in root.iter() for child in parent}
    definitions = {node.get('id'): node for node in root.iter() if node.get('id')}
    for use in list(root.iter(f'{{{SVG}}}use')):
        target = definitions.get(use.get(f'{{{XLINK}}}href', '').lstrip('#'))
        if target is None or target.tag != f'{{{SVG}}}image':
            continue
        # A use's width/height apply to svg/symbol viewports, not referenced images.
        image = deepcopy(target)
        image.attrib.pop('id', None)
        image.set('x', use.get('x', '0'))
        image.set('y', use.get('y', '0'))
        group = ET.Element(f'{{{SVG}}}g')
        if use.get('transform'):
            group.set('transform', use.get('transform'))
        group.append(image)
        parent = parents[use]
        index = list(parent).index(use)
        parent.remove(use)
        parent.insert(index, group)
    for clip in list(root.iter(f'{{{SVG}}}clipPath')):
        mask = ET.Element(f'{{{SVG}}}mask', {
            'id': clip.get('id'), 'maskUnits': 'userSpaceOnUse',
            'maskContentUnits': 'userSpaceOnUse',
            'x': '-2048', 'y': '-2048', 'width': '4096', 'height': '4096',
        })
        for child in clip:
            shape = deepcopy(child)
            shape.attrib.pop('id', None)
            shape.attrib.pop('style', None)
            shape.set('fill', '#ffffff')
            shape.set('stroke', 'none')
            mask.append(shape)
        parent = parents[clip]
        index = list(parent).index(clip)
        parent.remove(clip)
        parent.insert(index, mask)
    for node in root.iter():
        clip = node.attrib.pop('clip-path', None)
        if clip:
            node.set('mask', clip)
    for defs in root.iter(f'{{{SVG}}}defs'):
        for node in list(defs):
            if node.tag == f'{{{SVG}}}image':
                defs.remove(node)
    tree.write(destination, encoding='utf-8', xml_declaration=True)


def write_json(path, value):
    # JSON is also YAML: Calamares can read this without a build-time YAML library.
    path.write_text(json.dumps(value, indent=2) + '\n', encoding='utf-8')


def render(repo, output, base, architecture, edition, calamares_data='/usr/share/calamares',
           mode='preview', repository='https://totaljs-es.github.io/developer-distros/repo'):
    repo, output = Path(repo).resolve(), Path(output).resolve()
    source = repo / 'shared/calamares'
    if mode not in ('preview', 'installer') or base not in ('ubuntu', 'arch') or architecture not in ('amd64', 'arm64') or edition not in ('desktop', 'server'):
        raise ValueError('Invalid installer profile')
    if mode == 'installer':
        from urllib.parse import urlsplit
        url = urlsplit(repository)
        if any(char.isspace() or ord(char) < 32 for char in repository) or url.scheme != 'https' or not url.hostname or url.username or url.password or url.query or url.fragment:
            raise ValueError('The package repository must be an HTTPS URL without credentials or parameters')
    if output == source or source in output.parents:
        raise ValueError('Output must be outside the Calamares source directory')
    assets = {
        'logo-totaljs.svg': repo / 'shared/branding/logo-totaljs.svg',
        'totalvm.png': repo / 'shared/branding/totalvm/totalvm.png',
        'TOTALVM-README.md': repo / 'shared/branding/totalvm/README.md',
    }
    if mode == 'installer':
        assets.update({
            'desktop.jpg': repo / 'docs/images/desktop.jpg',
            'server.jpg': repo / 'docs/images/server.jpg',
        })
    # Validate before creating anything. Never merge into system configuration.
    if output.exists():
        raise ValueError('Output already exists; choose a new preview directory')
    for path in [source / 'branding/branding.desc', source / 'branding/stylesheet.qss',
                 source / 'branding/show.qml', *assets.values()]:
        if not path.is_file():
            raise ValueError('Missing source: ' + str(path))
    if mode == 'installer' and not (source / 'modules/totaljs/main.py').is_file():
        raise ValueError('Missing Total.js installation module')
    branding = json.loads((source / 'branding/branding.desc').read_text())
    branding['strings']['versionedName'] = (
        f'Total.js Developer — {base.title()} {architecture} — {edition.title()} — UI Preview'
    )
    output.mkdir(parents=True)
    # -c overrides the application data directory, including its QML lookup.
    # Reuse the installed Calamares runtime instead of copying third-party code.
    (output / 'qml').symlink_to(Path(calamares_data).resolve() / 'qml', target_is_directory=True)
    brand = output / 'branding/totaljs'
    shutil.copytree(source / 'branding', brand)
    for name, path in assets.items():
        shutil.copyfile(path, brand / name)
    qt_compatible_logo(assets['logo-totaljs.svg'], brand / 'logo-totaljs-qt.svg')
    write_json(brand / 'branding.desc', branding)
    modules = output / 'modules'
    modules.mkdir()
    write_json(output / 'settings.conf', {
        'modules-search': ['local'],
        'branding': 'totaljs',
        'prompt-install': False,
        'dont-chroot': False,
        'oem-setup': False,
        'disable-cancel': False,
        'disable-cancel-during-exec': False,
        'hide-back-and-next-during-exec': False,
        'quit-at-end': False,
        # No partition page, execution queue, user creation or restart.
        # Keyboard testing may change the current graphical session's layout.
        'sequence': [{'show': ['welcome', 'locale', 'keyboard']}],
    })
    write_json(modules / 'welcome.conf', {
        'showSupportUrl': True,
        'showKnownIssuesUrl': True,
        'showReleaseNotesUrl': False,
        'showDonateUrl': False,
        'requirements': {'check': ['screen'], 'required': []},
        'geoip': {'style': 'none'},
    })
    write_json(modules / 'locale.conf', {
        'region': 'Europe', 'zone': 'Madrid', 'adjustLiveTimezone': False,
        'geoip': {'style': 'none'},
    })
    write_json(modules / 'keyboard.conf', {
        'useLocale1': False, 'configure': {'kwin': False, 'gnome': False},
    })
    write_json(output / 'preview.json', {
        'mode': 'ui-preview', 'base': base, 'architecture': architecture,
        'edition': edition, 'installation': 'online', 'can_install': False,
    })
    if mode == 'installer':
        install_profile(source, output, base, architecture, edition, repository)
    return output


def install_profile(source, output, base, architecture, edition, repository):
    from urllib.parse import urlsplit
    url = urlsplit(repository)
    if any(char.isspace() or ord(char) < 32 for char in repository) or url.scheme != 'https' or not url.hostname or url.username or url.password or url.query or url.fragment:
        raise ValueError('The package repository must be an HTTPS URL without credentials or parameters')
    modules = output / 'modules'
    shutil.copytree(source / 'modules/totaljs', modules / 'totaljs',
                    ignore=shutil.ignore_patterns('__pycache__'))
    if base == 'ubuntu':
        shutil.copytree(source / 'modules/bootloader', modules / 'bootloader',
                        ignore=shutil.ignore_patterns('__pycache__'))
    settings = json.loads((output / 'settings.conf').read_text())
    settings['modules-search'] = [str(modules), 'local']
    settings['prompt-install'] = True
    settings['disable-cancel-during-exec'] = True
    settings['hide-back-and-next-during-exec'] = True
    settings['instances'] = [
        {'module': 'totaljs', 'id': phase, 'config': f'totaljs-{phase}.conf',
         'weight': {'bootstrap': 12, 'finalize': 3}.get(phase, 1)}
        for phase in ['preflight', 'bootstrap', 'finalize', 'arm-bootloader']
    ]
    for phase in ['preflight', 'bootstrap', 'finalize', 'arm-bootloader']:
        write_json(modules / f'totaljs-{phase}.conf', {
            'phase': phase, 'base': base, 'architecture': architecture,
            'repository': repository.rstrip('/'),
        })
    arm_boot = base == 'arch' and architecture == 'arm64'
    settings['sequence'] = [
        {'show': ['welcome', 'locale', 'keyboard', 'packagechooser', 'partition', 'users', 'summary']},
        {'exec': ['totaljs@preflight', 'partition', 'mount', 'totaljs@bootstrap',
                  'machineid', 'fstab', 'locale', 'keyboard', 'localecfg', 'users',
                  'networkcfg', 'hwclock', 'totaljs@finalize',
                  'totaljs@arm-bootloader' if arm_boot else 'bootloader', 'umount']},
        {'show': ['finished']},
    ]
    write_json(output / 'settings.conf', settings)
    brand = output / 'branding/totaljs/branding.desc'
    branding = json.loads(brand.read_text())
    branding['strings']['productName'] = 'Total.js Developer'
    branding['strings'].update({
        'version': 'Experimental', 'shortVersion': 'Experimental',
        'versionedName': f'Total.js Developer ({base.title()}, {architecture})',
        'shortVersionedName': 'Total.js Developer (Experimental)',
    })
    write_json(brand, branding)
    welcome = json.loads((modules / 'welcome.conf').read_text())
    welcome['requirements'] = {
        'requiredStorage': 30, 'requiredRam': 3.5,
        'internetCheckUrl': repository.rstrip('/') + '/totaljs-developer.gpg',
        'check': ['storage', 'ram', 'power', 'internet', 'root', 'screen'],
        'required': ['storage', 'ram', 'internet', 'root', 'screen'],
    }
    write_json(modules / 'welcome.conf', welcome)
    write_json(modules / 'packagechooser.conf', {
        'mode': 'required', 'method': 'legacy', 'default': edition,
        'labels': {'step': 'Edition'},
        'items': [
            {'id': 'desktop', 'name': 'Desktop', 'screenshot': str(output / 'branding/totaljs/desktop.jpg'),
             'description': 'The Total.js workspace with a lightweight desktop, browsers, Code, Flow and PostgreSQL. Packages are downloaded during installation.'},
            {'id': 'server', 'name': 'Server', 'screenshot': str(output / 'branding/totaljs/server.jpg'),
             'description': 'The Total.js tools and services with console and SSH access. No desktop is installed. Packages are downloaded during installation.'},
        ],
    })
    write_json(modules / 'partition.conf', {
        'efi': {'mountPoint': '/boot' if arm_boot else '/boot/efi',
                'recommendedSize': '1024MiB', 'minimumSize': '512MiB', 'label': 'TOTALJS_EFI'},
        'initialPartitioningChoice': 'none', 'initialSwapChoice': 'none',
        'enableLuksAutomatedPartitioning': False,
        'userSwapChoices': ['none', 'small'], 'defaultFileSystemType': 'ext4',
        'availableFileSystemTypes': ['ext4'],
        'partitionLayout': [{'name': 'TOTALJS_ROOT', 'filesystem': 'ext4',
                             'mountPoint': '/', 'size': '100%', 'minSize': '28G'}],
        'drawNestedPartitions': False,
        'alwaysShowPartitionLabels': True,
    })
    # The bootstrap job adds pseudo-filesystems after debootstrap/pacstrap finish.
    write_json(modules / 'mount.conf', {'extraMounts': []})
    sudo = 'sudo' if base == 'ubuntu' else 'wheel'
    write_json(modules / 'users.conf', {
        'defaultGroups': [sudo, 'audio', 'video', 'totaljs-developer', 'docker'],
        'sudoersGroup': sudo, 'sudoersConfigureWithGroup': True,
        'setRootPassword': False, 'doReusePassword': False,
        'displayAutologin': False, 'doAutologin': False,
        'passwordRequirements': {'minLength': 8},
        'allowWeakPasswords': False,
    })
    write_json(modules / 'bootloader.conf', {
        'efiBootLoader': 'grub', 'efiBootloaderId': 'ubuntu' if base == 'ubuntu' else 'totaljs',
        'grubInstall': 'grub-install', 'grubMkconfig': 'grub-mkconfig',
        'grubCfg': '/boot/grub/grub.cfg', 'grubProbe': 'grub-probe',
        'efiBootMgr': 'efibootmgr', 'installEFIFallback': True,
    })
    write_json(modules / 'finished.conf', {'restartNowMode': 'user-unchecked', 'notifyOnFinished': False})
    (output / 'preview.json').unlink()
    write_json(output / 'installer.json', {
        'mode': 'experimental-online-installer', 'base': base, 'architecture': architecture,
        'defaultEdition': edition, 'installation': 'online', 'can_install': True,
        'validatedInVM': False,
    })


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--base', choices=['ubuntu', 'arch'], required=True)
    parser.add_argument('--arch', choices=['amd64', 'arm64'], required=True)
    parser.add_argument('--edition', choices=['desktop', 'server'], default='desktop')
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--mode', choices=['preview', 'installer'], default='preview')
    parser.add_argument('--repository', default='https://totaljs-es.github.io/developer-distros/repo')
    parser.add_argument('--repo', type=Path, default=Path(__file__).resolve().parents[2])
    parser.add_argument('--calamares-data', type=Path, default=Path('/usr/share/calamares'),
                        help='Installed Calamares data directory on the preview machine')
    args = parser.parse_args()
    try:
        output = render(args.repo, args.output, args.base, args.arch, args.edition, args.calamares_data,
                        args.mode, args.repository)
    except (ValueError, OSError) as error:
        parser.exit(1, f'{error}\n')
    print(f'{args.mode} profile generated. On Linux: calamares -c {output}')


if __name__ == '__main__':
    main()
