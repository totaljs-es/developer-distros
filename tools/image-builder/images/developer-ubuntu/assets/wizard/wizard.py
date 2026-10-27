#!/usr/bin/env python3
"""Total.js Developer — first-run setup wizard.

Runs once on first login (see openbox autostart). Collects the developer
account, keyboard layout and regional settings, then hands the privileged work
off to totaljs-apply-firstrun.py via a scoped sudoers rule.
"""
import json
import os
import pwd
import re
import secrets
import subprocess
import threading
import unicodedata

import gi

gi.require_version("Gtk", "3.0")
# Pin Gdk to 3.0 too: GTK4 is also present on the image (pulled in by Firefox),
# so a bare `import Gdk` loads Gdk 4.0 and then clashes with our Gtk 3.0,
# crashing the wizard at import (gi.RepositoryError: Gdk 3.0 vs 4.0).
gi.require_version("Gdk", "3.0")
from gi.repository import Gdk, GLib, Gtk  # noqa: E402

# GdkPixbuf is only needed for the welcome logo. Guard the import so a missing
# typelib degrades to "no logo" instead of crashing the whole wizard before a
# window can appear.
try:
    gi.require_version("GdkPixbuf", "2.0")
    from gi.repository import GdkPixbuf  # noqa: E402
    HAVE_PIXBUF = True
except (ImportError, ValueError):
    HAVE_PIXBUF = False

GLib.set_prgname("TotalJSSetup")

GREEN = "#6ac043"
BG = "#15181c"
PANEL = "#1c2126"
FG = "#d7d9dc"
MUTED = "#8b949e"

CSS = f"""
window {{ background-color: {BG}; }}
.wizard-title {{ color: {FG}; font-size: 22px; font-weight: bold; }}
.wizard-subtitle {{ color: {MUTED}; font-size: 13px; }}
.wizard-panel {{ background-color: {PANEL}; border-radius: 10px; padding: 18px; }}
entry {{ background-color: #0f1316; color: {FG}; border: 1px solid #2a3036; border-radius: 6px; padding: 8px; }}
entry:focus {{ border-color: {GREEN}; }}
combobox, combobox box, combobox button, combobox button.combo {{ background-color: #0f1316; color: {FG}; background-image: none; box-shadow: none; outline: none; }}
combobox button, combobox button.combo {{ border: 1px solid #2a3036; border-radius: 6px; padding: 7px 10px; font-size: 14px; }}
combobox button:hover, combobox button.combo:hover, combobox button:active, combobox button.combo:active {{ background-color: #171c20; border-color: #3a424a; box-shadow: none; }}
combobox cellview, combobox arrow {{ color: {FG}; }}
combobox button:focus, combobox button.combo:focus {{ border-color: {GREEN}; }}
/* The dropdown list itself (a popup menu / treeview, NOT inside `combobox`) —
   style it explicitly so the options read clearly on dark, both idle and hover. */
menu, .menu, .background.menu {{ background-image: none; background-color: #0f1316; border: 1px solid #2a3036; box-shadow: none; }}
menu menuitem, menuitem {{ background-image: none; background-color: #0f1316; color: {FG}; padding: 7px 12px; }}
menu menuitem label, menuitem label, menu menuitem cellview, menuitem cellview {{ color: {FG}; }}
menuitem:hover, menuitem:selected, menuitem:active {{ background-image: none; background-color: #2c3a22; color: #ffffff; }}
menuitem:hover label, menuitem:selected label, menuitem:active label,
menuitem:hover cellview, menuitem:selected cellview, menuitem:active cellview {{ color: #ffffff; }}
treeview.view {{ background-color: #0f1316; color: {FG}; }}
treeview.view:selected, treeview.view:hover {{ background-color: #2c3a22; color: #ffffff; }}
switch {{ background-color: #2a3036; border-radius: 12px; }}
switch:checked {{ background-color: {GREEN}; }}
switch slider {{ background-color: #d7d9dc; border-radius: 11px; }}
label {{ color: {FG}; }}
.muted {{ color: {MUTED}; font-size: 12px; }}
.error {{ color: #e75a5a; font-size: 12px; }}
button.suggested-action {{ background-color: {GREEN}; color: #0f1316; font-weight: bold; border-radius: 6px; }}
button.suggested-action:hover {{ background-color: #7bd24d; }}
button.flat {{ color: {MUTED}; }}
spinner, spinner.restart-spinner {{ color: {GREEN}; -gtk-icon-shadow: none; min-width: 28px; min-height: 28px; }}
"""

