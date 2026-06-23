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

This sets `misc.allow_session_lock_restore`, autostarts the shell, and binds:

| Key | Action |
|---|---|
| `SUPER + R` | App launcher |
| `SUPER + I` | Settings |
| `SUPER + L` | Lock screen |
| `SUPER + E` | Tools toolbar |
| `SUPER + S` | Toggle scratchpad / special workspace |
| `SUPER + 1..0` | Per-monitor workspace switch (Shift = move window) |

Edit it to taste — the special-workspace window rules at the bottom are
commented examples; match them to your apps and to Settings → Tray.

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
non-SNI entries), tools, and weather. Settings persist to `settings.json`
(gitignored — your state stays local).

## License

[GPLv3](LICENSE). The `Caelestia.Blobs` plugin under `blobs-plugin/` derives
from the [Caelestia](https://github.com/caelestia-dots) project.
