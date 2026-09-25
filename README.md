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
- **System tray** — per-app hide, left-click to toggle a special workspace,
  per-app switch to launch it straight into that workspace, and **custom
  entries** to pin non-SNI apps (run a command or toggle a workspace).
- **Tools toolbar** — opt-in right-edge dock of **user-defined** tools: add your
  own buttons (name + command + icon from a picker) for anything you launch.
  Includes a built-in wallpaper / theme picker.
- **Lock screen** — session lock that survives shell hot-reload.
- **Settings app** (`SUPER+I`) — live, in-app configuration:
  - **Appearance modes**: frame / top-bar-only / floating islands, with live
    switching and matching panel styling.
  - **Theme designer**: built-in Material You themes plus create / duplicate /
    rename / delete / import / export of custom themes; optional
    `matugen` wallpaper-based generation.
  - **Wallpaper**: local + favorites + an online **Wallhaven browser** (search,
    sort, download); set, star favorites, and a timed **rotation** that
    re-themes on each change.
  - Configurable bar widgets, tray, tools, weather, and dependency overview.
  - **Keybindings**: assign Hyprland shortcuts for the shell's actions in-app
    (unbound by default; applied live via a generated Lua bind file).
  - **Hyprland**: arrange monitors on a **visual drag canvas** (reposition +
    edge-snap) and tune resolution / scale / rotation, plus
    appearance (gaps, borders, rounding, blur, shadow) and input (keyboard,
    mouse, layout) — all as an **override layer**: only what you change is written
    (to a generated Lua file); your own config is never touched. Display changes
    confirm-or-revert on a countdown. Requires the Lua config (like Keybindings).
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
| `matugen` + `hyprpaper` | Wallpaper switcher + Material You theme generation |
| `magick` (imagemagick) | Auto light/dark mode from wallpaper (else defaults dark) |
| `cava` | Audio visualizer |
| `brightnessctl` | Brightness control |
| `secret-tool` (libsecret) | Keyring for tokens (e.g. YT Music) |
| `qt6-websockets` (Qt module) | YouTube Music companion (realtime) |
| `khal` (+ `vdirsyncer`) | Calendar events (+ create/sync) |
| `nmcli` (networkmanager) | VPN section in the network panel |
| `wpctl` (wireplumber) | Bluetooth audio-profile switching (A2DP ↔ headset) |
| `curl` | Downloading wallpapers from the online (Wallhaven) browser |

The **network and Bluetooth panels are full in-shell managers** — no
nm-connection-editor or blueman needed. Wi-Fi (list, connect with password,
forget, radio toggle), Bluetooth (scan, pair, connect, trust, forget, rename,
battery) and battery alerts all use Quickshell's native
NetworkManager/BlueZ/UPower bindings and the shell's own notifications. Weather
and the YouTube Music companion use Qt's built-in HTTP client (no `curl`). Each
missing tool above just hides its feature; Settings → Dependencies shows what's
absent. For advanced Wi-Fi config (static IP, enterprise 802.1x, VPN editing)
use your preferred NetworkManager front-end.

The tools toolbar is **user-defined**: add your own buttons in Settings → Tools
(name + command + icon), so anything you'd launch — a file manager, screen
recorder, Docker UI — is your choice, not a bundled dependency. The wallpaper /
theme picker is the one built-in tool (uses `matugen`).

Media (play/pause/next, metadata) uses Quickshell's native MPRIS — no
`playerctl` needed. The optional YouTube Music companion talks to the
ytmdesktop server directly over a WebSocket — no Node. It needs the
`qt6-websockets` Qt module; without it the companion stays off and MPRIS is the
source of truth.
Screenshots, clipboard and idle-lock are **Hyprland-side**:
wire your own `hyprland.lua` binds (e.g. `grim`/`slurp`/`wl-copy`) and run an
idle daemon (e.g. `hypridle` calling `qs -p <shell dir> ipc call lock lock`) if
you want them.

## Install

**AUR** (Arch Linux) — installs to `/etc/xdg/quickshell/scottbass3-shell`:

```sh
yay -S scottbass3-shell-git
```

**Nix** (flake) — add the input and install the package:

```nix
inputs.scottbass3-shell.url = "github:scottbass3/shell";
# …
environment.systemPackages = [ inputs.scottbass3-shell.packages.${pkgs.stdenv.hostPlatform.system}.default ];
```

The package puts `quickshell` and the optional tools on the launcher's `PATH`;
the shell lives in `share/scottbass3-shell` of the package.

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

Add to the **end** of your `hyprland.lua`, for the AUR package:

```lua
loadfile("/etc/xdg/quickshell/scottbass3-shell/hypr/quickshell.lua")()
```

for Nix, with the package's store path (e.g. interpolated from home-manager):

```lua
loadfile("${scottbass3-shell}/share/scottbass3-shell/hypr/quickshell.lua")()
```

or for a git checkout:

```lua
loadfile(os.getenv("HOME") .. "/.config/quickshell/hypr/quickshell.lua")()
```

This sets `misc.allow_session_lock_restore`, autostarts the shell, binds the
per-monitor workspaces (`SUPER + 1..0`, Shift = move window), and sources the
generated shell-action binds plus the Settings → Hyprland override file — both
loaded last so they layer over your own config without overwriting it.

**Shell-action shortcuts** (app launcher, settings, lock, tools, scratchpad) are
**unbound by default**. Set them in **Settings → Keybindings** — each saved combo
is written to `~/.local/state/scottbass3-shell/binds.generated.lua` and applied
with `hyprctl reload`. Until
you bind anything, open the launcher from the bar button and Settings from the
dashboard gear icon.

In a git checkout, edit `hypr/quickshell.lua` to taste (the AUR copy is
replaced on every update — copy it elsewhere and `loadfile` your copy
instead). Apps that should open straight into a
special workspace are set in Settings → Tray → *Launch in special workspace*
(written to `hypr.generated.lua` as window rules, each one switchable).

## Running manually

```sh
scottbass3-shell &                 # AUR / Nix package
~/.config/quickshell/launch.sh &   # git checkout
```

`launch.sh` (installed as `/usr/bin/scottbass3-shell` by the package) only adds
the blobs plugin to `QML_IMPORT_PATH` and runs `quickshell` on its own config
directory.

## Configuration

Everything is configured live in-app — press **`SUPER + I`**. Appearance mode
(frame / top-bar / floating islands), theme designer (create / duplicate /
export / import), bar widgets, tray (per-app hide + special workspace + custom
non-SNI entries), tools, and weather.

All mutable state — settings, custom themes, pins, app-usage, generated binds —
lives **outside the checkout** under `~/.local/state/scottbass3-shell`
(`$XDG_STATE_HOME`). The repo stays read-only: pull updates without touching
your config.

## License

[GPLv3](LICENSE). The `Caelestia.Blobs` plugin under `blobs-plugin/` derives
from the [Caelestia](https://github.com/caelestia-dots) project.