FALLBACK_KEYMAPS = [
    ("English (US)", "us"),
    ("English (UK)", "gb"),
    ("Español", "es"),
    ("Français", "fr"),
    ("Deutsch", "de"),
    ("Italiano", "it"),
    ("Português", "pt"),
    ("Português (Brasil)", "br"),
    ("Nederlands", "nl"),
]


def installed_keymaps():
    """Return the layouts exposed by this distro's installed XKB data."""
    layouts = {}
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
                        fields = line.split(None, 1)
                        code = fields[0]
                        if re.fullmatch(r"[A-Za-z0-9_-]+", code):
                            layouts[code] = fields[1] if len(fields) > 1 else code
            if layouts:
                break
        except OSError:
            continue

    if not layouts:
        try:
            result = subprocess.run(
                ["localectl", "list-x11-keymap-layouts", "--no-pager"],
                text=True, capture_output=True, check=False,
            )
            for code in result.stdout.splitlines():
                code = code.strip()
                if re.fullmatch(r"[A-Za-z0-9_-]+", code):
                    layouts[code] = code
        except OSError:
            pass

    if not layouts:
        return FALLBACK_KEYMAPS
    return sorted(((label, code) for code, label in layouts.items()), key=lambda item: item[0].casefold())


def current_keymap(available_codes):
    """Prefer the layout already active in the first-login X session."""
    try:
        result = subprocess.run(
            ["setxkbmap", "-query"], text=True, capture_output=True, check=False,
        )
        match = re.search(r"^layout:\s*([^,\s]+)", result.stdout, re.MULTILINE)
        if match and match.group(1) in available_codes:
            return match.group(1)
    except OSError:
        pass
    return "us" if "us" in available_codes else next(iter(available_codes), None)


KEYMAPS = installed_keymaps()


def installed_locales():
    locales = set()
    try:
        result = subprocess.run(
            ["locale", "-a"], text=True, capture_output=True, check=False,
        )
        for value in result.stdout.splitlines():
            value = value.strip().replace(".utf8", ".UTF-8")
            if value:
                locales.add(value)
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

    for value in ("C.UTF-8", "en_US.UTF-8", "en_GB.UTF-8"):
        locales.add(value)
    return [(value, value) for value in sorted(locales, key=str.casefold)]


def current_locale(available_ids):
    for path in ("/etc/default/locale", "/etc/locale.conf"):
        try:
            with open(path, encoding="utf-8", errors="replace") as source:
                for line in source:
                    key, _, value = line.partition("=")
                    if key.strip() == "LANG":
                        locale = value.strip().strip('"').replace(".utf8", ".UTF-8")
                        if locale in available_ids:
                            return locale
        except OSError:
            pass
    try:
        result = subprocess.run(
            ["locale"], text=True, capture_output=True, check=False,
        )
        match = re.search(r'^LANG="?([^"\n]+)"?', result.stdout, re.MULTILINE)
        if match:
            locale = match.group(1).replace(".utf8", ".UTF-8")
            if locale in available_ids:
                return locale
    except OSError:
        pass
    return "C.UTF-8" if "C.UTF-8" in available_ids else next(iter(available_ids), None)


def installed_timezones():
    zones = set()
    try:
        result = subprocess.run(
            ["timedatectl", "list-timezones"], text=True, capture_output=True, check=False,
        )
        zones.update(line.strip() for line in result.stdout.splitlines() if line.strip())
    except OSError:
        pass

    if not zones:
        zone_root = "/usr/share/zoneinfo"
        skip_dirs = {"posix", "right", "SystemV"}
        try:
            for root, dirs, files in os.walk(zone_root):
                dirs[:] = [name for name in dirs if name not in skip_dirs and not name.startswith(".")]
                for filename in files:
                    path = os.path.join(root, filename)
                    rel = os.path.relpath(path, zone_root)
                    if (
                        filename.startswith(".")
                        or filename in {"localtime", "posixrules", "leapseconds", "tzdata.zi"}
                        or "." in filename
                    ):
                        continue
                    zones.add(rel)
        except OSError:
            pass

    zones.add("Etc/UTC")
    return [(value, value) for value in sorted(zones, key=str.casefold)]


