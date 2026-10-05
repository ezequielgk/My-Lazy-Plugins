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
- **+ Add Collection**: Press `A` or click the `+ Add Collection` button to open the interactive modal.
- **Controls**:
  - `←` / `→` (or `↑` / `↓`): Browse between collections.
  - `Enter`: Open the selected folder and browse its wallpapers.
  - `A`: Add a new collection (folder path, palette source type, and dynamic palette).
  - `Space`: Pick a random folder.
  - `Esc`: Close the panel.

#### Adding Collections (GUI Flow)
1. Press `A` or click `+ Add Collection` in Level 1.
2. Enter or paste the folder path (e.g. `~/Pictures/wallpapers/anime`).
3. Choose the **Palette Source** (`Built-in`, `Wallpaper dynamic`, `Custom`, or `Community`).
4. Select the **Palette**: dynamically populated based on what you actually have installed on your system.
5. Click **Add Collection** (or press `Enter`). The new collection is saved to `~/.config/noctalia/wallpaper-collections.json`.
6. You can add as many collections as you want sequentially!

> **Note**: To modify or remove existing collections, edit `~/.config/noctalia/wallpaper-collections.json`.

#### Level 2: Wallpapers Carousel
- **Spotlight Center Card**: Clean 3-card horizontal layout with direct image rendering.
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

- **`wallpaper_dir`**: Default base wallpaper directory.
- **`apply_palette`**: Automatically apply the assigned palette to Noctalia when choosing a wallpaper.
- **`notify_on_change`**: Send desktop notification when switching wallpaper, favorites, or adding collections.
- **`close_on_apply`**: Automatically close the carousel after applying a wallpaper.

> **Note**: Collections are managed directly in the widget GUI (+ button or `A` key) and persisted to `~/.config/noctalia/wallpaper-collections.json`. To modify or delete existing collections, edit that JSON file. Favorites are persisted in `~/.config/noctalia/wallpaper-widget-favorites.json`.

## License

MIT
