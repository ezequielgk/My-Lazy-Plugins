# Wallpaper Widget

A cinematic horizontal wallpaper switcher carousel and interactive bar widget for Noctalia with automatic palette synchronization, collections, and favorites.

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

#### Level 1: Folder Collections Carousel
- **Adaptive Aesthetic**: Automatically follows each user's Noctalia shell geometry and styling (`shell.corner_radius_scale`).
- **Preview**: Cards spotlight each collection cover with its assigned palette badge underneath.
- **★ Favorites Folder**: If you have wallpapers marked as favorites, a dedicated collection appears first in the list.
- **Controls**:
  - `←` / `→` (or `↑` / `↓`): Browse between collections.
  - `Enter`: Open the selected folder and browse its wallpapers.
  - `Space`: Pick a random folder.
  - `Esc`: Close the panel.

#### Level 2: Wallpapers Carousel
- **Original Clean Carousel**: Clean 3-card horizontal layout with direct image rendering.
- **Active Indicator**: Highlights the currently active wallpaper with the primary border and an `ACTIVE` badge.
- **Favorite Badge & Toggle**: A clean badge located in the info section below the spotlight card (`star` outline when not favorited, `star-filled` with primary accent when favorited).
- **Auto-Palette Switch**: Applying a wallpaper automatically applies the folder's configured palette in Noctalia.
- **Controls**:
  - `←` / `→` (or `↑` / `↓`): Browse wallpapers.
  - `Enter`: Apply the selected wallpaper and its assigned palette.
  - `F` (or click on the favorite badge): Toggle favorite status.
  - `Del` / `Backspace`: Return back to the Collections view.
  - `Space`: Apply a random wallpaper from this folder.
  - `Esc`: Close the panel.

### Bar Widget

- **Left click**: Toggles the Wallpaper Widget carousel panel.
- **Right click**: Immediately picks and applies a random wallpaper.
- **Scroll wheel up / down**: Cycles to the next or previous wallpaper.
- **Tooltip**: Displays current wallpaper and quick actions.

## Configuration (Settings -> Plugins -> Wallpaper Widget)

All settings in Noctalia's plugin menu are clean and global:

- **`wallpaper_dir`**: Default base wallpaper directory (automatically scans subfolders).
- **`apply_palette`**: Automatically apply the assigned palette to Noctalia when choosing a wallpaper.
- **`notify_on_change`**: Send desktop notification when switching wallpaper or modifying favorites.
- **`close_on_apply`**: Automatically close the carousel after applying a wallpaper.

### Custom Collections File (Optional)

To define explicit collections, you can place a file at `~/.config/noctalia/wallpaper-collections.json`:

```json
[
  {
    "name": "Nord",
    "path": "~/Imágenes/Wallpapers/Nord",
    "palette_type": "builtin",
    "palette": "Nord"
  },
  {
    "name": "Slatemist",
    "path": "~/Imágenes/Wallpapers/bjork/Slatemist/dark",
    "palette_type": "custom",
    "palette": "Dim"
  }
]
```

Favorites are automatically persisted in `~/.config/noctalia/wallpaper-widget-favorites.json`.

## License

MIT
