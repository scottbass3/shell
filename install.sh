#!/usr/bin/env bash
# One-shot installer for this Quickshell desktop shell.
#
#   Remote:  curl -fsSL <raw-url>/install.sh | bash
#   Local:   ./install.sh   (run from a checkout)
#
# It will: clone the repo to ~/.config/quickshell (remote mode), build the
# bundled Caelestia.Blobs Qt plugin, install the YouTube Music bridge deps
# (optional), and print the Hyprland integration steps.
set -euo pipefail

# ── Configuration ────────────────────────────────────────────────────────────
# Set this to your repository before publishing, or pass QS_REPO_URL=... .
REPO_URL="${QS_REPO_URL:-https://github.com/scottbass3/shell}"
BRANCH="${QS_BRANCH:-main}"
CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}/quickshell"

say()  { printf '\033[1;36m::\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m!!\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31mxx\033[0m %s\n' "$*" >&2; exit 1; }
need() { command -v "$1" >/dev/null 2>&1; }

# ── Locate source: a local checkout, or clone? ───────────────────────────────
SRC=""
self="${BASH_SOURCE[0]:-}"
if [ -n "$self" ] && [ -f "$(dirname "$self")/shell.qml" ]; then
    SRC="$(cd "$(dirname "$self")" && pwd -P)"
fi

# ── Required tools ───────────────────────────────────────────────────────────
for t in cmake make git; do need "$t" || die "missing required tool: $t"; done
need quickshell || warn "quickshell not in PATH — install it: https://quickshell.outfoxxed.me"

# ── Clone if not running from a checkout ─────────────────────────────────────
if [ -z "$SRC" ]; then
    if [ -e "$CONFIG" ]; then
        warn "$CONFIG exists — backing up to $CONFIG.bak.$$"
        mv "$CONFIG" "$CONFIG.bak.$$"
    fi
    say "Cloning $REPO_URL → $CONFIG"
    git clone --depth 1 -b "$BRANCH" "$REPO_URL" "$CONFIG"
    SRC="$CONFIG"
elif [ "$SRC" != "$CONFIG" ]; then
    warn "Running from $SRC (not $CONFIG) — building in place."
fi

cd "$SRC"

# ── Build the Caelestia.Blobs Qt plugin ──────────────────────────────────────
say "Building Caelestia.Blobs plugin (Qt6 ≥ 6.8)…"
cmake -S blobs-plugin -B blobs-plugin/build -DCMAKE_BUILD_TYPE=Release
cmake --build blobs-plugin/build --parallel
rm -rf Caelestia && mkdir -p Caelestia
cp -r blobs-plugin/build/qml/Caelestia/Blobs Caelestia/Blobs
say "Plugin → $SRC/Caelestia/Blobs"

# ── User state dir (settings, themes, pins) lives outside the checkout ───────
mkdir -p "${XDG_STATE_HOME:-$HOME/.local/state}/quickshell"
chmod +x launch.sh scripts/hypr/*.sh 2>/dev/null || true

# ── Optional runtime dependency report ───────────────────────────────────────
say "Optional runtime dependencies (features light up when present):"
for d in matugen cava brightnessctl wf-recorder slurp secret-tool superfile beacon; do
    if need "$d"; then printf '   \033[32m✓\033[0m %s\n' "$d"
    else                printf '   \033[33m–\033[0m %s\n' "$d"; fi
done

cat <<EOF

Done. Next steps:
  1. Wire up Hyprland (Lua config required) — add to the end of your hyprland.lua:
       loadfile(os.getenv("HOME") .. "/.config/quickshell/hypr/quickshell.lua")()
  2. Start the shell now:
       "$SRC/launch.sh" &
  3. Press SUPER+I for Settings to configure the bar, theme, tray and tools.
EOF
