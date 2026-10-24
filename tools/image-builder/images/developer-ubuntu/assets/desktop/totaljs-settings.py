#!/usr/bin/env python3
"""Total Settings — a small control hub for the Total.js Developer desktop."""
import os
import pathlib
import pwd
import re
import shutil
import subprocess

import gi
gi.require_version("Gtk", "3.0")
gi.require_version("Gdk", "3.0")
from gi.repository import Gdk, GLib, Gtk


GREEN = "#6ac043"
BG = "#15181c"
PANEL = "#1c2126"
FG = "#e4e8eb"
MUTED = "#929ca4"

CSS = f"""
window {{ background-color: {BG}; }}
.title {{ color: {FG}; font-size: 24px; font-weight: bold; }}
.subtitle {{ color: {MUTED}; font-size: 12px; }}
.section {{ color: {GREEN}; font-size: 11px; font-weight: bold; }}
.tile {{ background-image: none; background-color: {PANEL}; border: 1px solid #303840; border-radius: 8px; box-shadow: none; padding: 12px; }}
.tile:hover {{ background-image: none; background-color: #252c32; border-color: #45515b; }}
.tile:disabled {{ opacity: .42; }}
.tile-title {{ color: {FG}; font-size: 13px; font-weight: bold; }}
.tile-subtitle {{ color: {MUTED}; font-size: 11px; }}
.setting-panel {{ background-color: {PANEL}; border: 1px solid #303840; border-radius: 8px; padding: 14px; }}
.setting-title {{ color: {FG}; font-size: 13px; font-weight: bold; }}
.setting-subtitle {{ color: {MUTED}; font-size: 11px; }}
combobox, combobox box, combobox button, combobox button.combo {{ background-image: none; background-color: #0f1316; color: {FG}; box-shadow: none; }}
combobox button, combobox button.combo {{ border: 1px solid #303840; border-radius: 6px; padding: 7px 10px; }}
combobox button:hover, combobox button:active {{ background-image: none; background-color: #252c32; border-color: #45515b; }}
combobox cellview, combobox arrow {{ color: {FG}; }}
entry {{ background-color: #0f1316; color: {FG}; border: 1px solid #303840; border-radius: 6px; padding: 7px; }}
entry:focus {{ border-color: {GREEN}; }}
/* ComboBox and EntryCompletion are separate popup windows. Arch's default
   theme otherwise paints them white while retaining our light text colour. */
menu, .menu, .background.menu {{ background-image: none; background-color: #0f1316; border: 1px solid #303840; box-shadow: none; }}
menu menuitem, menuitem {{ background-image: none; background-color: #0f1316; color: {FG}; padding: 6px 10px; }}
menu menuitem label, menuitem label, menu menuitem cellview, menuitem cellview {{ color: {FG}; }}
menuitem:hover, menuitem:selected, menuitem:active {{ background-image: none; background-color: #2c3a22; color: #ffffff; }}
menuitem:hover label, menuitem:selected label, menuitem:active label,
menuitem:hover cellview, menuitem:selected cellview, menuitem:active cellview {{ color: #ffffff; }}
treeview.view {{ background-color: #0f1316; color: {FG}; }}
treeview.view:selected, treeview.view:hover {{ background-color: #2c3a22; color: #ffffff; }}
switch {{ background-color: #303840; border-radius: 12px; }}
switch:checked {{ background-color: {GREEN}; }}
switch slider {{ background-color: #d7d9dc; border-radius: 11px; }}
button.apply {{ background-image: none; background-color: {GREEN}; color: #0f1316; border: 0; border-radius: 6px; box-shadow: none; font-weight: bold; padding: 7px 14px; }}
button.apply:hover {{ background-image: none; background-color: #7bd24d; }}
button.choice {{ background-image: none; background-color: #20272d; color: {FG}; border: 1px solid #303840; border-radius: 6px; box-shadow: none; text-shadow: none; padding: 7px 12px; }}
button.choice label {{ color: {FG}; text-shadow: none; }}
button.choice:hover {{ background-image: none; background-color: #2a3239; }}
button.choice.active {{ background-image: none; background-color: #2c3a22; color: #ffffff; border-color: {GREEN}; }}
button.choice.active label {{ color: #ffffff; }}
.status {{ color: {MUTED}; font-size: 11px; }}
"""


