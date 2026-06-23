pragma Singleton
import QtQuick
import Quickshell.Io
import "."

// Weather via wttr.in (no API key). French (lang=fr).
// Refreshes on load + every (configurable) interval. Degrades gracefully
// (ok=false) if curl is missing or the request fails.
QtObject {
    id: root

    // Location: "" = auto-detect by IP. Settings override (default: Dijon).
    readonly property string place: SettingsService.get("weather.location", "Dijon")

    property bool   ok:       false
    property int    tempC:    0
    property int    feelsC:   0
    property string desc:     ""
    property int    humidity: 0
    property string icon:     "󰖐"     // weather glyph
    property string location: ""

    // ── Units ─────────────────────────────────────────────────────────────--
    readonly property bool   useF: SettingsService.get("weather.fahrenheit", false)
    readonly property string unit: useF ? "°F" : "°C"
    function conv(c) { return useF ? Math.round(c * 9 / 5 + 32) : Math.round(c) }
    readonly property int temp:  conv(tempC)
    readonly property int feels: conv(feelsC)

    // 3-day forecast: [{ day, min, max, icon }]
    property var forecast: []

    function refresh() { _proc.running = true }

    property Process _proc: Process {
        command: ["sh", "-c",
            "curl -s --max-time 8 'https://wttr.in/" + encodeURIComponent(root.place) + "?format=j1&lang=fr'"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: root._parse(text)
        }
    }

    // Map wttr weather codes → nerd-font glyphs (coarse buckets)
    function _glyph(code) {
        const c = parseInt(code)
        if ([113].includes(c))                          return "󰖙"   // sunny
        if ([116, 119, 122].includes(c))                return "󰖕"   // cloudy
        if ([143, 248, 260].includes(c))                return "󰖑"   // fog
        if ([176,263,266,293,296,299,302,305,308,353,356,359].includes(c)) return "󰖗" // rain
        if ([179,182,185,227,230,317,320,323,326,329,332,335,338,368,371,374,377].includes(c)) return "󰖘" // snow
        if ([200,386,389,392,395].includes(c))          return "󰖓"   // thunder
        return "󰖐"
    }

    function _parse(out) {
        try {
            const j  = JSON.parse(out)
            const cc = j.current_condition[0]
            root.tempC    = parseInt(cc.temp_C)
            root.feelsC   = parseInt(cc.FeelsLikeC)
            // Prefer the localized (French) description when present
            root.desc     = cc.lang_fr?.[0]?.value ?? cc.weatherDesc?.[0]?.value ?? ""
            root.humidity = parseInt(cc.humidity)
            root.icon     = root._glyph(cc.weatherCode)
            const area    = j.nearest_area?.[0]
            root.location = area?.areaName?.[0]?.value ?? ""

            const fr = Qt.locale("fr_FR")
            const fc = []
            for (let i = 0; i < Math.min(3, (j.weather || []).length); i++) {
                const w = j.weather[i]
                const noon = (w.hourly || []).find(h => h.time === "1200") || w.hourly?.[0]
                fc.push({
                    day:  new Date(w.date).toLocaleDateString(fr, "ddd"),
                    min:  parseInt(w.mintempC),
                    max:  parseInt(w.maxtempC),
                    icon: root._glyph(noon?.weatherCode ?? 0)
                })
            }
            root.forecast = fc
            root.ok = true
        } catch (e) {
            root.ok = false
        }
    }

    onPlaceChanged: refresh()

    property Timer _poll: Timer {
        interval: Math.max(5, SettingsService.get("weather.refreshMin", 30)) * 60000
        repeat: true; running: true
        onTriggered: root.refresh()
    }
    Component.onCompleted: refresh()
}
