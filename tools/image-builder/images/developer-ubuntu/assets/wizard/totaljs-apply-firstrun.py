#!/usr/bin/env python3
"""Root-side helper for the Total.js Developer first-run wizard.

Invoked via a narrowly-scoped sudoers NOPASSWD rule (see 90-totaljs-wizard in
/etc/sudoers.d). Takes the path to a JSON file written by the unprivileged
wizard UI, applies every privileged change, then removes the file.
"""
import json
import grp
import os
import pwd
import re
import shutil
import subprocess
import sys

CONFIG_DIRS = [
    "openbox", "tint2", "alacritty", "conky", "picom", "rofi", "dunst",
    "gsimplecal",
]
FALLBACK_KEYMAPS = {"us", "gb", "es", "fr", "de", "it", "pt", "br", "nl"}
CONKY_PROFILES = {
    "system", "minimal", "terminal", "dashboard",
    "compact", "services", "hidden",
}
WALLPAPER_PROFILES = {"signature", "shuffle"}


def run(cmd, **kwargs):
    # Default to check=True, but let callers override with check=False without
    # "got multiple values for keyword argument 'check'".
    kwargs.setdefault("check", True)
    subprocess.run(cmd, **kwargs)


def installed_keymaps() -> set[str]:
    """Load valid layout identifiers from this distro's installed XKB data."""
    layouts = set()
    for path in (
        "/usr/share/X11/xkb/rules/evdev.lst",
        "/usr/share/X11/xkb/rules/base.lst",
    ):
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
                return layouts
        except OSError:
            continue

    try:
        result = subprocess.run(
            ["localectl", "list-x11-keymap-layouts", "--no-pager"],
            text=True, capture_output=True, check=False,
        )
        layouts.update(
            code for code in (line.strip() for line in result.stdout.splitlines())
            if re.fullmatch(r"[A-Za-z0-9_-]+", code)
        )
    except OSError:
        pass
    return layouts or FALLBACK_KEYMAPS


def os_release() -> dict:
    # Shared between the Ubuntu and Arch images; a few privileged operations have
    # distro-specific names (admin group, sshd unit, keyboard config).
    data = {}
    try:
        with open("/etc/os-release") as f:
            for line in f:
                if "=" in line:
                    key, _, value = line.partition("=")
                    data[key.strip()] = value.strip().strip('"').lower()
    except OSError:
        pass
    return data


# Detect Arch via ID *and* ID_LIKE: Arch Linux ARM reports ID=archarm (NOT
# "arch"), with ID_LIKE=arch — so a plain `ID == "arch"` check missed it and the
# wizard fell back to Debian names (group `sudo` doesn't exist on Arch → the
# "usermod: group 'sudo' does not exist" failure).
_OSREL = os_release()
IS_ARCH = "arch" in _OSREL.get("ID", "") or "arch" in _OSREL.get("ID_LIKE", "")
# Arch grants admin rights via the `wheel` group and ships OpenSSH as `sshd`;
# Debian/Ubuntu use `sudo` and `ssh`.
ADMIN_GROUP = "wheel" if IS_ARCH else "sudo"
SSH_UNIT = "sshd" if IS_ARCH else "ssh"


def user_exists(name: str) -> bool:
    try:
        pwd.getpwnam(name)
        return True
    except KeyError:
        return False


