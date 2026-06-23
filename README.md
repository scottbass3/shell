# Quickshell Desktop Shell

A Material-You desktop shell for **Hyprland**, built with
[Quickshell](https://quickshell.outfoxxed.me). Top bar, app launcher
(Windows-11-style start menu), notification center, media controls, a tools
toolbar, a lock screen, and a built-in settings app with a theme designer — all
in QML, with liquid SDF panel corners that merge into a rounded screen frame.

> ⚠️ **Hyprland Lua config required.** Integration uses the `hl.*` Lua API
> (special-workspace toggles, focus dispatch, window moves). If you run the
> classic hyprlang (`.conf`) config you'll need to port `hypr/quickshell.lua`
> and `scripts/hypr/*.sh` yourself.

## Features

- **Top bar** — per-monitor workspaces (live window thumbnails on hover),
  clock, window title, system tray, and an opt-in status group
  (network, Bluetooth, microphone, audio, battery), notifications and power.
- **App launcher** — Windows-11-style start menu: type-anywhere fuzzy search,
  full 2D arrow-key grid navigation, pinned apps with drag-to-reorder,
  frecency-ranked recommendations, and right-click context menus. Deploys from
  the bottom of the screen.
- **Notification center** — popup toasts + a history panel; click a
  notification to focus/launch its app (revealing its special workspace if
  parked there). Do-not-disturb toggle.
- **Dashboard** — quick-settings popout with media controls (MPRIS + a realtime
  YouTube Music companion, with two-way auto-pause between players), audio
  visualizer, weather, and a settings shortcut.
- **System tray** — per-app hide, left-click to toggle a special workspace, and
  **custom entries** to pin non-SNI apps (run a command or toggle a workspace).
- **Tools toolbar** — opt-in dock of utilities (file explorer, Docker explorer,
  screen recorder, …), each individually toggleable and dependency-checked.
- **Lock screen** — session lock that survives shell hot-reload.
- **Settings app** (`SUPER+I`) — live, in-app configuration:
  - **Appearance modes**: frame / top-bar-only / floating islands, with live
    switching and matching panel styling.
  - **Theme designer**: built-in Material You themes plus create / duplicate /
    rename / delete / import / export of custom themes; optional
    `matugen` wallpaper-based generation.
  - Configurable bar widgets, tray, tools, weather, and dependency overview.
  - **Keybindings**: assign Hyprland shortcuts for the shell's actions in-app
    (unbound by default; applied live via a generated Lua bind file).
- **Liquid panel corners** — panels are SDF metaballs that smooth-merge into a
  rounded screen frame as they deploy.
- **Per-monitor workspaces** — every screen gets its own 1–10 range, with
  Super+N switch / Super+Shift+N move.

## Requirements

| | |
|---|---|
| **Compositor** | Hyprland 0.55+ with the **Lua** config system |
| **Shell** | [`quickshell`](https://quickshell.outfoxxed.me) (git/0.3.x) |
| **Build** | `cmake`, `make`, a C++20 compiler, **Qt 6.8+** (Core, Qml, Quick, ShaderTools) |
| **VCS** | `git` |

### Optional runtime dependencies

Each lights up a feature; the shell runs without them and Settings →
Dependencies shows what's missing.

| Tool | Enables |
|---|---|
| `matugen` | Wallpaper → Material You theme generation |
| `cava` | Audio visualizer |
| `node` + `npm` | YouTube Music companion (realtime track + controls) |
| `playerctl` | Extra MPRIS controls |
| `brightnessctl` | Brightness control |
| `grim`, `slurp`, `wl-copy` | Screenshots / region copy |
| `wf-recorder` | Screen recording |
| `hypridle` | Idle → lock |
| `secret-tool` (libsecret) | Keyring for tokens (e.g. YT Music) |
| `jq` | Workspace / window helper scripts |
| `superfile`, `beacon` | File / Docker explorer tools |

## Install

**One-liner** (clones to `~/.config/quickshell`, builds the plugin):

```sh
curl -fsSL https://raw.githubusercontent.com/scottbass3/shell/main/install.sh | bash
```

**Manual:**

```sh
git clone https://github.com/scottbass3/shell ~/.config/quickshell
cd ~/.config/quickshell
./install.sh
```

`install.sh` builds the bundled `Caelestia.Blobs` Qt plugin into
`./Caelestia/Blobs` (found via `launch.sh`'s `QML_IMPORT_PATH`), installs the
optional YouTube Music bridge deps, and prints the Hyprland steps.

## Hyprland integration

Add to the **end** of your `hyprland.lua`:

```lua
loadfile(os.getenv("HOME") .. "/.config/quickshell/hypr/quickshell.lua")()
```

This sets `misc.allow_session_lock_restore`, autostarts the shell, binds the
per-monitor workspaces (`SUPER + 1..0`, Shift = move window), and sources the
generated shell-action binds.

**Shell-action shortcuts** (app launcher, settings, lock, tools, scratchpad) are
**unbound by default**. Set them in **Settings → Keybindings** — each saved combo
is written to `hypr/binds.generated.lua` and applied with `hyprctl reload`. Until
you bind anything, open the launcher from the bar button and Settings from the
dashboard gear icon.

Edit `hypr/quickshell.lua` to taste — the special-workspace window rules at the
bottom are commented examples; match them to your apps and to Settings → Tray.

## Running manually

```sh
~/.config/quickshell/launch.sh &
```

`launch.sh` only adds the config dir to `QML_IMPORT_PATH` (so the blobs plugin
resolves) and execs `quickshell`.

## Configuration

Everything is configured live in-app — press **`SUPER + I`**. Appearance mode
(frame / top-bar / floating islands), theme designer (create / duplicate /
export / import), bar widgets, tray (per-app hide + special workspace + custom
non-SNI entries), tools, and weather.

All mutable state — settings, custom themes, pins, app-usage, generated binds —
lives **outside the checkout** under `~/.local/state/quickshell`
(`$XDG_STATE_HOME`). The repo stays read-only: pull updates without touching
your config.

## License

[GPLv3](LICENSE). The `Caelestia.Blobs` plugin under `blobs-plugin/` derives
from the [Caelestia](https://github.com/caelestia-dots) project.
