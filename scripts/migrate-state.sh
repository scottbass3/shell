#!/bin/sh
# Moves this shell's state from $XDG_STATE_HOME/quickshell (its old location,
# shared by every Quickshell config) to $XDG_STATE_HOME/scottbass3-shell.
# Called by hypr/quickshell.lua before the shell starts, and by the shell itself
# in case it hot-reloads onto the new location before Hyprland restarts.
# Exit 0 = migrated, 1 = nothing to do (safe to call repeatedly).
base="${XDG_STATE_HOME:-$HOME/.local/state}"
old="$base/quickshell"
new="$base/scottbass3-shell"

[ -f "$old/settings.json" ] && [ ! -f "$new/settings.json" ] || exit 1

mkdir -p "$new"
for n in settings.json active.json pinned.json usage.json \
         binds.generated.lua hypr.generated.lua custom exports generated wallpapers; do
    [ -e "$old/$n" ] || continue
    if [ -d "$old/$n" ] && [ -d "$new/$n" ]; then
        cp -a "$old/$n/." "$new/$n/" && rm -rf "$old/$n"
    else
        # A shell that started before the move may already have regenerated this.
        rm -rf "$new/$n"
        mv "$old/$n" "$new/$n"
    fi
done

# Saved wallpaper paths point into the old directory.
old_re=$(printf '%s/' "$old" | sed 's/[][\.*^$|]/\\&/g')
for f in "$new/settings.json" "$HOME/.config/hypr/hyprpaper.conf"; do
    [ -f "$f" ] && sed -i "s|$old_re|$new/|g" "$f"
done
exit 0
