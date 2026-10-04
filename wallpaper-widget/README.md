# Wallpaper Widget

A cinematic horizontal wallpaper switcher carousel and interactive bar widget for Noctalia with automatic palette synchronization and folder collections.

## Plugin

| Field | Value |
| --- | --- |
| ID | `ashur-d/wallpaper-widget` |
| Entries | Panel: `hub`; bar widget: `widget`; shortcut: `toggle` |

## Usage

Wallpaper Widget provides convenient ways to browse collections, switch wallpapers, and automatically adapt your Noctalia color palette:

### Visual 2-Level Carousel Panel

Open the floating carousel panel directly or bind it to a custom compositor keybind:

```sh
noctalia msg panel-toggle ashur-d/wallpaper-widget:hub
```

#### Level 1: Folder / Palette Collections Carousel
- **Cover Previews**: Displays your wallpaper folders (e.g. *Nord*, *Gruvbox*, *Tokyo Night*, *Nature*) with a thumbnail cover card and the assigned palette badge.
- **Palette Mapping**: Automatically pairs folder names with matching Noctalia palettes (*built-in*, *custom*, *community*, or dynamic *wallpaper*).
- **Navigation**:
  - `←` / `→` (or `↑` / `↓`): Browse between folders.
  - `Enter`: Open the selected folder and view its wallpapers.
  - `P`: Cycle/change the assigned palette for the highlighted folder.
  - `Space`: Pick a random folder.
  - `Esc`: Close the panel.

#### Level 2: Wallpapers Carousel
- **Cinematic Focus**: Spotlight center card with adjacent previews.
- **Active Indicator**: Highlights the currently active desktop wallpaper with an accent border.
- **Auto-Palette Switch**: Applying a wallpaper also switches Noctalia's color scheme to match the collection's palette.
- **Navigation**:
  - `←` / `→` (or `↑` / `↓`): Browse wallpapers.
  - `Enter`: Apply the selected wallpaper and its assigned color palette.
  - `Del` / `Backspace`: Return back to the Collections view.
  - `Space`: Apply a random wallpaper from this folder.
  - `Esc`: Close the panel.

### Bar Widget

Add the `widget` entry to your Noctalia bar:
- **Left click**: Toggles the Wallpaper Widget carousel panel.
- **Right click**: Immediately picks and applies a random wallpaper.
- **Scroll wheel up / down**: Cycles to the next or previous wallpaper.
- **Tooltip**: Displays the currently active wallpaper filename and control tips.

### Performance & Background Thumbnail Caching

Wallpaper Widget automatically generates and caches downscaled 512x288 thumbnails in `~/.cache/noctalia/wallpaper-widget/thumbnails/` for buttery-smooth 60 FPS carousel navigation:
- **Low-Priority Background Processing**: Runs thumbnail jobs in the background with `nice -n 19` so your desktop compositor and user input never hitch.
- **Auto-Detection**: Automatically detects `magick` (ImageMagick 7), `convert` (ImageMagick 6), or `ffmpeg`.
- **Graceful Fallback**: If none of these image utilities are installed, Wallpaper Widget falls back to original wallpaper files with zero required dependencies.

## Settings

Configure Wallpaper Widget in **Settings -> Plugins -> Wallpaper Widget**:

| Setting | Type | Default | Description |
| --- | --- | --- | --- |
| `wallpaper_dir` | `folder` | *(empty)* | Path to your wallpapers directory containing theme/palette subfolders. |
| `apply_palette` | `bool` | `true` | Automatically switch Noctalia's color palette when applying a wallpaper. |
| `default_palette_source` | `select` | `auto` | Fallback mode (`auto`, `wallpaper`, `none`) for folders without an explicit palette. |
| `notify_on_change` | `bool` | `true` | Send a desktop notification whenever wallpaper or palette is switched. |
| `close_on_apply` | `bool` | `false` | Automatically close the carousel after applying a wallpaper. |

## License

MIT
