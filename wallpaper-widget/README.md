# Wallpaper Widget

A cinematic horizontal wallpaper switcher carousel and interactive bar widget for Noctalia with automatic palette synchronization and custom folder slots.

## Plugin

| Field | Value |
| --- | --- |
| ID | `ezequielgk/wallpaper-widget` |
| Author | `ezequielgk` |
| Entries | Panel: `hub`; bar widget: `widget`; shortcut: `toggle` |

## Usage

### Visual 2-Level Carousel Panel

```sh
noctalia msg panel-toggle ezequielgk/wallpaper-widget:hub
```

#### Level 1: Folder / Palette Collections Carousel
- **Aesthetic**: Follows native Noctalia UI guidelines with clean borders matching your desktop theme.
- **Preview**: Cards spotlight each collection cover with its assigned palette badge underneath.
- **Controls**:
  - `←` / `→` (or `↑` / `↓`): Browse between collections.
  - `Enter`: Open the selected folder and browse its wallpapers.
  - `Space`: Pick a random folder.
  - `Esc`: Close the panel.

#### Level 2: Wallpapers Carousel
- **Original Layout**: Clean 3-card horizontal carousel.
- **Active Indicator**: Highlights the currently active wallpaper with the primary border.
- **Auto-Palette Switch**: Applying a wallpaper automatically applies the folder's configured palette in Noctalia.
- **Controls**:
  - `←` / `→` (or `↑` / `↓`): Browse wallpapers.
  - `Enter`: Apply the selected wallpaper and its assigned palette.
  - `Del` / `Backspace`: Return back to the Collections view.
  - `Space`: Apply a random wallpaper from this folder.
  - `Esc`: Close the panel.

### Bar Widget

- **Left click**: Toggles the Wallpaper Widget carousel panel.
- **Right click**: Immediately picks and applies a random wallpaper.
- **Scroll wheel up / down**: Cycles to the next or previous wallpaper.
- **Tooltip**: Displays current wallpaper and quick actions.

## Configuration (Settings -> Plugins -> Wallpaper Widget)

All collections and palette mappings are configured entirely in Noctalia's plugin settings:

- **`wallpaper_dir`**: Default base wallpaper directory (used as fallback if no custom slots are configured).
- **`apply_palette`**: Automatically apply the assigned palette to Noctalia when choosing a wallpaper.
- **`notify_on_change`**: Send desktop notification when switching wallpaper.
- **`close_on_apply`**: Automatically close the carousel after applying a wallpaper.
- **Slots 1 to 8**:
  - **Folder**: Path to the wallpaper folder for this slot.
  - **Palette Type**: Select `Built-in`, `Wallpaper (Dynamic)`, `Community`, or `Custom`.
  - **Palette Name**: The exact name of the palette (e.g. `Nord`, `Gruvbox`, `Dim`, `soft`). Leave empty to automatically use the folder's name.

## License

MIT
