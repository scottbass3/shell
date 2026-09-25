-- quickshell.lua — Hyprland integration for this Quickshell desktop shell.
--
-- REQUIRES Hyprland's Lua configuration system (the `hl.*` API). The helper
-- scripts under scripts/hypr/ dispatch `hl.dsp.*` expressions, which only the
-- Lua config interpreter understands. If you use the classic hyprlang (.conf)
-- config, you'll need to port these binds/rules and the scripts yourself.
--
-- Usage: source this at the END of your own hyprland.lua so it overrides:
--     loadfile(os.getenv("HOME") .. "/.config/quickshell/hypr/quickshell.lua")()
--
-- Everything below is namespaced to what the shell needs. Comment out anything
-- you don't want, or copy the bits you like into your own config.

local home    = os.getenv("HOME")
local mainMod = "SUPER"

-- This shell's root, derived from this file's location (hypr/quickshell.lua),
-- so it works from a checkout and from a system install alike.
local qsDir = debug.getinfo(1, "S").source:match("^@(.*)/hypr/[^/]+$") or (home .. "/.config/quickshell")
local ipc   = "qs -p '" .. qsDir:gsub("'", "'\\''") .. "' ipc call "

------------------------------------------------------------------------------
-- Required settings
------------------------------------------------------------------------------

hl.config({
    misc = {
        -- Let the relaunched lock client (quickshell) re-adopt the session lock
        -- instead of Hyprland's "lockscreen app died" failsafe. Needed because
        -- hot-reloading the shell tears down + recreates the WlSessionLock.
        allow_session_lock_restore = true,
    },
})

------------------------------------------------------------------------------
-- Autostart
------------------------------------------------------------------------------

hl.on("hyprland.start", function()
    hl.exec_cmd(home .. "/.config/quickshell/launch.sh")
end)

------------------------------------------------------------------------------
-- Keybindings
------------------------------------------------------------------------------

-- Shell action keybinds (launcher, settings, lock, tools, scratchpad) are
-- configured in-app under Settings → Keybindings and written to
-- hypr/binds.generated.lua. They are UNBOUND by default — until you set them,
-- reach Settings via the bar launcher button or the dashboard gear icon.
local stateBase = os.getenv("XDG_STATE_HOME") or (home .. "/.local/state")
local state     = stateBase .. "/scottbass3-shell"

-- One-time move from the old location ($XDG_STATE_HOME/quickshell, shared by
-- every Quickshell config). Runs before the shell starts, so it reads the moved
-- files; saved wallpaper paths still point into the old directory, so rewrite them.
local legacy = stateBase .. "/quickshell"
local function exists(p) local f = io.open(p); if f then f:close() end; return f ~= nil end
if not exists(state .. "/settings.json") and exists(legacy .. "/settings.json") then
    os.execute("mkdir -p '" .. state:gsub("'", "'\\''") .. "'")
    for _, n in ipairs({ "settings.json", "active.json", "pinned.json", "usage.json",
                         "binds.generated.lua", "hypr.generated.lua",
                         "custom", "exports", "generated", "wallpapers" }) do
        os.rename(legacy .. "/" .. n, state .. "/" .. n)
    end
    local from, to = legacy:gsub("%p", "%%%0"), state:gsub("%%", "%%%%")
    for _, f in ipairs({ state .. "/settings.json", home .. "/.config/hypr/hyprpaper.conf" }) do
        local h = io.open(f)
        if h then
            local txt = h:read("a"); h:close()
            h = io.open(f, "w"); h:write((txt:gsub(from, to))); h:close()
        end
    end
end

local genBinds = state .. "/binds.generated.lua"
if io.open(genBinds) then loadfile(genBinds)() end

-- Hyprland setting overrides (monitors / appearance / input) configured in-app
-- under Settings → Hyprland and written to hypr.generated.lua. Loaded LAST so it
-- layers over your own config (last-wins); absent/empty = no overrides.
local genHypr = state .. "/hypr.generated.lua"
if io.open(genHypr) then loadfile(genHypr)() end

-- Per-monitor workspaces (optional): Super+N switches to workspace N on the
-- FOCUSED monitor; Super+Shift+N moves the active window there. Each monitor
-- id k owns workspaces k*10+1 .. k*10+10. Bound by physical keycode so it works
-- on any keyboard layout (code:10..19 = number row 1..0).
for i = 1, 10 do
    local code = 9 + i
    hl.bind(mainMod .. " + code:" .. code,         hl.dsp.exec_cmd(ipc .. "ws go " .. i .. " switch"))
    hl.bind(mainMod .. " + SHIFT + code:" .. code, hl.dsp.exec_cmd(ipc .. "ws go " .. i .. " move"))
end

-- Apps parked in named special workspaces at launch are configured in-app under
-- Settings → Tray → "Launch in special workspace" and emitted as window rules
-- into hypr.generated.lua above. Keep such rules out of your own config, or the
-- in-app switch can't turn them off.
