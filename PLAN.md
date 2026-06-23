# Quickshell Desktop — Design & Implementation Plan

**Goal**: Build a modern, cohesive desktop shell with Material You theming.  
**Tools**: Quickshell 0.3.0 + QML + Qt6  
**Design language**: Material Design 3 (Material You), dynamic wallpaper-based palette

---

## Vision

A minimal top bar as the permanent anchor point, with a set of rich on-demand panels
that slide or pop into view. Everything themed dynamically from the wallpaper via matugen.

```
┌─────────────────────────────────────────────────────────────────────────────┐
│  [⊞] Firefox — Some Page Title     ● ● ● ◉ ● ●    14:32 · Tue Jun 3       │  ← top bar
│                                                    [🔔] [✦] [⊟] [▶] [⏻]   │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## Components

### 1. Top Bar (permanent, both monitors)

Always-visible, exclusive zone (pushes windows down).

| Zone | Content |
|---|---|
| Left | App launcher · Active window title |
| Center | Workspace dots · Clock |
| Right | Media mini-indicator · Notification bell (badge) · AI button · System tray · Status row (battery/wifi/bt/vol) · Power button |

Status row uses compact icon-only chips that expand to show values on hover.

---

### 2. Dashboard Panel (on-demand)

Triggered: dedicated bar button or hotkey.  
Position: slides in from right (or left), overlays content.

Contains:
- **Quick Settings** — wifi toggle + SSID, bluetooth toggle + device, volume slider, brightness slider
- **Calendar** — month view, current day highlighted
- **Performance** — CPU%, RAM%, network up/down as sparkline graphs or ring charts
- **Weather** — wttr.in (no API key), current conditions + forecast strip
- **Session** — lock, logout, suspend, hibernate, reboot, shutdown

---

### 3. Media Player Panel (on-demand)

Triggered: click media mini-indicator in bar.  
Position: popout panel (same morph system as audio/power/notif).  
Players: Spotify (native MPRIS) + YouTube Music (`youtube-music` AUR, exposes MPRIS).

Contains:
- Album art (blur/gradient fallback if none)
- Track title · artist · album
- Progress bar with scrub + elapsed/remaining time display
- Transport controls: shuffle · prev · play/pause · next · repeat
- Player switcher chips — shown when multiple MPRIS players active (Spotify + YTMusic)
- "Pop out" button — raises the active player's window via `hyprctl dispatch focuswindow`

Bar mini-indicator:
- Shows when any MPRIS player is playing
- Compact: small album art thumbnail + scrolling track name + play/pause button
- Click → opens full media panel

---

### 4. Workspace Overview (on-demand)

Triggered: hotkey (replaces hyprexpo) + bar button.  
Position: full-screen overlay.

Contains:
- Grid of all workspaces
- Each workspace cell: real window thumbnails via `Quickshell.Wayland._Screencopy`
- Click cell → switch to that workspace
- Window title labels below each thumbnail
- Create/delete workspace actions

---

### 5. Notification Center (on-demand, replaces swaync)

Triggered: notification bell button in bar.  
Position: slides in from right.

Contains:
- Notification list, grouped by application
- Each notification: icon · app name · title · body · timestamp · dismiss button
- Per-notification actions (if provided by notification)
- Clear all button
- DND (Do Not Disturb) toggle
- Toast popups in corner when center is closed

---

### 6. AI Assistant Panel (on-demand)

Triggered: dedicated bar button or hotkey.  
Position: floating panel (resizable).

Contains:
- Tab bar: **Claude** | **ChatGPT**
- `WebEngineView` embedding claude.ai / chatgpt.com
- Lazy-loaded (Qt WebEngine only initializes when first opened)

Requires: `qt6-webengine` package

---

## Theme System

Two sources, one interface. All components bind to `ThemeManager.*` — they never
care whether the active theme came from matugen or a preset.

### Sources

| Source | How |
|---|---|
| **matugen (wallpaper)** | Run `matugen image <wallpaper>` → generates `theme/generated/wallpaper.qml` |
| **Presets** | Hand-crafted QML files in `theme/presets/`, one per theme |

### Presets bundled

| Theme | Variants |
|---|---|
| Catppuccin | Mocha (dark) · Macchiato (dark) · Frappe (dark) · Latte (light) |
| Nord | Dark |
| Tokyo Night | Night · Storm · Light |

More can be added by dropping a new file into `theme/presets/`.

### How switching works

```
User clicks preset in Dashboard picker
              │
              ▼
ThemeManager.setTheme("catppuccin-mocha")
              │
              ▼