def apply_user(data: dict) -> str:
    username = data["username"].strip()
    full_name = data.get("full_name", "").strip() or "Total.js Developer"
    password = data["password"]

    if not re.fullmatch(r"[a-z](?:[a-z0-9-]{0,30}[a-z0-9])?", username):
        raise ValueError(f"invalid username: {username!r}")
    if user_exists(username) and username != "totaljs":
        raise ValueError(f"username already exists: {username!r}")
    if not password:
        raise ValueError("password must not be empty")
    if any(char in full_name for char in ":,\n\r"):
        raise ValueError("full name contains unsupported characters")

    if not user_exists(username):
        run([
            "useradd", "-m", "-s", "/bin/bash",
            "-c", full_name, username,
        ])
    groups = [ADMIN_GROUP, "docker", "autologin"]
    for optional in ("audio", "video"):
        try:
            grp.getgrnam(optional)
            groups.append(optional)
        except KeyError:
            pass
    run(["usermod", "-aG", ",".join(groups), username])
    run(["chpasswd"], input=f"{username}:{password}\n", text=True)
    run(["usermod", "-U", "-s", "/bin/bash", username])
    if os.path.isdir("/www"):
        # /www is normally a macOS-backed virtiofs share. Linux can create and
        # edit its files, but the host filesystem does not permit chown, and a
        # recursive ownership change used to make the entire wizard fail.
        mount = subprocess.run(
            ["findmnt", "-n", "-o", "FSTYPE", "/www"],
            text=True, capture_output=True, check=False,
        )
        if mount.stdout.strip() != "virtiofs":
            run(["chown", "-R", f"{username}:{username}", "/www"])

    home = f"/home/{username}"
    src_home = "/home/totaljs"
    if username != "totaljs":
        os.makedirs(f"{home}/.config", exist_ok=True)
        for name in CONFIG_DIRS:
            src = f"{src_home}/.config/{name}"
            dst = f"{home}/.config/{name}"
            if os.path.isdir(src) and not os.path.isdir(dst):
                shutil.copytree(src, dst)
        os.makedirs(f"{home}/.config/totaljs", exist_ok=True)
        run(["chown", "-R", f"{username}:{username}", f"{home}/.config"])

    os.makedirs(f"{home}/.config/totaljs", exist_ok=True)
    with open(f"{home}/.config/totaljs/first-run.done", "w") as f:
        f.write("")
    run(["chown", "-R", f"{username}:{username}", f"{home}/.config/totaljs"])

    apply_login_mode(username, bool(data.get("autologin", True)))
    apply_desktop_preferences(username, data)

    if username != "totaljs":
        # Infrastructure services use dedicated system accounts, so the public
        # bootstrap identity can disappear completely after the real account is
        # ready. Schedule deletion after the wizard session has ended.
        cleanup = "/usr/local/sbin/totaljs-remove-bootstrap-user"
        with open(cleanup, "w") as f:
            f.write("#!/usr/bin/env bash\n")
            f.write("sleep 2\n")
            f.write("pkill -KILL -u totaljs 2>/dev/null || true\n")
            f.write("userdel -r totaljs 2>/dev/null || true\n")
            f.write("rm -f /var/lib/AccountsService/users/totaljs\n")
        os.chmod(cleanup, 0o700)
        unit = "/etc/systemd/system/totaljs-bootstrap-cleanup.service"
        with open(unit, "w") as f:
            f.write("[Unit]\nDescription=Remove the Total.js bootstrap account\n")
            f.write("After=local-fs.target\nBefore=lightdm.service\n\n")
            f.write("[Service]\nType=oneshot\n")
            f.write(f"ExecStart={cleanup}\n")
            f.write("ExecStartPost=/usr/bin/systemctl disable totaljs-bootstrap-cleanup.service\n\n")
            f.write("[Install]\nWantedBy=multi-user.target\n")
        run(["systemctl", "enable", "totaljs-bootstrap-cleanup.service"], check=False)

    enable_password_ssh()

    return username


def apply_login_mode(username: str, autologin: bool):
    """Rewrite the LightDM seat config for the chosen sign-in behaviour.

    autologin=True  -> boot straight into the desktop as `username`.
    autologin=False -> show the greeter and ask for the password every time
                       (the autologin-* keys are simply omitted).
    """
    os.makedirs("/etc/lightdm/lightdm.conf.d", exist_ok=True)
    conf = "/etc/lightdm/lightdm.conf.d/50-totalvm.conf"
    lines = ["[Seat:*]"]
    if autologin:
        lines += [
            f"autologin-user={username}",
            "autologin-user-timeout=0",
            "autologin-session=openbox",
        ]
    lines += [
        "user-session=openbox",
        "greeter-session=lightdm-gtk-greeter",
    ]
    with open(conf, "w") as f:
        f.write("\n".join(lines) + "\n")


