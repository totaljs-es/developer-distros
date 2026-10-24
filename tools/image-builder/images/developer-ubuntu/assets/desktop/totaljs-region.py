#!/usr/bin/env python3
"""Small regional settings panel that never changes the desktop language."""
import os
import pathlib
import subprocess

import gi
gi.require_version("Gtk", "3.0")
from gi.repository import Gtk


FALLBACK_FORMATS = (
    "C.UTF-8",
    "en_US.UTF-8",
)

REGION_VARIABLES = (
    "LC_TIME", "LC_NUMERIC", "LC_MONETARY", "LC_MEASUREMENT", "LC_PAPER",
)
REGION_FILE = pathlib.Path.home() / ".config" / "environment.d" / "90-totaljs-region.conf"


def installed_locales():
    """Map normalized locale names to the exact names accepted by libc."""
    try:
        result = subprocess.run(
            ["locale", "-a"], text=True, capture_output=True, check=False,
        )
        values = [value.strip() for value in result.stdout.splitlines() if value.strip()]
    except OSError:
        values = []
    if not values:
        values = list(FALLBACK_FORMATS)
    return {
        value.lower().replace("utf-8", "utf8"): value
        for value in values
    }


SYSTEM_LOCALES = installed_locales()


def canonical_locale(locale):
    normalized = locale.lower().replace("utf-8", "utf8")
    return SYSTEM_LOCALES.get(normalized)


def locale_label(locale):
    """Present the libc locale name with consistent UTF-8 spelling."""
    return locale.replace(".utf8", ".UTF-8").replace(".UTF8", ".UTF-8")


FORMAT_ITEMS = sorted(
    ((locale_label(locale), locale) for locale in SYSTEM_LOCALES.values()),
    key=lambda item: item[0].casefold(),
)


def default_format():
    return (
        canonical_locale("en_US.UTF-8")
        or canonical_locale("C.UTF-8")
        or FORMAT_ITEMS[0][1]
    )


def saved_format():
    """Return the persisted choice, including during the current login."""
    try:
        for line in REGION_FILE.read_text(encoding="utf-8").splitlines():
            name, separator, value = line.partition("=")
            if separator and name in REGION_VARIABLES and canonical_locale(value):
                return value
    except OSError:
        pass
    for name in REGION_VARIABLES:
        value = os.environ.get(name)
        if value and canonical_locale(value):
            return value
    return default_format()


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
    entry.connect("activate", lambda _entry: select_typed())

    def select_typed():
        match = matching_item(items, entry.get_text())
        if match:
            combo.set_active_id(match[1])

    if active_id is not None:
        combo.set_active_id(active_id)
    return combo, entry


class RegionWindow(Gtk.Window):
    def __init__(self):
        super().__init__(title="Regional Settings")
        self.set_role("totaljs-region")
        self.set_default_size(520, 250)
        self.set_border_width(24)

        grid = Gtk.Grid(column_spacing=18, row_spacing=16)
        self.add(grid)
        title = Gtk.Label()
        title.set_markup("<span size='x-large' weight='bold'>Regional Settings</span>")
        title.set_halign(Gtk.Align.START)
        grid.attach(title, 0, 0, 2, 1)

        subtitle = Gtk.Label(label="Adjust time zone and number/date formats without changing the interface language.")
        subtitle.set_halign(Gtk.Align.START)
        subtitle.set_line_wrap(True)
        grid.attach(subtitle, 0, 1, 2, 1)

        zones = subprocess.check_output(["timedatectl", "list-timezones"], text=True).splitlines()
        current_zone = subprocess.check_output(["timedatectl", "show", "-p", "Timezone", "--value"], text=True).strip()
        zone_items = [(zone, zone) for zone in zones]
        self.timezone, self.timezone_search = make_searchable_combo(zone_items, current_zone)
        self.zone_items = zone_items
        grid.attach(Gtk.Label(label="Time zone", xalign=0), 0, 2, 1, 1)
        grid.attach(self.timezone, 1, 2, 1, 1)

        current_format = canonical_locale(saved_format()) or default_format()
        format_items = FORMAT_ITEMS
        self.formats, self.formats_search = make_searchable_combo(
            format_items,
            current_format,
        )
        self.format_items = format_items
        grid.attach(Gtk.Label(label="Formats", xalign=0), 0, 3, 1, 1)
        grid.attach(self.formats, 1, 3, 1, 1)

        button = Gtk.Button(label="Apply")
        button.get_style_context().add_class("suggested-action")
        button.connect("clicked", self.apply)
        button.set_halign(Gtk.Align.END)
        grid.attach(button, 1, 4, 1, 1)

    def apply(self, _button):
        if self.timezone.get_active_id() is None:
            match = matching_item(self.zone_items, self.timezone_search.get_text())
            if match:
                self.timezone.set_active_id(match[1])
        if self.formats.get_active_id() is None:
            match = matching_item(self.format_items, self.formats_search.get_text())
            if match:
                self.formats.set_active_id(match[1])
        zone = self.timezone.get_active_id()
        locale = self.formats.get_active_id()
        errors = []
        if not zone:
            errors.append("Choose a time zone from the list.")
        else:
            result = subprocess.run(
                ["timedatectl", "set-timezone", zone],
                text=True, capture_output=True, check=False,
            )
            if result.returncode:
                errors.append(result.stderr.strip() or "The time zone could not be changed.")
        if not locale:
            errors.append("Choose a regional format from the list.")
        else:
            if not canonical_locale(locale):
                errors.append("The selected regional format is not installed.")
                locale = None
        if locale:
            REGION_FILE.parent.mkdir(parents=True, exist_ok=True)
            with REGION_FILE.open("w", encoding="utf-8") as config:
                for name in REGION_VARIABLES:
                    config.write(f"{name}={locale}\n")
            profile = os.path.expanduser("~/.profile")
            begin, end = "# Total.js regional formats", "# End Total.js regional formats"
            try:
                with open(profile, encoding="utf-8") as source:
                    content = source.read()
            except FileNotFoundError:
                content = ""
            managed = begin + "\n" + "\n".join(
                f"export {name}={locale}"
                for name in REGION_VARIABLES
            ) + "\n" + end
            import re
            pattern = re.compile(re.escape(begin) + r".*?" + re.escape(end), re.DOTALL)
            content = pattern.sub(managed, content) if pattern.search(content) else content.rstrip() + "\n\n" + managed + "\n"
            with open(profile, "w", encoding="utf-8") as destination:
                destination.write(content)
        message_type = Gtk.MessageType.ERROR if errors else Gtk.MessageType.INFO
        title = "Regional settings could not be saved" if errors else "Regional settings saved"
        dialog = Gtk.MessageDialog(transient_for=self, flags=0, message_type=message_type,
                                   buttons=Gtk.ButtonsType.OK, text=title)
        if errors:
            dialog.format_secondary_text("\n".join(errors))
        else:
            dialog.format_secondary_text("The time zone changes now. Format changes apply at your next login.")
        dialog.run()
        dialog.destroy()


if __name__ == "__main__":
    window = RegionWindow()
    window.connect("destroy", Gtk.main_quit)
    window.show_all()
    Gtk.main()