Writes current theme name to ~/.config/quickshell/theme/active.json
              │
              ▼
ThemeManager loads theme/presets/catppuccin-mocha.qml (or generated/wallpaper.qml)
              │
              ▼
All components re-bind — live update, no restart
```

For matugen:
```
User clicks "Wallpaper" in picker  (or wallpaper changes)
              │
              ▼
Process { command: ["matugen", "image", wallpaperPath, "--template", templatePath] }
              │
              ▼
Overwrites theme/generated/wallpaper.qml
              │
              ▼
ThemeManager.setTheme("wallpaper")  →  FileView reloads  →  live update
```

### Theme file format

Every theme (preset or generated) is a plain JSON file `theme.json` in its folder.
`ThemeManager` reads it via `FileView` and exposes typed `color` properties.

```json
{
  "name": "Catppuccin Mocha",
  "dark": true,
  "palette": {
    "rosewater": "#f5e0dc",
    "mauve": "#cba6f7",
    "base": "#1e1e2e",
    "mantle": "#181825",
    "crust": "#11111b"
  },
  "roles": {
    "primary": "#cba6f7",
    "onPrimary": "#1e1e2e",
    "primaryContainer": "#313244",
    "secondary": "#89b4fa",
    "surface": "#181825",
    "surfaceVariant": "#313244",
    "background": "#1e1e2e",
    "onBackground": "#cdd6f4",
    "error": "#f38ba8",
    "outline": "#585b70"
  }
}
```

matugen template (`quickshell.tera`) generates this same JSON format.
`ThemeManager` only reads `roles` — `palette` is stored for the picker preview swatches.

### Color roles exposed by ThemeManager
```qml
ThemeManager.primary
ThemeManager.onPrimary
ThemeManager.primaryContainer
ThemeManager.secondary
ThemeManager.surface
ThemeManager.surfaceVariant
ThemeManager.background
ThemeManager.onBackground
ThemeManager.error
ThemeManager.outline
ThemeManager.isDark          // bool
ThemeManager.name            // "Catppuccin Mocha"
ThemeManager.availableThemes // list for picker UI
```

### Dashboard theme picker UI

Horizontal scrollable row of theme cards:
- Card shows: theme name + 5-color swatch strip (primary, secondary, surface, background, accent)
- Active theme card has border/highlight
- First card: "Wallpaper" (matugen) — shows current generated palette or placeholder
- Click any card → `ThemeManager.setTheme(id)`, persists to `active.json`

---

## Architecture

### File Structure

```
~/.config/quickshell/
├── shell.qml                         # ShellRoot — Variants over screens
│
├── theme/
│   ├── ThemeManager.qml              # Singleton: loads active theme, exposes color roles
│   ├── active.json                   # Persisted: current theme id (e.g. "catppuccin-mocha")
│   ├── presets/
│   │   ├── catppuccin-mocha.json
│   │   ├── catppuccin-macchiato.json
│   │   ├── catppuccin-frappe.json
│   │   ├── catppuccin-latte.json
│   │   ├── nord.json
│   │   ├── tokyo-night.json
│   │   ├── tokyo-night-storm.json
│   │   └── tokyo-night-light.json
│   ├── generated/
│   │   └── wallpaper.json            # AUTO-GENERATED by matugen — do not edit
│   └── matugen/
│       └── quickshell.tera           # matugen template → wallpaper.json
│
├── bar/
│   ├── Bar.qml                       # PanelWindow, exclusive zone, per screen
│   ├── BarLeft.qml
│   ├── BarCenter.qml
│   └── BarRight.qml
│
├── panels/
│   ├── Dashboard.qml
│   ├── MediaPlayer.qml
│   ├── WorkspaceOverview.qml
│   ├── NotificationCenter.qml
│   └── AIAssistant.qml
│
├── widgets/
│   ├── bar/
│   │   ├── Workspaces.qml            # Quickshell.Hyprland dots
│   │   ├── Clock.qml                 # Time + date
│   │   ├── WindowTitle.qml           # Active window via HyprlandIpc
│   │   ├── MediaMini.qml             # Compact: art thumbnail + track name
│   │   ├── StatusRow.qml             # Battery + wifi + bt + vol compact chips
│   │   ├── NotifButton.qml           # Bell + unread badge
│   │   ├── AIButton.qml
│   │   ├── Tray.qml                  # SystemTray item row
│   │   └── PowerButton.qml
│   └── shared/
│       ├── Calendar.qml
│       ├── QuickSettings.qml         # Wifi/BT/vol/brightness toggles+sliders
│       ├── PerformanceGraphs.qml     # Sparklines for CPU/RAM/net
│       ├── Weather.qml               # wttr.in card
│       ├── SessionControls.qml       # Lock/logout/shutdown grid
│       ├── NotifList.qml             # Notification list + dismiss logic
│       ├── MediaControls.qml         # Full transport controls
│       └── WorkspaceGrid.qml         # Screencopy thumbnails grid
│
└── services/                         # Pragma Singleton — shared across instances
    ├── SystemMetrics.qml             # CPU/RAM/temp via FileView polling /proc
    ├── NetworkSpeed.qml              # /proc/net/dev delta polling
    ├── WeatherService.qml            # HTTP fetch wttr.in, parsed JSON
    ├── NotificationService.qml       # Quickshell.Services.Notifications bridge
    └── ThemeManager.qml              # FileView on colors.qml, hot-reload trigger