def current_timezone(available_ids):
    try:
        result = subprocess.run(
            ["timedatectl", "show", "-p", "Timezone", "--value"],
            text=True, capture_output=True, check=False,
        )
        value = result.stdout.strip()
        if value in available_ids:
            return value
    except OSError:
        pass
    try:
        with open("/etc/timezone", encoding="utf-8", errors="replace") as source:
            value = source.read().strip()
            if value in available_ids:
                return value
    except OSError:
        pass
    return "Etc/UTC" if "Etc/UTC" in available_ids else next(iter(available_ids), None)


LOCALES = installed_locales()
TIMEZONES = installed_timezones()


def username_slug(value, final=False):
    """Normalize free-form typing into a safe, human Linux login name."""
    ascii_value = (
        unicodedata.normalize("NFKD", value)
        .encode("ascii", "ignore")
        .decode("ascii")
        .lower()
    )
    slug = re.sub(r"[^a-z0-9]+", "-", ascii_value)
    slug = re.sub(r"^[^a-z]+", "", slug)[:32]
    return slug.rstrip("-") if final else slug


def matching_item(items, query):
    """Return the best (label, id) match for typed combo text."""
    query = query.strip().casefold()
    if not query:
        return None
    for label, item_id in items:
        if query in (label.casefold(), item_id.casefold()):
            return label, item_id
    for label, item_id in items:
        if query in label.casefold() or query in item_id.casefold():
            return label, item_id
    return None


def make_searchable_combo(items, active_id=None):
    combo = Gtk.ComboBoxText.new_with_entry()
    combo.set_entry_text_column(0)
    for label, item_id in items:
        combo.append(item_id, label)

    entry = combo.get_child()
    completion_model = Gtk.ListStore(str, str)
    for label, item_id in items:
        completion_model.append((label, item_id))
    completion = Gtk.EntryCompletion()
    completion.set_model(completion_model)
    completion.set_text_column(0)
    completion.set_minimum_key_length(1)
    completion.set_popup_completion(True)
    completion.set_inline_selection(True)
    completion.set_match_func(
        lambda _completion, key, tree_iter, _data:
            key.casefold() in completion_model[tree_iter][0].casefold()
            or key.casefold() in completion_model[tree_iter][1].casefold(),
        None,
    )

    def select_match(_completion, model, tree_iter):
        combo.set_active_id(model[tree_iter][1])
        entry.set_position(-1)
        return True

    completion.connect("match-selected", select_match)
    entry.set_completion(completion)

    def select_typed(_entry):
        match = matching_item(items, entry.get_text())
        if match:
            combo.set_active_id(match[1])

    entry.connect("activate", select_typed)
    if active_id is not None:
        combo.set_active_id(active_id)
    return combo, entry

WIZARD_DIR = os.path.dirname(os.path.abspath(__file__))