def apply_desktop_preferences(username: str, data: dict):
    conky = data.get("desktop_stats", "system")
    wallpaper = data.get("wallpaper", "shuffle")
    if conky not in CONKY_PROFILES or wallpaper not in WALLPAPER_PROFILES:
        raise ValueError("invalid desktop preferences")

    home = pwd.getpwnam(username).pw_dir
    state_dir = os.path.join(home, ".config", "totaljs")
    os.makedirs(state_dir, exist_ok=True)
    with open(os.path.join(state_dir, "conky-profile"), "w") as f:
        f.write(conky + "\n")

    pinned = os.path.join(state_dir, "wallpaper")
    if wallpaper == "signature":
        shutil.copy2("/usr/share/backgrounds/totaljs/wallpaper.jpg", pinned)
    elif os.path.exists(pinned):
        os.remove(pinned)
    run(["chown", "-R", f"{username}:{username}", state_dir])


def enable_password_ssh():
    os.makedirs("/etc/ssh/sshd_config.d", exist_ok=True)
    with open("/etc/ssh/sshd_config.d/60-totaljs-developer.conf", "w") as f:
        f.write("PasswordAuthentication yes\n")
        f.write("PermitRootLogin no\n")
    # The image ships with its host keys removed (so every VM gets unique ones);
    # generate any that are missing before (re)starting sshd, or it fails to
    # start ("ssh.service failed").
    run(["ssh-keygen", "-A"], check=False)
    run(["systemctl", "restart", SSH_UNIT], check=False)


def apply_keyboard(layout: str):
    # On Ubuntu/Debian, `localectl set-x11-keymap` is NOT supported (localed
    # refuses with "Setting X11 and console keymaps is not supported in
    # Debian") — the correct way is to write /etc/default/keyboard and let
    # console-setup apply it. So we do exactly that, no localectl.
    if layout not in installed_keymaps():
        raise ValueError(f"invalid keyboard layout: {layout!r}")
    if IS_ARCH:
        # Arch has no console-setup / /etc/default/keyboard. Set the X11 layout
        # the native way and apply it live with localectl (which, unlike Debian,
        # Arch fully supports).
        os.makedirs("/etc/X11/xorg.conf.d", exist_ok=True)
        with open("/etc/X11/xorg.conf.d/00-keyboard.conf", "w") as f:
            f.write(
                'Section "InputClass"\n'
                '    Identifier "system-keyboard"\n'
                '    MatchIsKeyboard "on"\n'
                f'    Option "XkbLayout" "{layout}"\n'
                'EndSection\n'
            )
        run(["localectl", "set-x11-keymap", layout], check=False)
        return
    keyboard_default = "/etc/default/keyboard"
    if os.path.exists(keyboard_default):
        with open(keyboard_default) as f:
            content = f.read()
        content = re.sub(r'^XKBLAYOUT=.*$', f'XKBLAYOUT="{layout}"', content, flags=re.MULTILINE)
    else:
        content = f'XKBMODEL="pc105"\nXKBLAYOUT="{layout}"\nXKBVARIANT=""\nXKBOPTIONS=""\n'
    with open(keyboard_default, "w") as f:
        f.write(content)
    # Apply now for the running console/X session (best-effort, non-fatal).
    if shutil.which("setupcon"):
        run(["setupcon", "--force"], check=False)


def installed_locales() -> set[str]:
    locales = {"C.UTF-8"}
    try:
        result = subprocess.run(
            ["locale", "-a"], text=True, capture_output=True, check=False,
        )
        locales.update(
            value.strip().replace(".utf8", ".UTF-8")
            for value in result.stdout.splitlines()
            if value.strip()
        )
    except OSError:
        pass

    try:
        with open("/etc/locale.gen", encoding="utf-8", errors="replace") as source:
            for line in source:
                match = re.match(r"^#?\s*([^#\s]+\.UTF-8)\s+UTF-8\b", line)
                if match:
                    locales.add(match.group(1))
    except OSError:
        pass
    return locales