```

### Multi-Monitor

`shell.qml` uses `Variants { model: Quickshell.screens }` to spawn `Bar.qml` per monitor.
Each bar receives `screen: modelData` — PanelWindow anchors to that screen.

Panels (Dashboard, NotifCenter, etc.) spawn one per screen too, but only the active
screen's panel opens when triggered. Panels receive `screen` prop and position relative
to that screen's geometry.

### Data Singletons

Heavy polling services are `pragma Singleton` objects instantiated once.
All bar instances and panels import and share the same data.
Avoids duplicate `/proc` reads on multi-monitor setups.

---

## Key Technical Notes

### Quickshell modules used
| Module | Purpose |
|---|---|
| `Quickshell.Wayland` | PanelWindow, layer shell, BackgroundEffect (blur) |
| `Quickshell.Hyprland` | Workspaces, active window, monitor events |
| `Quickshell.Services.Mpris` | Media player data + control |
| `Quickshell.Services.Pipewire` | Volume/mic (output + input) |
| `Quickshell.Services.UPower` | Battery state |
| `Quickshell.Services.SystemTray` | Tray icons + DBusMenu |
| `Quickshell.Services.Notifications` | Full notification protocol replacement for swaync |
| `Quickshell.Bluetooth` | BT toggle + device name |
| `Quickshell.Networking` | Wifi SSID + strength |
| `Quickshell.Io` | FileView, Process, Socket |
| `Quickshell.Wayland._Screencopy` | Window thumbnails for workspace overview |
| `Quickshell.Wayland._BackgroundEffect` | Panel blur |
| `QtWebEngine` (Qt6) | AI assistant WebEngineView |

### Workspace overview + Screencopy
`Quickshell.Wayland._Screencopy` can capture outputs or individual surfaces.
For workspace grid: capture all visible windows per workspace, display as thumbnails.
This is the most complex widget — deferred to a late phase.

### Notifications (replacing swaync completely)
`Quickshell.Services.Notifications` provides:
- `NotificationServer` — registers as freedesktop notification daemon
- Persistent notification list
- Dismiss / action support
swaync removed from hyprland exec-once once this is live.

### Weather (no API key)
`wttr.in/auto?format=j1` returns JSON with current conditions + 3-day forecast.
No API key. Fetched via `Quickshell.Io.Process` or a small JS XMLHttpRequest.
Refresh on demand + every 30 min.

### matugen template (Tera)
Outputs `theme/generated/wallpaper.json` in the same format as preset JSON files.
`ThemeManager` treats it identically to any preset — same interface, same hot-reload path.

### Panel show/hide animations
QML `NumberAnimation` on `x`, `y`, or `opacity`.
Panels use `visible` binding + `enter`/`exit` transitions.
Slide from right: `x` animates from `screen.width` to `screen.width - panel.width`.

---

## Implementation Phases

### Phase 0 — Dependencies
- [x] Install `matugen` (AUR)
- [x] Install `qt6-webengine` (for AI panel — can defer to Phase 9)

### Phase 1 — Theme System
- [x] Write all preset JSON files (Catppuccin ×4, Nord, Tokyo Night ×3)
- [x] `theme/ThemeManager.qml`: singleton, reads `active.json`, exposes color roles
- [x] `theme/active.json`: default to `catppuccin-mocha` (or user choice)
- [x] Switching: `ThemeManager.setTheme(id)` — writes `active.json`, reloads roles live
- [x] Write matugen template (`quickshell.tera`) → outputs `theme/generated/wallpaper.json`
- [x] Write wallpaper-change wrapper script (triggers matugen, then `ThemeManager.setTheme("wallpaper")`)
- [x] Verify: switch preset → all color bindings update live
- [x] Verify: change wallpaper → matugen runs → "wallpaper" theme updates live

### Phase 2 — Bar Scaffold
- [x] `shell.qml`: ShellRoot + Variants over screens
- [x] `bar/Bar.qml`: PanelWindow, correct anchors, exclusiveZone, themed background
- [x] Left/center/right sections wired up
- [x] Verified: bar on both monitors, exclusive zone working

### Phase 3 — Bar Core Widgets
- [x] `Workspaces.qml`: per-monitor workspace dots, active highlight, click to switch
- [x] `Clock.qml`: time (HH:mm) + date, updates every second
- [x] `WindowTitle.qml`: active window class + title via HyprlandIpc

### Phase 4 — Bar Status Widgets
- [x] `StatusRow.qml`: battery % + icon, wifi icon + SSID, BT icon + device, volume icon
- [x] `Tray.qml`: SystemTray icons row, left-click activate, right-click → DBusMenu via PopoutService
- [x] `PowerButton.qml`: opens PowerPanel popup

### Phase 4c — Battery extras (not in original plan)
- [x] Power-profile popout on battery hover (PowerSaver/Balanced/Performance via PowerProfiles)
- [x] `services/BatteryService.qml`: notify on charger plug/unplug + low/critical battery

### Phase 4b — Popout System (not in original plan)
- [x] `services/PopoutService.qml`: singleton tracking which panel is open, anchor position, screen
- [x] Caelestia-style morph transitions: single container, animated width+height, panels crossfade+scale
- [x] `panels/AudioPanel.qml`: volume sliders (output+input), device selection (sink/source switching)
- [x] `panels/PowerPanel.qml`: shutdown/reboot/suspend/lock actions
- [x] `panels/TrayMenuPanel.qml` + `widgets/bar/TrayMenuPage.qml`: contextual tray menus via QsMenuOpener
- [x] Blob background system (BlobGroup + BlobRect) per panel
- [x] Input mask management (click-through except interactive regions)
- [x] Full-screen dismiss overlay for pinned menus (tray contextual)

### Phase 5 — Notification System (replaces swaync)
- [x] `services/NotificationService.qml`: NotificationServer singleton, JS array for safe list access
- [x] Toast popups (stack with per-notif 5s expiry, cap 5, hover pauses+expands, suppressed when full center open)
- [x] `NotifButton.qml`: bell icon + unread count badge, hover opens NC, click pins it
- [x] `panels/NotificationCenter.qml`: notification list (count-based model), dismiss, clear all
- [x] Notification center routed through PopoutService (morphs with other panels)
- [x] swaync removed from hyprland exec-once
- [x] Per-notification dismiss button (✕ in app name row, hover highlight)
- [x] Scrollable notification list (ListView, scrolls when content exceeds panel max height)
- [ ] DND toggle → Dashboard only (see Phase 6)

### Phase 6 — Dashboard Panel (triggered: hover clock in bar center)
- [x] `panels/Dashboard.qml`: popout via PopoutService (morphs with other panels), hover clock to open
- [x] Header: large time + full date
- [x] Calendar: month grid, today highlighted, prev/next month nav
- [x] QuickSettings toggle chips: Wi-Fi (nmcli), Bluetooth, DND, Mute
- [x] Volume slider + brightness slider (`services/BrightnessService.qml`, brightnessctl)
- [x] SessionControls: lock/suspend/logout/reboot/shutdown row
- [x] **DND toggle** lives here (QuickSettings) — not in bar or notification panel
- [x] Bento card layout (rows + columns, not a vertical stack)
- [x] `services/SystemMetricsService.qml`: CPU/RAM/temp polling (/proc + /sys)
- [x] Metrics card: CPU/RAM/temp rings (Canvas arcs)
- [x] `services/WeatherService.qml`: wttr.in JSON fetch (curl, auto-location)
- [x] Weather card: current conditions + 3-day forecast strip
- [x] Bento redesign: Profile | Weather | QuickSettings rail | MPRIS columns; Clock | Calendar | Metrics below
- [x] Profile card: avatar (~/.face), username, uptime; hover → lock/suspend/logout/reboot/shutdown
- [x] Metrics rings vertical
- [x] QuickSettings icon rail + left-sliding elevated flyout (volume=AudioPanel, brightness slider, theme; wifi/vpn/bt placeholder; DND inline toggle)
- [x] Flyout dismiss: click icon toggles/swaps, click elsewhere closes
- [x] `services/MprisService.qml` + MPRIS card: circular album art, progress ring, prev/play/next
- [x] QuickSettings submenus: Wi-Fi (nmcli), VPN (nmcli), Bluetooth (Quickshell.Bluetooth) + blueman/nm-connection-editor launch buttons
- [ ] MPRIS player switcher + pop-out-window button (Phase 7)
- [ ] Theme picker swatch previews (needs per-preset palette load)

### Phase 6c — Custom Lock Screen (not in original plan)
- [x] `services/LockService.qml`: WlSessionLock state + PAM auth (config "login")
- [x] `LockScreen.qml`: WlSessionLock + per-screen surface
- [x] State 1: wallpaper + clock/date (left) + weather (bottom-right)
- [x] State 2: click/key → background blur (MultiEffect) + password prompt
- [x] Triggers: Super+L → `qs ipc call lock lock`; dashboard + power panel lock buttons → LockService.lock()
- [x] hyprland.lua: Super+L rebound from hyprlock to qs ipc

### Phase 6d — Right-edge Tools Toolbar (not in original plan)
Triggered: a small notch on the right screen border indicates the toolbar position.
Hovering the notch deploys (slides in from the right) a vertical list of launch buttons.

- [x] `ToolsBar.qml`: right-edge PanelWindow (per screen), notch indicator, input mask per state
- [x] Hover notch → button strip slides in from the right edge; hover-away auto-collapse (350ms)
- [x] File explorer → kitty `--class superfile -e spf` (floats via existing window_rule)
- [x] Screen recorder → `services/ScreenRecorderService.qml` (wf-recorder + slurp region, toggle + red indicator)
- [x] Docker repo explorer → kitty `--class beacon -e beacon`
- [x] Wallpaper selector → `services/WallpaperService.qml`: lists `~/wallpaper/*`, scrollable thumbnail picker, applies via hyprpaper (starts it if needed) + persists hyprpaper.conf + matugen theme
- [ ] Per-screen note: currently shows on every screen (acceptable); restrict to primary later if desired

### Phase 7 — Media Player (as a Dashboard tab)
- [x] `services/MprisService.qml`: active player + player list + manual select, seek, shuffle, loop cycle, raise, time formatting
- [x] Dashboard tab bar (Home | Media) — switches the dashboard content; popout morphs to the tab's size
- [x] Media tab: large album art, title/artist/album, scrub progress bar + elapsed/total, transport (shuffle · prev · play/pause · next · loop)
- [x] Player switcher chips (shown when >1 player: Spotify / YouTube Music)
- [x] Pop-out button → `MprisService.raise()` (raises the player window) + closes dashboard
- [~] MediaMini bar widget — not added (the bento already has a mini MPRIS card; full control is the Media tab)

### Phase 8 — Workspace Overview ✅
- [x] `panels/WorkspaceOverview.qml`: bar popout (opens on hover of the workspace dots), not a full-screen overlay
- [x] Workspace cells with live `ScreencopyView` thumbnails (app-icon fallback for hidden workspaces), windows positioned + scaled by real geometry, focused cell highlighted, id badge
- [x] Click a cell to switch workspace; click a window thumbnail to switch to its workspace
- [x] Add-workspace cell ("+") → switch to next free workspace in the monitor's range
- [x] Drag-and-drop windows between cells (live preview proxy follows cursor, source hidden while dragging); drop on add-cell → move to a new workspace
- [x] Move does not steal focus / warp cursor (`scripts/movewin.sh`: no_warps + silent move + refocus restore)
- [x] "Screens" section: other monitors' active workspace as drop targets (move window there) + click to focus; their windows are also draggable
- [x] Per-monitor (display-dependent) workspaces: `workspace_rule` ranges (eDP-1 = 1-10, HDMI-A-1 = 11-20), Super+N / Super+Shift+N map to the focused/active-window monitor via `scripts/ws.sh` (keycode-bound for AZERTY), self-healing pin against workspace drift; bar dots + overview relabel to local 1-10
- [x] Special workspaces hidden from the bar dots
- [ ] Global hotkey to open the overview (currently hover-only) — optional

### Phase 9 — App Launcher (rofi replacement, Windows 11 Start-menu style) ✅ (mouse-drag/menu/tabs pending real-input verify)

Triggered: Super (or bar app-launcher button); replaces rofi.
Position: centered floating panel (PanelWindow / popout), morphs in like Win11 Start.

**Layout** (top → bottom):
1. **Search bar** — focused by default; fuzzy search.
2. **Pinned apps** — grid; reorderable (drag); paginated into tabs when overflowing.
3. **Recommended** — frecency-ranked (frequency + recency); excludes pinned apps.

#### 9a — Scaffold + app model ✅
- [x] `services/AppService.qml`: `DesktopEntries` catalog, `launch()` (records usage), icon/key helpers
- [x] `services/AppUsageService.qml`: frecency scoring + JSON persistence (front-loads 9c data layer)
- [x] `services/LauncherService.qml`: open/close state, opens on focused monitor
- [x] `panels/Launcher.qml` + `widgets/launcher/AppGrid.qml`: deploys from bottom edge (slide-up), themed surface
- [x] Trigger: Super+R bind (`hyprland.lua` → `qs ipc call launcher toggle`) + `launcher` IpcHandler in shell.qml
- [x] Open/close slide+fade; dismiss on Escape / click-outside
- [x] Keyboard focus restore on close (bounce-refocus script; shared with tools toolbar)

#### 9b — Search ✅
- [x] Search bar at top, focused on open
- [x] **Type-anywhere**: field always holds focus, so any key types (printable → search)
- [x] Fuzzy search (JS subsequence + word-boundary/prefix bonuses) in `AppService.search()`
- [x] Results replace the pinned + recommended sections
- [x] ↓/↑ navigate results; Enter opens selected; Enter with none selected opens first match
- [x] Escape clears search → restores pinned + recommended view
- [x] ↓ with empty search box → leave search bar, select pinned section (grid arrow-nav)

#### 9c — Recommended section (frecency)
- [x] `services/AppUsageService.qml`: per-app launch history persisted to JSON (`~/.config/quickshell/launcher/usage.json`); append timestamp on launch
- [x] **Frecency scoring**: `score = Σ weight(age)` over recent launches; time-bucket decay (<1h→100, <1d→80, <1w→40, <1mo→20, older→10)
  - [x] Store bounded history per app (cap 50 timestamps)
- [x] Show fixed N apps (6), highest frecency first
- [x] Exclude any app currently pinned (`recommended(excludeKeys, n)`)
- [ ] Right-click → "Remove" = clear that app's launch history (resets score to 0) — needs context menu (9e)
- [x] Keyboard: reachable from pinned via ↓ at bottom row

#### 9d — Pinned apps (state persisted to `~/.config/quickshell/launcher/pinned.json`)
- [x] `services/PinnedService.qml`: ordered key list, persisted JSON, seeded on first run
- [x] Grid of pinned apps; left-click launches
- [x] **Reorder** via mouse drag (floating proxy + drop-index; `PinnedService.move`, persisted) — needs real-mouse verify
- [x] **Tabs/pages**: pinned paginated (cols×3 = 18/page); animated page dots, click to switch
  - [x] Navigate tabs with ← / → at the rightmost / leftmost app of a row
- [x] Keyboard grid nav (arrows); ↓ at bottom row → recommended section

#### 9e — Context menus (right-click)
- [x] Context menu overlay in `Launcher.qml` (keyboard + mouse navigable), AppGrid emits `contextRequested`
- [x] On a **pinned app**: Launch, Unpin
- [x] On a **recommended app**: Launch, Pin, Remove (clear usage history)
- [x] On a **search result**: Launch, Pin/Unpin
- [x] Full keyboard navigation of the menu (↑/↓ select, Enter run, Esc close)

#### 9f — Accessibility / polish
- [x] Entire menu navigable by keyboard only AND by mouse only
- [x] Focus ring / selection highlight consistent across sections (secondaryContainer + primary border)
- [ ] Optional: scroll-to-selected when keyboard nav moves off-screen (defer)

### Phase 10 — Notes App (Tools toolbar)

Add a note-taking app to the right-edge Tools toolbar (Phase 6d).

- [ ] `panels/Notes.qml` (or `widgets/tools/Notes.qml`): floating notes panel/window
- [ ] `services/NotesService.qml`: notes persisted to `~/.config/quickshell/notes/` (one file per note, e.g. markdown)
- [ ] Note list (sidebar) + editor pane; create / delete / rename notes
- [ ] Autosave on edit
- [ ] Tools-toolbar launch button (notch strip) opens it
- [ ] (Optional) basic markdown rendering / preview toggle

### Phase 11 — Settings Menu

A central place to configure the shell, replacing scattered hardcoded constants.

**Status (2026-06-12):** Foundation built — `services/SettingsService.qml` (settings.json, get/set/toggle/reset, forward-compatible), `services/DependencyService.qml` (binary probe + install hints), `services/SettingsUi.qml` (open state + focus restore), `panels/Settings.qml` (centered modal: sidebar + Appearance/Bar/Tools/Dependencies/Advanced; toggle/slider/segmented/button controls; opt-in toggles show a dependency badge). Opens via `qs ipc call settings toggle` + **Super+I** + Dashboard quick-settings gear. **Wired (live-applies):** Clock `bar.clock.use24h`/`seconds`; bar widget visibility (`bar.widgets.launcher/windowTitle/status`); tools gating (`tools.enabled` + per-tool `tools.*` AND'd with `DependencyService`); ThemeManager `bar.height`/`appearance.panelRadius`/`appearance.fontSize`; media `media.visualizer`/`media.bongo`/`media.ytm`; notifications `clickOpensApp`/`dndDefault`/`toastMs`/`toastMax`; weather `location`/`fahrenheit`/`refreshMin`; workspaces `hideSpecial`/`numbers`. Categories: Appearance, Bar, Media, Notifications, Weather, Tools, Dependencies, Advanced. Controls: toggle/slider/segmented/text/button. appearance modes **frame/topbar/islands** (`appearance.mode`, live; islands = per-section bar pills + detached floating panel cards). Theme picker relocated into Settings → Appearance. **Theme designer** done: editable `theme/custom.json` via `ThemeManager.customize()/setRole()/importTheme()`; designer UI = per-role hex editors (live apply), Import (path→Custom), Export (→theme/exports/). **Remaining:** islands styling for launcher/tools edge panels; position/orientation; unified-workspaces behavior; Power category; tray **add non-SNI app**. Done: tray **hide** + per-app **special-ws** config (Settings → Tray, `tray.hidden`/`tray.specialWs`). Tool/widget defaults are `true` on the dev machine; **distribution ships a bundled `settings.json` with opt-in features off**. Remaining: appearance modes (frame/topbar/islands), bar height/radius/font sliders applied, position/orientation, theme designer (export/import), tray config (add non-SNI app, per-app special-ws, hide), unified-workspaces toggle, media/notif/weather/power categories.

**Design philosophy (this is meant to be distributed):**
- **Non-intrusive**: ships with a minimal, conservative default (bare-minimum bar, tools off, no extra widgets). A fresh install looks clean and does nothing surprising.
- **Opt-in**: every non-essential feature/widget/tool is OFF by default; the user turns things on deliberately.
- **Few dependencies**: core shell runs with stock Quickshell + coreutils. Anything needing an extra package (cava, wf-recorder, matugen, node for the YT bridge, etc.) is an **optional** feature, gated behind a runtime requirement check (see Tools). Never hard-fail or assume a binary exists.

**Architecture**
- `services/SettingsService.qml`: singleton; loads/saves `~/.config/quickshell/settings.json`; typed properties with conservative defaults; `set(key, value)` persists + hot-applies (no reload). All components bind to `SettingsService.*` instead of hardcoded values; missing/old keys fall back to defaults (forward-compatible).
- `services/DependencyService.qml`: checks whether a required binary exists (`which`-style probe), exposes `available(name)` + a human install hint per optional dep. Used to gate opt-in features and prompt the user.
- `panels/Settings.qml`: categorized UI (left category list + right scrollable pane, Material controls). Opened from a Dashboard gear button (primary trigger).
- Migration: move existing hardcoded values to defaults (`ThemeManager` typography/spacing, weather location, clock format, bar widget list, toast timing, workspace ranges…).

**What gets configured**

- **Appearance / Theme**
  - [ ] Active theme (preset or wallpaper) — relocate the Dashboard picker here
  - [ ] **Theme designer**: edit M3 role colors live (color pickers) → save as a named custom theme; **Export** to a file (share) + **Import** from a file
  - [ ] Wallpaper picker (link to `WallpaperService`)
  - [ ] **Overall appearance mode**: `frame` (current SDF border + merged panels) · `top-bar only` (no border/frame) · `floating islands` (separated rounded bar segments / panels). One switch reflows the shell.
  - [ ] **Layout / position / orientation** of the System bar, Tools toolbar, Launcher: which screen edge (top/bottom/left/right), alignment, per-monitor placement
  - [ ] Bar height, corner radius, floating gap, screen border width
  - [ ] Panel radius, panel blur on/off
  - [ ] Font family + base font sizes
- **Bar** (bare minimum enabled by default; everything else opt-in)
  - [ ] Default-on set: clock, workspaces, tray, power (the essentials). Window title, launcher button, media mini, status row, notification bell, extra status chips = **opt-in** toggles
  - [ ] Widget order per zone (left/center/right)
  - [ ] Clock: 12/24h, date format, show seconds
  - [ ] Workspaces: dots vs numbers; **hide special** toggle; **switch back to unified (shared) workspaces** between screens vs the per-monitor scheme
  - [ ] **System tray config**:
    - [ ] Add an app to the tray that doesn't implement SNI itself (manual entry: name/icon/class → click action)
    - [ ] Per-tray-app: enable/disable the special-workspace parking, set/clear its special-ws name
    - [ ] Hide specific apps from the tray
- **Launcher**
  - [ ] Columns, recommended count, pinned-per-page
  - [ ] Manage pinned apps (add/remove/reorder) — link to the launcher
  - [ ] Reset usage data (clears frecency `usage.json`)
- **Media**
  - [ ] Visualizer: on/off, bar length, color source (requires `cava` → opt-in, dep-checked)
  - [ ] Bongo cat: on/off
  - [ ] Preferred/default player
  - [ ] YouTube Music companion (opt-in, needs `node`): enable/disable, server port, **re-authorize** button, clear stored token
- **Notifications**
  - [ ] DND default (and optional schedule)
  - [ ] Toast: timeout, max stack size, screen corner
  - [ ] Click-notification-opens-app (toggle)
  - [ ] Per-app mute list
- **Weather**
  - [ ] Location (auto vs city), units (°C/°F), refresh interval
- **Workspaces / WM**
  - [ ] Per-monitor ranges (eDP-1 = 1-10, HDMI-A-1 = 11-20) vs unified — view/edit (mirrors the bar toggle)
  - [ ] Special-workspace ↔ app-class map (tray parking)
- **Tools toolbar** (entire toolbar OFF by default; each tool OFF by default)
  - [ ] Master enable for the toolbar
  - [ ] Enable each tool one-by-one (file explorer, screen recorder, docker explorer, wallpaper picker, notes…)
  - [ ] **Requirement check on enable**: probe the tool's binary via `DependencyService`; if missing, block + prompt with the package to install (e.g. recorder → `wf-recorder`+`slurp`; files → `superfile`; docker → `beacon`). Optional deps never installed automatically — just surfaced.
  - [ ] Per-tool command override; auto-collapse delay; notch side
- **System / Power**
  - [ ] Power-menu actions shown (lock/suspend/logout/reboot/shutdown)
  - [ ] Lock: idle timeout (hypridle if present), blur amount
  - [ ] Startup apps (exec-once) — at least view; edit if feasible
- **Performance / Metrics**
  - [ ] Poll intervals (CPU/RAM/net), which metric rings are shown
- **Advanced**
  - [ ] Reload config, open `settings.json`, reset-to-defaults, export/import whole config

**UI**
- [ ] `panels/Settings.qml`: sidebar categories + scrollable pane; toggles, sliders, dropdowns, text/number fields, color pickers
- [ ] Opt-in toggles show a dependency badge + install hint when the required binary is missing (disabled until present)
- [ ] Live apply (no restart) + persist on change
- [ ] (Optional) settings search box
- [ ] Trigger: Dashboard gear button (consider also a launcher/tools entry)

### Phase 12 — AI Assistant Panel (POSTPONED — blocked on browser embedding)

**Blocked**: embedding a `WebEngineView` crashes stock Quickshell (`base::CommandLine
cannot be properly initialized`, qArgc=0, jemalloc conflict). True embedding needs a
patched Quickshell build (PR #351 + jemalloc off) or a separate process. **Postponed
until Quickshell ships official browser/WebView support upstream.**

- [ ] (blocked) Install `qt6-webengine`
- [ ] (blocked) `panels/AIAssistant.qml`: floating resizable panel
- [ ] (blocked) `AIButton.qml` in bar
- [ ] (blocked) Tab bar: Claude (claude.ai) + ChatGPT (chatgpt.com)
- [ ] (blocked) Lazy WebEngineView init
- [ ] Revisit when Quickshell adds WebView support (track PR #351 / upstream)

### Phase 13 — Polish
- [ ] All panel open/close animations (slide + fade)
- [ ] Hover states on all interactive bar elements
- [ ] Keyboard shortcuts for panels
- [ ] Multi-monitor edge cases (panel positions, screen detection)
- [ ] Screencopy thumbnail refresh rate tuning

### Phase 14 — Migration
- [ ] Confirm all features working
- [ ] `hyprland.conf`: remove `exec-once=waybar`, add `exec-once=quickshell`
- [ ] Confirm swaync removed (done in Phase 5)

---

## Open Questions / Decisions

- Bar height (px)? Suggest: 36px (dense) or 44px (comfortable)
- Workspace style: filled dots / numbers / window count badges?
- Dashboard position: right slide-in or centered floating card?
- Weather location: auto-detect (wttr.in/auto) or hardcode city?
- Laptop screen vs external: same layout, or simplified layout on laptop?
- Dark vs light scheme: always dark, always light, or follow system/time?
