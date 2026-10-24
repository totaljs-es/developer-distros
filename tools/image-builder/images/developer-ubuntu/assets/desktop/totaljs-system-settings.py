#!/usr/bin/env python3
"""Narrow root helper for Total Settings login and keyboard controls."""
import grp
import os
import pwd
import re
import shutil
import subprocess
import sys


FALLBACK_KEYMAPS = {"us", "gb", "es", "fr", "de", "it", "pt", "br", "nl"}


def run(command):
    subprocess.run(command, check=False)


def is_arch():
    try:
        data = {}
        with open("/etc/os-release", encoding="utf-8") as source:
            for line in source:
                if "=" in line:
                    key, _, value = line.partition("=")
                    data[key] = value.strip().strip('"').lower()
        return "arch" in data.get("ID", "") or "arch" in data.get("ID_LIKE", "")
    except OSError:
        return False


def installed_keymaps():
    layouts = set()
    for path in ("/usr/share/X11/xkb/rules/evdev.lst", "/usr/share/X11/xkb/rules/base.lst"):
        try:
            section = None
            with open(path, encoding="utf-8", errors="replace") as source:
                for raw_line in source:
                    line = raw_line.strip()
                    if line.startswith("!"):
                        fields = line[1:].strip().split()
                        section = fields[0] if fields else None
                    elif section == "layout" and line:
                        code = line.split(None, 1)[0]
                        if re.fullmatch(r"[A-Za-z0-9_-]+", code):
                            layouts.add(code)
            if layouts:
                break
        except OSError:
            continue
    return layouts or FALLBACK_KEYMAPS


def invoking_user():
    try:
        uid = int(os.environ["PKEXEC_UID"])
        account = pwd.getpwuid(uid)
    except (KeyError, ValueError):
        raise ValueError("This helper must be launched by Total Settings through PolicyKit.")
    if account.pw_uid == 0:
        raise ValueError("Automatic root login is not allowed.")
    return account.pw_name


def apply_autologin(enabled):
    username = invoking_user()
    try:
        grp.getgrnam("autologin")
        run(["usermod", "-aG", "autologin", username])
    except KeyError:
        pass

    os.makedirs("/etc/lightdm/lightdm.conf.d", exist_ok=True)
    lines = ["[Seat:*]"]
    if enabled:
        lines += [
            f"autologin-user={username}",
            "autologin-user-timeout=0",
            "autologin-session=openbox",
        ]
    lines += [
        "user-session=openbox",
        "greeter-session=lightdm-gtk-greeter",
    ]
    path = "/etc/lightdm/lightdm.conf.d/50-totalvm.conf"
    with open(path + ".tmp", "w", encoding="utf-8") as destination:
        destination.write("\n".join(lines) + "\n")
    os.chmod(path + ".tmp", 0o644)
    os.replace(path + ".tmp", path)


def apply_keyboard(layout):
    if layout not in installed_keymaps():
        raise ValueError(f"Unknown keyboard layout: {layout}")
    if is_arch():
        os.makedirs("/etc/X11/xorg.conf.d", exist_ok=True)
        with open("/etc/X11/xorg.conf.d/00-keyboard.conf", "w", encoding="utf-8") as destination:
            destination.write(
                'Section "InputClass"\n'
                '    Identifier "system-keyboard"\n'
                '    MatchIsKeyboard "on"\n'
                f'    Option "XkbLayout" "{layout}"\n'
                'EndSection\n'
            )
        run(["localectl", "set-x11-keymap", layout])
        return

    path = "/etc/default/keyboard"
    try:
        with open(path, encoding="utf-8") as source:
            content = source.read()
    except OSError:
        content = 'XKBMODEL="pc105"\nXKBVARIANT=""\nXKBOPTIONS=""\n'
    if re.search(r"^XKBLAYOUT=.*$", content, flags=re.MULTILINE):
        content = re.sub(r"^XKBLAYOUT=.*$", f'XKBLAYOUT="{layout}"', content, flags=re.MULTILINE)
    else:
        content = content.rstrip() + f'\nXKBLAYOUT="{layout}"\n'
    with open(path + ".tmp", "w", encoding="utf-8") as destination:
        destination.write(content)
    os.chmod(path + ".tmp", 0o644)
    os.replace(path + ".tmp", path)
    if shutil.which("setupcon"):
        run(["setupcon", "--force"])


def main():
    if os.geteuid() != 0 or len(sys.argv) != 3:
        raise ValueError("Invalid Total Settings request.")
    operation, value = sys.argv[1:]
    if operation == "autologin" and value in {"on", "off"}:
        apply_autologin(value == "on")
    elif operation == "keyboard":
        apply_keyboard(value)
    else:
        raise ValueError("Unsupported Total Settings operation.")


if __name__ == "__main__":
    try:
        main()
    except Exception as error:  # noqa: BLE001 - return one useful UI message
        print(error, file=sys.stderr)
        sys.exit(1)