FALLBACK_KEYMAPS = [
    ("English (US)", "us"), ("English (UK)", "gb"), ("Español", "es"),
    ("Français", "fr"), ("Deutsch", "de"), ("Italiano", "it"),
    ("Português", "pt"), ("Português (Brasil)", "br"), ("Nederlands", "nl"),
]


def installed_keymaps():
    layouts = {}
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
                        fields = line.split(None, 1)
                        code = fields[0]
                        if re.fullmatch(r"[A-Za-z0-9_-]+", code):
                            layouts[code] = fields[1] if len(fields) > 1 else code
            if layouts:
                break
        except OSError:
            continue
    if not layouts:
        return FALLBACK_KEYMAPS
    return sorted(((label, code) for code, label in layouts.items()), key=lambda item: item[0].casefold())


def matching_item(items, query):
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


def searchable_combo(items, active_id=None):
    combo = Gtk.ComboBoxText.new_with_entry()
    combo.set_entry_text_column(0)
    for label, item_id in items:
        combo.append(item_id, label)
    # GtkComboBoxText uses cell renderers inside its detached popup. Explicit
    # renderer colours are the reliable fallback across Ubuntu and Arch themes.
    for cell in combo.get_cells():
        cell.set_property("foreground", FG)
        cell.set_property("foreground-set", True)
        cell.set_property("cell-background", "#0f1316")
        cell.set_property("cell-background-set", True)
    entry = combo.get_child()
    model = Gtk.ListStore(str, str)
    for label, item_id in items:
        model.append((label, item_id))
    completion = Gtk.EntryCompletion()
    completion.set_model(model)
    completion.set_text_column(0)
    completion.set_minimum_key_length(1)
    completion.set_popup_completion(True)
    completion.set_inline_selection(True)
    completion.set_match_func(
        lambda _completion, key, tree_iter, _data:
            key.casefold() in model[tree_iter][0].casefold()
            or key.casefold() in model[tree_iter][1].casefold(),
        None,
    )

    def select_match(_completion, selected_model, tree_iter):
        combo.set_active_id(selected_model[tree_iter][1])
        entry.set_position(-1)
        return True

    completion.connect("match-selected", select_match)
    entry.set_completion(completion)
    entry.connect(
        "activate",
        lambda _entry: combo.set_active_id(matching_item(items, entry.get_text())[1])
        if matching_item(items, entry.get_text()) else None,
    )
    if active_id:
        combo.set_active_id(active_id)
    return combo, entry


def current_keymap(valid_codes):
    try:
        result = subprocess.run(
            ["setxkbmap", "-query"], text=True, capture_output=True, check=False,
        )
        match = re.search(r"^layout:\s*([^,\s]+)", result.stdout, re.MULTILINE)
        if match and match.group(1) in valid_codes:
            return match.group(1)
    except OSError:
        pass
    return "us" if "us" in valid_codes else next(iter(valid_codes), None)


def autologin_enabled():
    username = pwd.getpwuid(os.getuid()).pw_name
    try:
        config = pathlib.Path("/etc/lightdm/lightdm.conf.d/50-totalvm.conf").read_text()
    except OSError:
        return False
    return re.search(rf"^autologin-user={re.escape(username)}$", config, re.MULTILINE) is not None