class WizardWindow(Gtk.Window):
    def __init__(self):
        super().__init__(title="Total.js Developer Setup")
        self.set_wmclass("TotalJSSetup", "TotalJSSetup")
        self.set_role("totaljs-setup")
        self.set_default_size(620, 520)
        self.set_position(Gtk.WindowPosition.CENTER)
        self.set_resizable(False)
        self.set_decorated(False)

        self.stack = Gtk.Stack()
        self.stack.set_transition_type(Gtk.StackTransitionType.SLIDE_LEFT_RIGHT)
        self.stack.set_transition_duration(220)

        outer = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=0)
        outer.get_style_context().add_class("wizard-panel")
        outer.set_margin_top(24)
        outer.set_margin_bottom(24)
        outer.set_margin_start(24)
        outer.set_margin_end(24)
        outer.pack_start(self.stack, True, True, 0)
        self.add(outer)

        available_codes = {code for _, code in KEYMAPS}
        selected_keymap = current_keymap(available_codes)
        self.keymap_combo, self.keymap_search = make_searchable_combo(KEYMAPS, selected_keymap)
        if self.keymap_combo.get_active_id() is None:
            self.keymap_combo.set_active(0)
        # Styling GtkComboBoxText text via CSS is unreliable (it rendered nearly
        # invisible). Set the cell renderer's foreground colour directly — this
        # always wins, for both the closed value and the dropdown list.
        for cell in self.keymap_combo.get_cells():
            cell.set_property("foreground", FG)
            cell.set_property("foreground-set", True)
            cell.set_property("cell-background", "#0f1316")
            cell.set_property("cell-background-set", True)
        # Apply the chosen layout to the LIVE X session as soon as it's picked,
        # so the next fields (full name, password) can be typed with it — e.g.
        # "Güiles" needs the Spanish layout for the ü.
        self.keymap_combo.connect("changed", lambda *_: self._apply_live_keymap())

        locale_ids = {value for _, value in LOCALES}
        timezone_ids = {value for _, value in TIMEZONES}
        self.locale_combo, self.locale_search = make_searchable_combo(LOCALES, current_locale(locale_ids))
        self.timezone_combo, self.timezone_search = make_searchable_combo(TIMEZONES, current_timezone(timezone_ids))
        for combo in (self.locale_combo, self.timezone_combo):
            if combo.get_active_id() is None:
                combo.set_active(0)
            for cell in combo.get_cells():
                cell.set_property("foreground", FG)
                cell.set_property("foreground-set", True)
                cell.set_property("cell-background", "#0f1316")
                cell.set_property("cell-background-set", True)

        self._normalizing_username = False
        self.username_entry = Gtk.Entry(placeholder_text="Maximum 32 characters")
        self.username_entry.set_max_length(32)
        self.username_entry.connect("changed", self._normalize_username_entry)
        self.fullname_entry = Gtk.Entry(placeholder_text="Shown on the login screen")
        self.password_entry = Gtk.Entry(visibility=False, placeholder_text="Password")
        self.password_confirm_entry = Gtk.Entry(visibility=False, placeholder_text="Confirm password")

        # Sign-in behaviour: ON = boot straight to the desktop (default, the
        # friendliest for a single-user dev VM); OFF = show the login screen.
        self.autologin_switch = Gtk.Switch()
        self.autologin_switch.set_active(True)
        self.autologin_switch.set_halign(Gtk.Align.START)

        self.desktop_stats_combo = Gtk.ComboBoxText()
        self.desktop_stats_combo.append("system", "System overview")
        self.desktop_stats_combo.append("compact", "Compact")
        self.desktop_stats_combo.append("services", "Services")
        self.desktop_stats_combo.append("hidden", "Hidden")
        self.desktop_stats_combo.set_active_id("system")

        self.wallpaper_combo = Gtk.ComboBoxText()
        self.wallpaper_combo.append("signature", "Total.js signature")
        self.wallpaper_combo.append("shuffle", "Shuffle on login")
        self.wallpaper_combo.set_active_id("shuffle")

        for combo in (self.desktop_stats_combo, self.wallpaper_combo):
            for cell in combo.get_cells():
                cell.set_property("foreground", FG)
                cell.set_property("foreground-set", True)
                cell.set_property("cell-background", "#0f1316")
                cell.set_property("cell-background-set", True)

        self.error_label = Gtk.Label(label="")
        self.error_label.get_style_context().add_class("error")
        self.keyboard_error_label = Gtk.Label(label="")
        self.keyboard_error_label.get_style_context().add_class("error")
        self.region_error_label = Gtk.Label(label="")
        self.region_error_label.get_style_context().add_class("error")
        self.stack.add_titled(self._page_welcome(), "welcome", "Welcome")
        self.stack.add_titled(self._page_keyboard(), "keyboard", "Keyboard")
        self.stack.add_titled(self._page_region(), "region", "Region")
        self.stack.add_titled(self._page_account(), "account", "Account")
        self.stack.add_titled(self._page_appearance(), "appearance", "Appearance")
        self.stack.add_titled(self._page_apply(), "apply", "Apply")
        self.stack.add_titled(self._page_restarting(), "restarting", "Restarting")

        self.connect("map-event", self._on_mapped)
        self.show_all()
        self.apply_spinner_box.hide()

    def _on_mapped(self, *_):
        # Openbox can map undecorated windows before honoring CENTER. Recenter
        # once the native GDK window and its monitor are known.
        GLib.idle_add(self._center_on_screen)
        # Openbox can apply placement once more after GTK's map callback. Two
        # short retries keep the undecorated wizard centered deterministically.
        GLib.timeout_add(150, self._center_on_screen)
        GLib.timeout_add(450, self._center_on_screen)
        return False

    def _center_on_screen(self):
        screen = Gdk.Screen.get_default()
        if screen is None:
            return False
        width, height = 620, 520
        top_margin, bottom_margin = 34, 44
        available_height = max(height, screen.get_height() - top_margin - bottom_margin)
        self.resize(width, height)
        self.move(
            max(0, (screen.get_width() - width) // 2),
            top_margin + max(0, (available_height - height) // 2),
        )
        return False

    # --- pages ---------------------------------------------------------

    def _page_welcome(self):
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=18)
        box.set_valign(Gtk.Align.CENTER)

        logo_path = os.path.join(WIZARD_DIR, "toto-welcome.png")
        if HAVE_PIXBUF and os.path.exists(logo_path):
            try:
                pixbuf = GdkPixbuf.Pixbuf.new_from_file_at_scale(logo_path, 144, 144, True)
                image = Gtk.Image.new_from_pixbuf(pixbuf)
                box.pack_start(image, False, False, 0)
            except Exception:
                pass

        title = Gtk.Label(label="Welcome to Total.js Developer")
        title.get_style_context().add_class("wizard-title")
        box.pack_start(title, False, False, 0)

        subtitle = Gtk.Label(label="Let's get your new development environment ready.")
        subtitle.get_style_context().add_class("wizard-subtitle")
        subtitle.set_justify(Gtk.Justification.CENTER)
        box.pack_start(subtitle, False, False, 0)

        credit = Gtk.Label(label="Toto, mascot of Spanish Total.js")
        credit.get_style_context().add_class("muted")
        box.pack_start(credit, False, False, 0)

        next_btn = self._suggested_button("Get started")
        next_btn.connect("clicked", lambda *_: self.stack.set_visible_child_name("keyboard"))
        box.pack_start(self._footer(None, next_btn), False, False, 0)
        return box

    def _apply_live_keymap(self):
        code = self.keymap_combo.get_active_id()
        if not code:
            return
        try:
            subprocess.run(["setxkbmap", code], check=False)
        except Exception:
            pass

    def _page_keyboard(self):
        box = self._page_box("Keyboard layout", "Used by the desktop and terminal.")
        box.pack_start(self.keymap_combo, False, False, 0)
        box.pack_start(self.keyboard_error_label, False, False, 0)

        back_btn = self._flat_button("Back")
        back_btn.connect("clicked", lambda *_: self.stack.set_visible_child_name("welcome"))
        next_btn = self._suggested_button("Next")
        next_btn.connect("clicked", self._on_keyboard_next)
        box.pack_end(self._footer(back_btn, next_btn), False, False, 0)
        return box

    def _page_region(self):
        box = self._page_box("Regional settings", "Choose language formats and local time.")
        grid = self._form_grid([
            ("Locale", self.locale_combo),
            ("Timezone", self.timezone_combo),
        ])
        box.pack_start(grid, False, False, 0)

        hint = Gtk.Label(label="Type to search. The defaults come from the distro.")
        hint.get_style_context().add_class("muted")
        hint.set_xalign(0)
        box.pack_start(hint, False, False, 0)
        box.pack_start(self.region_error_label, False, False, 0)

        back_btn = self._flat_button("Back")
        back_btn.connect("clicked", lambda *_: self.stack.set_visible_child_name("keyboard"))
        next_btn = self._suggested_button("Next")
        next_btn.connect("clicked", self._on_region_next)
        box.pack_end(self._footer(back_btn, next_btn), False, False, 0)
        return box

    def _page_account(self):
        box = self._page_box("Create your account",
                              "This becomes your desktop login and replaces the temporary setup account.")
        grid = self._form_grid([
            ("Username", self.username_entry),
            ("Full name", self.fullname_entry),
            ("Password", self.password_entry),
            ("Confirm password", self.password_confirm_entry),
        ])
        box.pack_start(grid, False, False, 0)
        box.pack_start(self.error_label, False, False, 0)

        # Auto-login toggle (a switch reads more clearly than a checkbox here).
        login_row = Gtk.Box(spacing=10)
        login_row.set_margin_top(4)
        login_label = Gtk.Label(label="Log in automatically at startup")
        login_label.set_xalign(0)
        login_row.pack_start(login_label, True, True, 0)
        login_row.pack_start(self.autologin_switch, False, False, 0)
        box.pack_start(login_row, False, False, 0)
        login_hint = Gtk.Label(label="Off shows the login screen and asks for your password each time.")
        login_hint.get_style_context().add_class("muted")
        login_hint.set_xalign(0)
        box.pack_start(login_hint, False, False, 0)

        back_btn = self._flat_button("Back")
        back_btn.connect("clicked", lambda *_: self.stack.set_visible_child_name("region"))
        next_btn = self._suggested_button("Next")
        next_btn.connect("clicked", self._on_account_next)
        box.pack_end(self._footer(back_btn, next_btn), False, False, 0)
        return box

    def _page_appearance(self):
        box = self._page_box("Make it yours",
                              "Choose the calmest desktop for the way you work. You can change these later from the menu.")
        grid = self._form_grid([
            ("Desktop stats", self.desktop_stats_combo),
            ("Wallpaper", self.wallpaper_combo),
        ])
        box.pack_start(grid, False, False, 0)

        back_btn = self._flat_button("Back")
        back_btn.connect("clicked", lambda *_: self.stack.set_visible_child_name("account"))
        next_btn = self._suggested_button("Review")
        next_btn.connect("clicked", self._on_appearance_next)
        box.pack_end(self._footer(back_btn, next_btn), False, False, 0)
        return box

    def _page_apply(self):
        box = self._page_box("Ready to go", "")
        self.summary_label = Gtk.Label(label="")
        self.summary_label.set_justify(Gtk.Justification.LEFT)
        self.summary_label.set_xalign(0)
        box.pack_start(self.summary_label, False, False, 0)

        self.apply_spinner_box = Gtk.Box(spacing=8)
        spinner = Gtk.Spinner()
        self.apply_spinner = spinner
        self.apply_status_label = Gtk.Label(label="Applying…")
        self.apply_status_label.get_style_context().add_class("muted")
        self.apply_spinner_box.pack_start(spinner, False, False, 0)
        self.apply_spinner_box.pack_start(self.apply_status_label, False, False, 0)
        box.pack_start(self.apply_spinner_box, False, False, 0)

        back_btn = self._flat_button("Back")
        back_btn.connect("clicked", lambda *_: self.stack.set_visible_child_name("appearance"))
        self.apply_btn = self._suggested_button("Finish setup")
        self.apply_btn.connect("clicked", self._on_apply)
        self.back_btn = back_btn
        box.pack_end(self._footer(back_btn, self.apply_btn), False, False, 0)
        return box

    def _page_restarting(self):
        # Shown after the privileged apply succeeds. The machine reboots a few
        # seconds later into the new account, so we DON'T close the window — we
        # keep this calm "please wait" screen with a spinning logo up until the
        # reboot takes over, so it's obvious the user should just sit tight.
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=18)
        box.set_valign(Gtk.Align.CENTER)
        box.set_halign(Gtk.Align.CENTER)

        logo_path = os.path.join(WIZARD_DIR, "logo.png")
        if HAVE_PIXBUF and os.path.exists(logo_path):
            try:
                pixbuf = GdkPixbuf.Pixbuf.new_from_file_at_scale(logo_path, 104, 120, True)
                box.pack_start(Gtk.Image.new_from_pixbuf(pixbuf), False, False, 0)
            except Exception:
                pass

        spinner = Gtk.Spinner()
        spinner.set_size_request(32, 32)
        spinner.get_style_context().add_class("restart-spinner")
        self._restart_spinner = spinner
        box.pack_start(spinner, False, False, 0)

        title = Gtk.Label(label="Please wait… restarting")
        title.get_style_context().add_class("wizard-title")
        box.pack_start(title, False, False, 0)

        subtitle = Gtk.Label(
            label="Your environment is ready. It will restart into your\n"
                  "new account in a moment — please don't do anything yet."
        )
        subtitle.get_style_context().add_class("wizard-subtitle")
        subtitle.set_justify(Gtk.Justification.CENTER)
        box.pack_start(subtitle, False, False, 0)
        return box

    # --- helpers ---------------------------------------------------------

    def _page_box(self, title, subtitle):
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=14)
        box.set_margin_top(8)
        t = Gtk.Label(label=title)
        t.get_style_context().add_class("wizard-title")
        t.set_xalign(0)
        box.pack_start(t, False, False, 0)
        if subtitle:
            s = Gtk.Label(label=subtitle)
            s.get_style_context().add_class("wizard-subtitle")
            s.set_xalign(0)
            box.pack_start(s, False, False, 0)
        return box

    def _form_grid(self, fields):
        grid = Gtk.Grid(row_spacing=10, column_spacing=12)
        for row, (label_text, widget) in enumerate(fields):
            label = Gtk.Label(label=label_text)
            label.set_xalign(0)
            grid.attach(label, 0, row, 1, 1)
            widget.set_hexpand(True)
            grid.attach(widget, 1, row, 1, 1)
        return grid

    def _footer(self, back_btn, next_btn):
        row = Gtk.Box(spacing=10)
        row.set_margin_top(16)
        if back_btn:
            row.pack_start(back_btn, False, False, 0)
        spacer = Gtk.Box()
        row.pack_start(spacer, True, True, 0)
        row.pack_start(next_btn, False, False, 0)
        return row

    def _suggested_button(self, label):
        btn = Gtk.Button(label=label)
        btn.get_style_context().add_class("suggested-action")
        return btn

    def _flat_button(self, label):
        btn = Gtk.Button(label=label)
        btn.get_style_context().add_class("flat")
        return btn

    # --- validation / actions ---------------------------------------------

    def _on_keyboard_next(self, *_):
        self._ensure_combo_selection(self.keymap_combo, self.keymap_search, KEYMAPS)
        if self.keymap_combo.get_active_id() is None:
            self.keyboard_error_label.set_label("Choose a keyboard layout from the list.")
            return
        self.keyboard_error_label.set_label("")
        self.stack.set_visible_child_name("region")

    def _ensure_combo_selection(self, combo, entry, items):
        if combo.get_active_id() is None:
            match = matching_item(items, entry.get_text())
            if match:
                combo.set_active_id(match[1])

    def _on_region_next(self, *_):
        self._ensure_combo_selection(self.locale_combo, self.locale_search, LOCALES)
        self._ensure_combo_selection(self.timezone_combo, self.timezone_search, TIMEZONES)
        if self.locale_combo.get_active_id() is None:
            self.region_error_label.set_label("Choose a locale from the list.")
            return
        if self.timezone_combo.get_active_id() is None:
            self.region_error_label.set_label("Choose a timezone from the list.")
            return
        self.region_error_label.set_label("")
        self.stack.set_visible_child_name("account")

    def _normalize_username_entry(self, entry):
        if self._normalizing_username:
            return
        value = entry.get_text()
        normalized = username_slug(value)
        if value != normalized:
            self._normalizing_username = True
            entry.set_text(normalized)
            entry.set_position(-1)
            self._normalizing_username = False

        exists_error = "That username already exists. Please choose another one."
        existing_user = None
        if normalized:
            try:
                existing_user = pwd.getpwnam(normalized)
            except KeyError:
                pass
        if existing_user is not None and normalized != "totaljs":
            entry.set_icon_from_icon_name(Gtk.EntryIconPosition.SECONDARY, "dialog-error-symbolic")
            entry.set_icon_tooltip_text(Gtk.EntryIconPosition.SECONDARY, exists_error)
            self._set_error(exists_error)
        else:
            entry.set_icon_from_icon_name(Gtk.EntryIconPosition.SECONDARY, None)
            if self.error_label.get_text() == exists_error:
                self._set_error("")

    def _on_account_next(self, *_):
        username = username_slug(self.username_entry.get_text(), final=True)
        self.username_entry.set_text(username)
        full_name = self.fullname_entry.get_text().strip()
        password = self.password_entry.get_text()
        confirm = self.password_confirm_entry.get_text()

        if not username:
            self._set_error("Please choose a username.")
            return
        if not re.fullmatch(r"[a-z](?:[a-z0-9-]{0,30}[a-z0-9])?", username):
            self._set_error("Username must begin with a letter.")
            return
        try:
            existing_user = pwd.getpwnam(username)
        except KeyError:
            existing_user = None
        if existing_user is not None and username != "totaljs":
            self._set_error("That username already exists. Please choose another one.")
            return
        if any(char in full_name for char in ":,\n\r"):
            self._set_error("Full name cannot contain commas or colons.")
            return
        if not password:
            self._set_error("Please choose a password.")
            return
        if password != confirm:
            self._set_error("Passwords don't match.")
            return

        self._set_error("")
        self.stack.set_visible_child_name("appearance")

    def _on_appearance_next(self, *_):
        username = self.username_entry.get_text().strip()
        keymap_label = self.keymap_combo.get_active_text()
        locale_label = self.locale_combo.get_active_text()
        timezone_label = self.timezone_combo.get_active_text()
        autologin = "yes" if self.autologin_switch.get_active() else "no (ask at login)"
        self.summary_label.set_label(
            f"Keyboard:       {keymap_label}\n"
            f"Locale:         {locale_label}\n"
            f"Timezone:       {timezone_label}\n"
            f"Username:       {username}\n"
            f"Auto-login:     {autologin}\n"
            f"Desktop stats:  {self.desktop_stats_combo.get_active_text()}\n"
            f"Wallpaper:      {self.wallpaper_combo.get_active_text()}\n"
        )
        self.stack.set_visible_child_name("apply")

    def _set_error(self, message):
        self.error_label.set_label(message)

    def _on_apply(self, *_):
        self.apply_btn.set_sensitive(False)
        self.back_btn.set_sensitive(False)
        self.apply_spinner_box.show()
        self.apply_spinner.start()

        data = {
            "username": self.username_entry.get_text().strip(),
            "full_name": self.fullname_entry.get_text().strip(),
            "password": self.password_entry.get_text(),
            "keymap": self.keymap_combo.get_active_id(),
            "locale": self.locale_combo.get_active_id(),
            "timezone": self.timezone_combo.get_active_id(),
            "autologin": self.autologin_switch.get_active(),
            "desktop_stats": self.desktop_stats_combo.get_active_id(),
            "wallpaper": self.wallpaper_combo.get_active_id(),
        }

        # Run the privileged apply in a worker thread so the GTK main loop
        # keeps spinning (the apply creates a user and recreates the Code
        # container — several seconds — which would otherwise freeze the UI).
        threading.Thread(target=self._run_apply, args=(data,), daemon=True).start()

    def _run_apply(self, data):
        config_dir = os.path.expanduser("~/.config/totaljs")
        os.makedirs(config_dir, exist_ok=True)
        json_path = os.path.join(config_dir, f"wizard-{secrets.token_hex(8)}.json")
        old_mask = os.umask(0o077)
        try:
            with open(json_path, "w") as f:
                json.dump(data, f)
        finally:
            os.umask(old_mask)

        try:
            subprocess.run(
                ["sudo", "-n", "/usr/bin/python3",
                 "/usr/local/sbin/totaljs-apply-firstrun.py", json_path],
                check=True, capture_output=True, text=True,
            )
            GLib.idle_add(self._apply_ok)
        except subprocess.CalledProcessError as exc:
            GLib.idle_add(self._apply_failed, (exc.stderr or "").strip()[:200])

    def _apply_ok(self):
        self.apply_spinner.stop()
        # Don't close — the apply scheduled a reboot in a few seconds. Switch to
        # the calm "restarting" screen with the spinning logo and leave it up
        # until the machine reboots into the new account.
        self.stack.set_visible_child_name("restarting")
        if hasattr(self, "_restart_spinner"):
            self._restart_spinner.show()
            self._restart_spinner.start()
        return False

    def _apply_failed(self, message):
        self.apply_spinner.stop()
        self.apply_status_label.set_label(f"Setup failed: {message}")
        self.apply_btn.set_sensitive(True)
        self.back_btn.set_sensitive(True)
        return False


def main():
    # Use GTK's dark variant so every widget (notably the combo boxes, whose
    # cell text is otherwise near-invisible) renders light-on-dark by default.
    # Our CSS below only layers the green accents on top.
    settings = Gtk.Settings.get_default()
    if settings is not None:
        settings.set_property("gtk-application-prefer-dark-theme", True)

    style_provider = Gtk.CssProvider()
    style_provider.load_from_data(CSS.encode())
    Gtk.StyleContext.add_provider_for_screen(
        Gdk.Screen.get_default(), style_provider, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION,
    )
    win = WizardWindow()
    win.connect("destroy", Gtk.main_quit)
    Gtk.main()


if __name__ == "__main__":
    main()
