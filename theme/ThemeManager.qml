pragma Singleton
import QtQuick
import Quickshell.Io
import "../services"

QtObject {
    id: root

    // ── Available themes (order = picker order) ─────────────────────────────
    readonly property var availableThemes: [
        { id: "wallpaper",              name: "Wallpaper",              dark: true  },
        { id: "catppuccin-mocha",       name: "Catppuccin Mocha",       dark: true  },
        { id: "catppuccin-macchiato",   name: "Catppuccin Macchiato",   dark: true  },
        { id: "catppuccin-frappe",      name: "Catppuccin Frappé",      dark: true  },
        { id: "catppuccin-latte",       name: "Catppuccin Latte",       dark: false },
        { id: "nord",                   name: "Nord",                   dark: true  },
        { id: "tokyo-night",            name: "Tokyo Night",            dark: true  },
        { id: "tokyo-night-storm",      name: "Tokyo Night Storm",      dark: true  },
        { id: "tokyo-night-light",      name: "Tokyo Night Light",      dark: false },
    ]

    // Roles exposed in the theme designer (curated subset of the M3 tokens).
    readonly property var editableRoles: [
        "primary", "onPrimary", "secondary", "tertiary",
        "background", "onBackground", "surface", "onSurface",
        "surfaceContainer", "surfaceContainerHigh", "surfaceVariant", "onSurfaceVariant",
        "error", "outline", "outlineVariant"
    ]
    // Current value of a role as a "#rrggbb" string (for the designer fields).
    function roleHex(key) {
        const c = root[key]
        return (c && c.toString) ? c.toString() : ""
    }

    // ── Active theme state ───────────────────────────────────────────────────
    property string activeId: "catppuccin-mocha"
    property var    _data:    ({})
    readonly property var themeData: _data   // public: full loaded theme.json (for export)

    // ── Color roles (M3 tokens) ──────────────────────────────────────────────
    // NOTE: roles whose name begins with "on" cannot use a `onX: expr` binding —
    // QML parses that as a signal handler and silently drops the binding (text
    // renders black). They are declared without initializer and set in _applyRoles().
    readonly property color primary:              _role("primary",              "#6750A4")
    property color onPrimary
    readonly property color primaryContainer:     _role("primaryContainer",     "#EADDFF")
    property color onPrimaryContainer
    readonly property color secondary:            _role("secondary",            "#625B71")
    property color onSecondary
    readonly property color secondaryContainer:   _role("secondaryContainer",   "#E8DEF8")
    property color onSecondaryContainer
    readonly property color tertiary:             _role("tertiary",             "#7D5260")
    property color onTertiary
    readonly property color surface:              _role("surface",              "#1C1B1F")
    readonly property color surfaceVariant:       _role("surfaceVariant",       "#49454F")
    readonly property color surfaceContainer:     _role("surfaceContainer",     "#211F26")
    readonly property color surfaceContainerHigh: _role("surfaceContainerHigh", "#2B2930")
    readonly property color surfaceContainerLow:  _role("surfaceContainerLow",  "#1D1B20")
    property color onSurface
    property color onSurfaceVariant
    readonly property color background:           _role("background",           "#1C1B1F")
    property color onBackground
    readonly property color error:                _role("error",                "#F2B8B5")
    property color onError
    readonly property color outline:              _role("outline",              "#938F99")
    readonly property color outlineVariant:       _role("outlineVariant",       "#49454F")
    readonly property color inverseSurface:       _role("inverseSurface",       "#E6E1E5")
    readonly property color inverseOnSurface:     _role("inverseOnSurface",     "#313033")
    readonly property color inversePrimary:       _role("inversePrimary",       "#6750A4")
    readonly property color shadow:               _role("shadow",               "#000000")
    readonly property color scrim:                _role("scrim",                "#000000")

    // ── Meta ─────────────────────────────────────────────────────────────────
    readonly property bool   isDark: _data.dark !== undefined ? _data.dark : true
    readonly property string name:   _data.name  !== undefined ? _data.name  : ""

    // ── Palette (raw, for swatch preview) ────────────────────────────────────
    readonly property var palette: _data.palette !== undefined ? _data.palette : ({})

    // ── Typography & spacing constants ───────────────────────────────────────
    // Configurable via SettingsService (defaults preserve the original values).
    readonly property int    barHeight:      SettingsService.get("bar.height", 40)
    readonly property int    barFloatTop:    8
    readonly property int    barTotalHeight: barHeight + barFloatTop + 4
    readonly property int    barRadius:      barHeight / 2
    readonly property int    screenRadius:   20
    readonly property int    panelRadius:    SettingsService.get("appearance.panelRadius", 16)
    readonly property int    borderWidth:    8
    readonly property int    chipRadius:     8
    readonly property int    spacing:        8
    readonly property int    spacingLg:      16
    readonly property string fontFamily:     "JetBrainsMono Nerd Font"
    readonly property int    _fontBase:      SettingsService.get("appearance.fontSize", 13)
    readonly property int    fontSizeSm:     _fontBase - 1
    readonly property int    fontSizeMd:     _fontBase
    readonly property int    fontSizeLg:     _fontBase + 3

    // ── Internal ─────────────────────────────────────────────────────────────
    function _role(key, fallback) {
        if (_data.roles && _data.roles[key] !== undefined)
            return _data.roles[key]
        return fallback
    }

    // Set "on*" roles imperatively (see note above their declarations).
    function _applyRoles() {
        onPrimary            = _role("onPrimary",            "#FFFFFF")
        onPrimaryContainer   = _role("onPrimaryContainer",   "#21005D")
        onSecondary          = _role("onSecondary",          "#FFFFFF")
        onSecondaryContainer = _role("onSecondaryContainer", "#1D192B")
        onTertiary           = _role("onTertiary",           "#FFFFFF")
        onSurface            = _role("onSurface",            "#E6E1E5")
        onSurfaceVariant     = _role("onSurfaceVariant",     "#CAC4D0")
        onBackground         = _role("onBackground",         "#E6E1E5")
        onError              = _role("onError",              "#601410")
    }

    readonly property string _customDir: Qt.resolvedUrl("custom").toString().replace(/^file:\/\//, "")
    function _isUser(id) { return ("" + id).indexOf("user:") === 0 }
    function _slugOf(id) { return ("" + id).slice(5) }

    function _themeFilePath(id) {
        const base = Qt.resolvedUrl(".").toString().replace(/^file:\/\//, "")
        if (id === "wallpaper") return base + "generated/wallpaper.json"
        if (_isUser(id))        return _customDir + "/" + _slugOf(id) + ".json"
        return base + "presets/" + id + ".json"
    }

    // ── User themes (theme/custom/<slug>.json) + designer + CRUD ──────────────
    property var userThemes: []                              // [{id,slug,name,dark}]
    readonly property var pickerThemes: availableThemes.concat(userThemes)

    property Process _scan: Process {
        stdout: StdioCollector { onStreamFinished: root._parseScan(text) }
    }
    function refreshThemes() {
        const d = _customDir.replace(/'/g, "'\\''")
        _scan.command = ["sh", "-c",
            "mkdir -p '" + d + "'; for f in '" + d + "'/*.json; do [ -e \"$f\" ] || continue; " +
            "n=$(jq -r '.name // \"Theme\"' \"$f\" 2>/dev/null); dk=$(jq -r '.dark // true' \"$f\" 2>/dev/null); " +
            "b=$(basename \"$f\" .json); printf '%s\\t%s\\t%s\\n' \"$b\" \"$n\" \"$dk\"; done"]
        _scan.running = true
    }
    function _parseScan(txt) {
        const out = []
        const lines = ("" + txt).split("\n")
        for (let i = 0; i < lines.length; i++) {
            const t = lines[i]; if (!t.trim()) continue
            const p = t.split("\t")
            if (p.length < 2) continue
            out.push({ id: "user:" + p[0], slug: p[0], name: p[1], dark: (p[2] || "true").trim() === "true", custom: true })
        }
        userThemes = out
    }

    // Writer: after writing a user theme, optionally switch to it, else reload if active.
    property string _pendingSwitchId: ""
    property Process _userWriter: Process {
        onExited: {
            root.refreshThemes()
            if (root._pendingSwitchId !== "") { const s = root._pendingSwitchId; root._pendingSwitchId = ""; root.setTheme(s) }
            else if (root._isUser(root.activeId)) root._themeView.reload()
        }
    }
    function _writeUser(slug, jsonStr, switchTo) {
        const p = (_customDir + "/" + slug + ".json").replace(/'/g, "'\\''")
        if (switchTo) _pendingSwitchId = "user:" + slug
        _userWriter.command = ["sh", "-c",
            "mkdir -p '" + _customDir.replace(/'/g, "'\\''") + "' && printf '%s' '" + jsonStr.replace(/'/g, "'\\''") + "' > '" + p + "'"]
        _userWriter.running = true
    }

    function _slugify(name) {
        let s = ("" + name).toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-+|-+$/g, "")
        if (!s) s = "theme"
        let base = s, n = 2
        while (userThemes.some(t => t.slug === s)) { s = base + "-" + n; n++ }
        return s
    }
    function _currentData(name) {
        const d = JSON.parse(JSON.stringify(_data || {}))
        d.name = name
        if (!d.roles) d.roles = {}
        for (let i = 0; i < editableRoles.length; i++) {
            const k = editableRoles[i]
            if (d.roles[k] === undefined) d.roles[k] = roleHex(k)
        }
        return d
    }

    // Create a new user theme seeded from the current colors, switch to it.
    function createTheme(name) { _writeUser(_slugify(name), JSON.stringify(_currentData(name || "New Theme")), true) }

    // Duplicate an existing theme (preset or user) into a new user theme.
    function duplicateTheme(srcId, name) {
        const slug = _slugify(name)
        const src = _themeFilePath(srcId).replace(/'/g, "'\\''")
        const dst = (_customDir + "/" + slug + ".json").replace(/'/g, "'\\''")
        const nm  = ("" + (name || "Copy")).replace(/'/g, "'\\''")
        _pendingSwitchId = "user:" + slug
        _userWriter.command = ["sh", "-c",
            "mkdir -p '" + _customDir.replace(/'/g, "'\\''") + "' && t=$(jq --arg n '" + nm + "' '.name=$n' '" + src + "') && printf '%s' \"$t\" > '" + dst + "'"]
        _userWriter.running = true
    }

    // Rename a user theme (changes its display name; slug/id stay stable).
    function renameTheme(id, newName) {
        if (!_isUser(id)) return
        const f  = _themeFilePath(id).replace(/'/g, "'\\''")
        const nm = ("" + newName).replace(/'/g, "'\\''")
        _userWriter.command = ["sh", "-c", "t=$(jq --arg n '" + nm + "' '.name=$n' '" + f + "') && printf '%s' \"$t\" > '" + f + "'"]
        _userWriter.running = true   // onExited refreshes the list
    }

    // Delete a user theme; if it was active, fall back to the first preset.
    property bool _delWasActive: false
    property Process _delProc: Process {
        onExited: {
            root.refreshThemes()
            if (root._delWasActive) { root._delWasActive = false; root.setTheme(root.availableThemes[1].id) }
        }
    }
    function deleteTheme(id) {
        if (!_isUser(id)) return
        _delWasActive = (id === activeId)
        _delProc.command = ["sh", "-c", "rm -f '" + _themeFilePath(id).replace(/'/g, "'\\''") + "'"]
        _delProc.running = true
    }

    // Edit one role of the ACTIVE user theme (live: write + reload). Presets are read-only.
    function setRole(key, val) {
        if (!_isUser(activeId)) return
        const d = JSON.parse(JSON.stringify(_data || {}))
        if (!d.roles) d.roles = {}
        d.roles[key] = "" + val
        _writeUser(_slugOf(activeId), JSON.stringify(d), false)
    }

    // Import a theme.json from a path as a new user theme.
    function importTheme(path, name) {
        const slug = _slugify(name || "imported")
        const src = ("" + path).replace(/'/g, "'\\''")
        const dst = (_customDir + "/" + slug + ".json").replace(/'/g, "'\\''")
        _pendingSwitchId = "user:" + slug
        _userWriter.command = ["sh", "-c", "mkdir -p '" + _customDir.replace(/'/g, "'\\''") + "' && cp '" + src + "' '" + dst + "'"]
        _userWriter.running = true
    }

    // ── Public API ───────────────────────────────────────────────────────────
    function setTheme(id) {
        activeId = id
        _writeActive.command = [
            "sh", "-c",
            "printf '%s' '{\"theme\":\"" + id + "\"}' > " + Qt.resolvedUrl("active.json").toString().replace(/^file:\/\//, "")
        ]
        _writeActive.running = true
        const p = _themeFilePath(id)
        // If the path is unchanged (e.g. re-selecting "wallpaper" after matugen
        // regenerated it), force a reload — matugen's atomic write defeats the
        // FileView change watcher, so the colors wouldn't otherwise refresh.
        if (_themeView.path === p) _themeView.reload()
        else                       _themeView.path = p
    }

    function generateWallpaperTheme(wallpaperPath) {
        const cfgPath = Qt.resolvedUrl("matugen/matugen.toml").toString().replace(/^file:\/\//, "")
        // Pick light/dark mode from the wallpaper's mean luminance (matugen
        // itself always defaults to dark).
        _matugen.command = ["sh", "-c",
            'WP="$1"; CFG="$2"; ' +
            'L=$(magick "$WP" -resize 1x1\\! -colorspace Gray -format "%[fx:mean]" info: 2>/tmp/matugen-mode.err); ' +
            'MODE=dark; ' +
            '[ -n "$L" ] && awk -v l="$L" "BEGIN{exit !(l>0.55)}" && MODE=light; ' +
            'echo "L=$L MODE=$MODE WP=$WP" > /tmp/matugen-mode.log; ' +
            'matugen -c "$CFG" --mode "$MODE" image --source-color-index 0 "$WP"',
            "sh", wallpaperPath, cfgPath]
        _matugen.running = true
    }

    // ── File watchers ─────────────────────────────────────────────────────────
    property FileView _activeView: FileView {
        path:         Qt.resolvedUrl("active.json").toString().replace(/^file:\/\//, "")
        watchChanges: true
        blockLoading: true
        onLoaded: {
            try {
                const parsed = JSON.parse(text())
                if (parsed.theme && parsed.theme !== root.activeId) {
                    root.activeId = parsed.theme
                    _themeView.path = root._themeFilePath(parsed.theme)
                }
            } catch(e) {}
        }
    }

    property FileView _themeView: FileView {
        watchChanges: true
        blockLoading: true
        onLoaded: {
            try { root._data = JSON.parse(text()); root._applyRoles() } catch(e) {}
        }
    }

    // ── Processes ─────────────────────────────────────────────────────────────
    property Process _writeActive: Process { running: false }

    property Process _matugen: Process {
        running: false
        onExited: (code, signal) => {
            if (code === 0)
                root.setTheme("wallpaper")
        }
    }

    // ── Bootstrap ─────────────────────────────────────────────────────────────
    Component.onCompleted: {
        try {
            const parsed = JSON.parse(_activeView.text())
            activeId = parsed.theme || "catppuccin-mocha"
        } catch(e) {
            activeId = "catppuccin-mocha"
        }
        _applyRoles()
        _themeView.path = _themeFilePath(activeId)
        refreshThemes()
    }
}