class SettingsWindow(Gtk.Window):
    def __init__(self):
        super().__init__(title="Total Settings")
        self.set_role("totaljs-settings")
        self.set_default_size(760, 680)
        self.set_position(Gtk.WindowPosition.CENTER)
        self.set_border_width(0)

        provider = Gtk.CssProvider()
        provider.load_from_data(CSS.encode())
        Gtk.StyleContext.add_provider_for_screen(
            Gdk.Screen.get_default(), provider, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION,
        )

        scroll = Gtk.ScrolledWindow()
        scroll.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
        self.add(scroll)
        content = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=14)
        content.set_margin_top(24)
        content.set_margin_bottom(24)
        content.set_margin_start(28)
        content.set_margin_end(28)
        scroll.add(content)

        title = Gtk.Label(label="Total Settings", xalign=0)
        title.get_style_context().add_class("title")
        content.pack_start(title, False, False, 0)
        subtitle = Gtk.Label(
            label="Everything needed to shape and maintain your Total.js Developer desktop.",
            xalign=0,
        )
        subtitle.get_style_context().add_class("subtitle")
        content.pack_start(subtitle, False, False, 2)

        self._section(content, "SYSTEM")
        system = self._tile_grid()
        content.pack_start(system, False, False, 0)
        self._add_tile(system, 0, 0, "Network", "Connections and network profiles",
                       "network-wired", ["nm-connection-editor"])
        self._add_tile(system, 1, 0, "Sound", "Input, output and application volume",
                       "multimedia-volume-control", ["pavucontrol"])
        self._add_tile(system, 0, 1, "Regional", "Time zone and regional formats",
                       "preferences-desktop-locale", ["/usr/local/bin/totaljs-region"])
        self._add_tile(system, 1, 1, "Total.js Center", "Services, addresses and environment",
                       "/usr/local/share/icons/totaljs-panel.svg",
                       ["totaljs-open", "http://totaljs.developer"])
        self._add_tile(system, 0, 2, "System Monitor", "Processes and resource usage",
                       "utilities-system-monitor", ["alacritty", "-e", "htop"])

        self._section(content, "LOGIN & INPUT")
        content.pack_start(self._login_input_panel(), False, False, 0)

        self._section(content, "APPEARANCE")
        appearance = self._tile_grid()
        content.pack_start(appearance, False, False, 0)
        self._add_tile(appearance, 0, 0, "Appearance", "Theme, icons, fonts and cursor",
                       "preferences-desktop-theme", ["lxappearance"])
        self._add_tile(appearance, 1, 0, "Window Borders", "Window theme and behaviour",
                       "preferences-system-windows", ["/usr/local/bin/totaljs-window-borders"])
        self._add_tile(appearance, 0, 1, "Panel", "Top bar and dock appearance",
                       "tint2conf",
                       ["/usr/local/bin/totaljs-panel-settings"])

        self._section(content, "WALLPAPER")
        content.pack_start(self._choice_row([
            ("Next", ["totaljs-wallpaper", "next"]),
            ("Pin Current", ["totaljs-wallpaper", "pin"]),
            ("Shuffle", ["totaljs-wallpaper", "shuffle"]),
            ("Total.js Signature", ["totaljs-wallpaper", "signature"]),
        ]), False, False, 0)

        self._section(content, "DESKTOP STATS")
        profile = self._conky_profile()
        content.pack_start(self._choice_row([
            ("System", ["totaljs-conky", "system"], "system"),
            ("Compact", ["totaljs-conky", "compact"], "compact"),
            ("Services", ["totaljs-conky", "services"], "services"),
            ("Hidden", ["totaljs-conky", "hidden"], "hidden"),
        ], active=profile), False, False, 0)

        self.status = Gtk.Label(label="", xalign=0)
        self.status.get_style_context().add_class("status")
        content.pack_start(self.status, False, False, 2)

    @staticmethod
    def _section(parent, text):
        label = Gtk.Label(label=text, xalign=0)
        label.get_style_context().add_class("section")
        label.set_margin_top(8)
        parent.pack_start(label, False, False, 0)

    @staticmethod
    def _tile_grid():
        return Gtk.Grid(column_spacing=12, row_spacing=12, column_homogeneous=True)

    def _login_input_panel(self):
        panel = Gtk.Grid(column_spacing=14, row_spacing=14)
        panel.get_style_context().add_class("setting-panel")

        keyboard_labels = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=3)
        keyboard_title = Gtk.Label(label="Keyboard layout", xalign=0)
        keyboard_title.get_style_context().add_class("setting-title")
        keyboard_subtitle = Gtk.Label(label="Used by the desktop and terminal", xalign=0)
        keyboard_subtitle.get_style_context().add_class("setting-subtitle")
        keyboard_labels.pack_start(keyboard_title, False, False, 0)
        keyboard_labels.pack_start(keyboard_subtitle, False, False, 0)
        panel.attach(keyboard_labels, 0, 0, 1, 1)

        self.keymap_items = installed_keymaps()
        valid_codes = {code for _, code in self.keymap_items}
        self.keymap, self.keymap_search = searchable_combo(
            self.keymap_items, current_keymap(valid_codes),
        )
        self.keymap.set_hexpand(True)
        panel.attach(self.keymap, 1, 0, 1, 1)
        apply_keyboard = Gtk.Button(label="Apply")
        apply_keyboard.get_style_context().add_class("apply")
        apply_keyboard.connect("clicked", self._apply_keyboard)
        panel.attach(apply_keyboard, 2, 0, 1, 1)

        login_labels = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=3)
        login_title = Gtk.Label(label="Log in automatically at startup", xalign=0)
        login_title.get_style_context().add_class("setting-title")
        login_subtitle = Gtk.Label(label="Turn off to ask for your password at boot", xalign=0)
        login_subtitle.get_style_context().add_class("setting-subtitle")
        login_labels.pack_start(login_title, False, False, 0)
        login_labels.pack_start(login_subtitle, False, False, 0)
        panel.attach(login_labels, 0, 1, 2, 1)

        self.autologin = Gtk.Switch()
        self.autologin.set_active(autologin_enabled())
        self.autologin.set_halign(Gtk.Align.END)
        self.autologin.set_valign(Gtk.Align.CENTER)
        self.autologin.connect("state-set", self._set_autologin)
        panel.attach(self.autologin, 2, 1, 1, 1)
        return panel

    def _add_tile(self, grid, column, row, title, subtitle, icon, command):
        button = Gtk.Button()
        button.set_relief(Gtk.ReliefStyle.NONE)
        button.get_style_context().add_class("tile")
        button.set_hexpand(True)
        button.set_size_request(-1, 78)
        box = Gtk.Box(spacing=12)
        if icon.startswith("/") and pathlib.Path(icon).is_file():
            image = Gtk.Image.new_from_file(icon)
        else:
            image = Gtk.Image.new_from_icon_name(icon, Gtk.IconSize.DIALOG)
        box.pack_start(image, False, False, 0)
        labels = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=3)
        labels.set_valign(Gtk.Align.CENTER)
        heading = Gtk.Label(label=title, xalign=0)
        heading.get_style_context().add_class("tile-title")
        detail = Gtk.Label(label=subtitle, xalign=0)
        detail.get_style_context().add_class("tile-subtitle")
        detail.set_line_wrap(True)
        labels.pack_start(heading, False, False, 0)
        labels.pack_start(detail, False, False, 0)
        box.pack_start(labels, True, True, 0)
        button.add(box)
        executable = command[0]
        available = pathlib.Path(executable).is_file() if executable.startswith("/") else shutil.which(executable)
        button.set_sensitive(bool(available))
        if not available:
            button.set_tooltip_text(f"{title} is unavailable in this installation")
        button.connect("clicked", lambda _button: self._launch(command, title))
        grid.attach(button, column, row, 1, 1)

    def _choice_row(self, choices, active=None):
        row = Gtk.Box(spacing=8)
        buttons = []
        for choice in choices:
            label, command = choice[:2]
            choice_id = choice[2] if len(choice) > 2 else None
            button = Gtk.Button(label=label)
            button.get_style_context().add_class("choice")
            if choice_id == active:
                button.get_style_context().add_class("active")
            button.connect("clicked", self._run_choice, command, label, buttons, choice_id)
            buttons.append(button)
            row.pack_start(button, False, False, 0)
        return row

    def _run_choice(self, button, command, label, siblings, choice_id):
        result = subprocess.run(command, text=True, capture_output=True, check=False)
        if result.returncode:
            self._error(label, result.stderr.strip() or "The setting could not be applied.")
            return
        if choice_id:
            for sibling in siblings:
                sibling.get_style_context().remove_class("active")
            button.get_style_context().add_class("active")
        self.status.set_text(f"{label} applied")
        GLib.timeout_add_seconds(3, self._clear_status)

    @staticmethod
    def _system_setting(operation, value):
        try:
            return subprocess.run(
                ["pkexec", "/usr/local/libexec/totaljs-system-settings", operation, value],
                text=True, capture_output=True, check=False,
            )
        except OSError as error:
            return subprocess.CompletedProcess([], 1, "", str(error))

    def _apply_keyboard(self, _button):
        if self.keymap.get_active_id() is None:
            match = matching_item(self.keymap_items, self.keymap_search.get_text())
            if match:
                self.keymap.set_active_id(match[1])
        layout = self.keymap.get_active_id()
        if not layout:
            self._setting_error("Keyboard layout", "Choose a layout from the list.")
            return
        result = self._system_setting("keyboard", layout)
        if result.returncode:
            self._setting_error(
                "Keyboard layout", result.stderr.strip() or "The keyboard layout was not changed.",
            )
            return
        subprocess.run(["setxkbmap", layout], check=False)
        self.status.set_text("Keyboard layout applied")
        GLib.timeout_add_seconds(3, self._clear_status)

    def _set_autologin(self, _switch, enabled):
        result = self._system_setting("autologin", "on" if enabled else "off")
        if result.returncode:
            if result.returncode in (126, 127):
                self.status.set_text("Automatic login was not changed")
                GLib.timeout_add_seconds(3, self._clear_status)
            else:
                self._setting_error(
                    "Automatic login", result.stderr.strip() or "The login setting was not changed.",
                )
            return True
        self.status.set_text("Automatic login enabled" if enabled else "Password login enabled")
        GLib.timeout_add_seconds(3, self._clear_status)
        return False

    def _launch(self, command, title):
        try:
            subprocess.Popen(command, start_new_session=True)
            self.status.set_text(f"Opened {title}")
            GLib.timeout_add_seconds(3, self._clear_status)
        except OSError as error:
            self._error(title, str(error))

    def _error(self, title, message):
        dialog = Gtk.MessageDialog(
            transient_for=self, message_type=Gtk.MessageType.ERROR,
            buttons=Gtk.ButtonsType.OK, text=f"Could not open {title}",
        )
        dialog.format_secondary_text(message)
        dialog.run()
        dialog.destroy()

    def _setting_error(self, title, message):
        dialog = Gtk.MessageDialog(
            transient_for=self, message_type=Gtk.MessageType.ERROR,
            buttons=Gtk.ButtonsType.OK, text=f"Could not change {title}",
        )
        dialog.format_secondary_text(message)
        dialog.run()
        dialog.destroy()

    def _clear_status(self):
        self.status.set_text("")
        return False

    @staticmethod
    def _conky_profile():
        try:
            return (pathlib.Path.home() / ".config/totaljs/conky-profile").read_text().strip()
        except OSError:
            return "system"


if __name__ == "__main__":
    window = SettingsWindow()
    window.connect("destroy", Gtk.main_quit)
    window.show_all()
    Gtk.main()
