#!/usr/bin/env python3
"""Makes a PKGBUILD for Arch from a package of packages/ (the layout of Debian), so that there is one source for both distributions.

    mkpkg.py PACKAGE-DIR OUT-DIR       one package
    mkpkg.py --all OUT-DIR             every package of packages/ that is not in arch/skip

OUT-DIR/<name>/ gets: PKGBUILD, <name>.install and files/ (a copy of packages/<name>/files). The scripts of Debian (postinst, prerm, postrm)
become the functions of the .install file as they are: they only change where Debian and Arch really differ (the architecture name).
"""
import os
import re
import shutil
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
PACKAGES = os.path.join(os.path.dirname(HERE), 'packages')

ARCH_NAME = '{ case "$(uname -m)" in x86_64) echo amd64;; aarch64) echo arm64;; *) uname -m;; esac; }'


def read_map():
    table = {}
    with open(os.path.join(HERE, 'depends.map')) as f:
        for line in f:
            line = line.split('#', 1)[0].strip()
            if not line:
                continue
            parts = line.split()
            table[parts[0]] = [] if parts[1:] == ['-'] else parts[1:]
    return table


def read_skip():
    with open(os.path.join(HERE, 'skip')) as f:
        return {l.split('#', 1)[0].strip() for l in f if l.split('#', 1)[0].strip()}


def parse_control(path):
    fields, key = {}, None
    with open(path) as f:
        for line in f.read().split('\n'):
            if not line:
                continue
            if line[0] in ' \t':
                if key:
                    fields[key] += '\n' + line.strip()
            else:
                key, _, value = line.partition(':')
                fields[key] = value.strip()
    return fields


def convert_depends(text, table, name):
    result = []
    for item in text.replace('\n', ' ').split(','):
        item = item.strip()
        if not item:
            continue
        item = item.split('|')[0].strip()  # alternatives: the first one
        match = re.match(r'^([a-z0-9.+-]+)\s*(?:\(\s*(>=|<=|=|>>|<<)\s*([^)\s]+)\s*\))?$', item)
        if not match:
            sys.exit(f'{name}: cannot read the dependency "{item}"')
        dep, op, version = match.groups()
        if dep in table:
            names = table[dep]
        elif dep.startswith('totaljs-'):
            names = [dep]
        else:
            sys.exit(f'{name}: the dependency "{dep}" is not in arch/depends.map')
        for n in names:
            if op and dep.startswith('totaljs-') and n == dep:
                op2 = {'>>': '>', '<<': '<'}.get(op, op)
                version = version.split('-')[0] if op2 in ('>=', '>', '<=', '<') and '-' in version else version
                n = f'{n}{op2}{version}'
            if n not in result:
                result.append(n)
    return result


def script_body(path):
    if not os.path.exists(path):
        return None
    with open(path) as f:
        text = f.read()
    text = re.sub(r'^#!.*\n', '', text, count=1)
    text = text.replace('dpkg --print-architecture', ARCH_NAME)
    return text


def make(package_dir, out_dir, table):
    name = os.path.basename(os.path.normpath(package_dir))
    control = parse_control(os.path.join(package_dir, 'control'))
    version, _, release = control['Version'].partition('-')
    release = release or '1'
    description = control.get('Description', name).split('\n')[0].replace('"', "'").replace('$', '').replace('`', "'")
    depends = convert_depends(control.get('Depends', ''), table, name)

    target = os.path.join(out_dir, name)
    shutil.rmtree(target, ignore_errors=True)
    os.makedirs(target)
    files = os.path.join(package_dir, 'files')
    if os.path.isdir(files):
        shutil.copytree(files, os.path.join(target, 'files'), symlinks=True)
    else:
        os.makedirs(os.path.join(target, 'files'))

    # `include`: lines "<path in this repository> <path in the package>" (the wallpapers, the splash, the icons and the logo are kept once, in shared/ and tools/)
    include = os.path.join(package_dir, 'include')
    if os.path.isfile(include):
        repo_root = os.path.dirname(PACKAGES)
        with open(include) as f:
            for line in f:
                line = line.strip()
                if not line or line.startswith('#'):
                    continue
                source, dest = line.split(None, 1)
                source = os.path.join(repo_root, source)
                dest = os.path.join(target, 'files', dest.strip())
                if not os.path.exists(source):
                    sys.exit(f'{name}: include: {source} does not exist')
                if os.path.isdir(source):
                    shutil.copytree(source, dest, dirs_exist_ok=True)
                else:
                    os.makedirs(os.path.dirname(dest), exist_ok=True)
                    shutil.copy2(source, dest)

    overlay = os.path.join(HERE, 'overlay', name)
    if os.path.isdir(os.path.join(overlay, 'files')):
        shutil.copytree(os.path.join(overlay, 'files'), os.path.join(target, 'files'), symlinks=True, dirs_exist_ok=True)

    scripts = {fn: script_body(os.path.join(package_dir, fn)) for fn in ('postinst', 'prerm', 'postrm')}
    install = ['# Generated by arch/mkpkg.py from packages/%s: do not edit.' % name]
    for fn, body in scripts.items():
        if body is not None:
            install.append('_%s() {\n%s\n}' % (fn, body.rstrip('\n')))
    extra = script_body(os.path.join(overlay, 'postinst'))
    if extra is not None:
        install.append('_postinst_arch() {\n%s\n}' % extra.rstrip('\n'))
    if scripts['postinst'] is not None or extra is not None:
        run = '( _postinst configure "%s" ); ' if scripts['postinst'] is not None else ''
        run_arch = '( _postinst_arch ); ' if extra is not None else ''
        install.append('post_install() { %s%s}' % (run % '' if run else '', run_arch))
        install.append('post_upgrade() { %s%s}' % (run % '$2' if run else '', run_arch))
    if scripts['prerm'] is not None:
        install.append('pre_remove() { ( _prerm remove ); }')
    if scripts['postrm'] is not None:
        install.append('post_remove() { ( _postrm remove ); }')
    has_install = len(install) > 1
    if has_install:
        with open(os.path.join(target, name + '.install'), 'w') as f:
            f.write('\n'.join(install) + '\n')

    pkgbuild = [
        '# Generated by arch/mkpkg.py from packages/%s: do not edit.' % name,
        'pkgname=%s' % name,
        'pkgver=%s' % version,
        'pkgrel=%s' % release,
        'pkgdesc="%s"' % description,
        "arch=('any')",
        'url="%s"' % control.get('Homepage', 'https://www.totaljs.com'),
        "license=('MIT')",
        'depends=(%s)' % ' '.join("'%s'" % d for d in depends),
        "options=('!strip' '!debug' '!emptydirs')",
    ]
    if has_install:
        pkgbuild.append('install=%s.install' % name)
    pkgbuild += ['package() {', '  cp -a "${startdir}/files/." "${pkgdir}/"', '}']
    with open(os.path.join(target, 'PKGBUILD'), 'w') as f:
        f.write('\n'.join(pkgbuild) + '\n')
    return name


def main():
    args = sys.argv[1:]
    table = read_map()
    if len(args) == 2 and args[0] == '--all':
        skip = read_skip()
        names = sorted(d for d in os.listdir(PACKAGES) if os.path.isfile(os.path.join(PACKAGES, d, 'control')) and d not in skip)
        for d in names:
            make(os.path.join(PACKAGES, d), args[1], table)
            print('arch: ' + d)
    elif len(args) == 2:
        make(args[0], args[1], table)
    else:
        sys.exit(__doc__)


if __name__ == '__main__':
    main()
