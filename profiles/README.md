# Profiles

Save, load and switch between Noctalia config profiles.

| Field | Value |
|-------|-------|
| ID | `ezequielgk/profiles` |
| Entry (Widget) | `ezequielgk/profiles:switcher` |
| Entry (Shortcut) | `ezequielgk/profiles:switcher` |
| Entry (Panel) | `ezequielgk/profiles:manager` |

## Usage

- Add the bar widget from the Add-widget picker (`ezequielgk/profiles:switcher`).
- Add the control center tile from Settings → Control Center → Shortcuts.
- Open the panel with `noctalia msg panel-toggle ezequielgk/profiles:manager` or right-click the widget.

## Notes

- Profiles are stored in the plugin's data directory. 
- A backup of the current `settings.toml` is written before each load.
- Changes apply instantly by calling `noctalia msg config-reload`.