def apply_locale(locale_value: str):
    locale_value = locale_value.strip().replace(".utf8", ".UTF-8")
    if locale_value not in installed_locales():
        raise ValueError(f"invalid locale: {locale_value!r}")

    if os.path.exists("/etc/locale.gen") and locale_value not in {"C", "C.UTF-8", "POSIX"}:
        escaped = re.escape(locale_value)
        try:
            with open("/etc/locale.gen", encoding="utf-8", errors="replace") as source:
                content = source.read()
            content = re.sub(
                rf"^#\s*({escaped}\s+UTF-8\b)",
                r"\1",
                content,
                flags=re.MULTILINE,
            )
            if not re.search(rf"^{escaped}\s+UTF-8\b", content, flags=re.MULTILINE):
                content += f"\n{locale_value} UTF-8\n"
            with open("/etc/locale.gen", "w", encoding="utf-8") as target:
                target.write(content)
        except OSError:
            pass
        if shutil.which("locale-gen"):
            run(["locale-gen"], check=False)

    with open("/etc/locale.conf", "w", encoding="utf-8") as f:
        f.write(f"LANG={locale_value}\n")
    if shutil.which("update-locale"):
        run(["update-locale", f"LANG={locale_value}"], check=False)
    else:
        os.makedirs("/etc/default", exist_ok=True)
        with open("/etc/default/locale", "w", encoding="utf-8") as f:
            f.write(f"LANG={locale_value}\n")


def valid_timezone(timezone: str) -> bool:
    if not re.fullmatch(r"[A-Za-z0-9_+\-/]+", timezone):
        return False
    zone_path = os.path.realpath(os.path.join("/usr/share/zoneinfo", timezone))
    zone_root = os.path.realpath("/usr/share/zoneinfo")
    return zone_path.startswith(zone_root + os.sep) and os.path.isfile(zone_path)


def apply_timezone(timezone: str):
    timezone = timezone.strip()
    if not valid_timezone(timezone):
        raise ValueError(f"invalid timezone: {timezone!r}")
    applied = False
    if shutil.which("timedatectl"):
        result = subprocess.run(["timedatectl", "set-timezone", timezone], check=False)
        applied = result.returncode == 0
    if not applied:
        tmp = "/etc/localtime.tmp"
        try:
            os.remove(tmp)
        except OSError:
            pass
        os.symlink(f"/usr/share/zoneinfo/{timezone}", tmp)
        os.replace(tmp, "/etc/localtime")
    with open("/etc/timezone", "w", encoding="utf-8") as f:
        f.write(timezone + "\n")


def apply_regional_settings(data: dict):
    if data.get("locale"):
        apply_locale(data["locale"])
    if data.get("timezone"):
        apply_timezone(data["timezone"])


def main():
    if len(sys.argv) != 2:
        print("usage: totaljs-apply-firstrun.py <json-path>", file=sys.stderr)
        sys.exit(2)

    json_path = sys.argv[1]
    with open(json_path) as f:
        data = json.load(f)

    try:
        username = apply_user(data)

        if data.get("keymap"):
            apply_keyboard(data["keymap"])
        apply_regional_settings(data)

        # The bootstrap privilege exists only for this one successful setup.
        try:
            os.remove("/etc/sudoers.d/90-totaljs-wizard")
        except OSError:
            pass

        # The bootstrap account may now be locked, so schedule the reboot while
        # this root helper still owns the operation instead of relying on Polkit.
        # ~6s gives the wizard's "restarting" screen time to show before the
        # machine actually reboots, so it never looks like it just closed.
        run([
            "systemd-run", "--on-active=6s", "--unit=totaljs-first-run-reboot",
            "systemctl", "reboot",
        ])

        print(f"OK username={username}")
    except Exception as exc:  # noqa: BLE001 — surface a clean message, not a traceback
        print(f"ERROR: {exc}", file=sys.stderr)
        sys.exit(1)
    finally:
        try:
            os.remove(json_path)
        except OSError:
            pass


if __name__ == "__main__":
    main()
