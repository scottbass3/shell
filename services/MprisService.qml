pragma Singleton
import QtQuick
import QtQml
import Quickshell.Services.Mpris
import "."

// Active MPRIS player + track info + full transport controls. Supports manual
// player selection, seeking, shuffle/loop, and raising the player window.
// The YouTube Music companion server (YtmCompanionService) is merged in as a
// virtual player so YT Music is always present (even when paused) with richer
// data; it replaces the MPRIS "youtube" entry when available.
QtObject {
    id: root

    // The companion acts as a sentinel "player" object in the list.
    readonly property var ytm: YtmCompanionService
    function _isYtm(p) { return p === YtmCompanionService }
    readonly property bool ytmActive: active === YtmCompanionService

    // Real players: drop playerctld, de-dupe by identity, and fold in the
    // companion (replacing the MPRIS youtube entry when the companion is up).
    readonly property var players: {
        const raw = Mpris.players?.values ?? []
        const ytmUp = YtmCompanionService.available
        const seen = {}
        const out = []
        for (const p of raw) {
            const id = (p?.identity ?? "").toLowerCase()
            const dn = (p?.dbusName ?? "").toLowerCase()
            if (dn.indexOf("playerctld") >= 0 || id.indexOf("playerctld") >= 0) continue
            if (ytmUp && id.indexOf("youtube") >= 0) continue   // companion supersedes
            if (id !== "" && seen[id]) continue
            seen[id] = true
            out.push(p)
        }
        if (ytmUp) out.push(YtmCompanionService)
        return out
    }
    property var _selected: null     // manual override (player object); null = auto
    property int _tick: 0

    // Short display name (identity is often a raw app id, e.g. youtube_music)
    function label(p) {
        if (root._isYtm(p)) return "YouTube"
        const n = (p?.identity ?? "").toString().toLowerCase()
        if (n.indexOf("youtube") >= 0) return "YouTube"
        if (n.indexOf("spotify") >= 0) return "Spotify"
        if (n.indexOf("firefox") >= 0 || n.indexOf("mozilla") >= 0) return "Firefox"
        if (n.indexOf("vlc") >= 0)     return "VLC"
        if (n.indexOf("mpv") >= 0)     return "mpv"
        if (n.indexOf("chrom") >= 0)   return "Browser"
        const c = (p?.identity ?? "Player").replace(/[._]/g, " ").trim()
        return c ? c.charAt(0).toUpperCase() + c.slice(1) : "Player"
    }

    // Nerd-font glyph per player
    function icon(p) {
        if (root._isYtm(p)) return "󰗃"
        const n = (p?.identity ?? "").toString().toLowerCase()
        if (n.indexOf("youtube") >= 0) return "󰗃"
        if (n.indexOf("spotify") >= 0) return "󰓇"
        if (n.indexOf("firefox") >= 0 || n.indexOf("mozilla") >= 0) return "󰈹"
        if (n.indexOf("vlc") >= 0)     return "󰕼"
        if (n.indexOf("chrom") >= 0)   return "󰊯"
        return "󰝚"
    }

    // Re-pick whenever the player set changes or the tick advances.
    readonly property var active: {
        const _ = root._tick
        const ps = root.players
        if (!ps || ps.length === 0) return null
        if (root._selected && ps.indexOf(root._selected) >= 0) return root._selected
        // prefer a currently-playing source (companion counts via its own flag)
        for (const p of ps) {
            if (p === YtmCompanionService) { if (YtmCompanionService.playing) return p }
            else if (p.playbackState === MprisPlaybackState.Playing) return p
        }
        return ps[0]
    }

    readonly property bool hasPlayer: active !== null
    readonly property bool multiple:  players.length > 1
    readonly property bool playing:   ytmActive ? YtmCompanionService.playing
                                                : (active?.playbackState === MprisPlaybackState.Playing)
    readonly property string title:   ytmActive ? YtmCompanionService.title  : (active?.trackTitle  ?? "")
    readonly property string artist:  ytmActive ? YtmCompanionService.artist : (active?.trackArtist ?? "")
    readonly property string album:   ytmActive ? YtmCompanionService.album  : (active?.trackAlbum  ?? "")
    readonly property string artUrl:  ytmActive ? YtmCompanionService.artUrl : (active?.trackArtUrl ?? "")
    readonly property string identity: ytmActive ? "youtube" : (active?.identity ?? "")

    readonly property real length:   ytmActive ? (YtmCompanionService.durationMs / 1000) : (active?.length ?? 0)

    // Smoothly interpolated position: anchor to the player's reported position,
    // then advance with wall-clock while playing (re-anchored on real updates).
    property real _anchorPos: 0
    property real _anchorMs:  0
    property int  _ptick:     0
    function _reanchor() { _anchorPos = active?.position ?? 0; _anchorMs = Date.now() }

    readonly property real position: {
        const _ = root._ptick
        if (!active) return 0
        if (ytmActive) return YtmCompanionService.positionMs / 1000   // companion interpolates itself
        const p = root.playing ? _anchorPos + (Date.now() - _anchorMs) / 1000 : _anchorPos
        return root.length > 0 ? Math.max(0, Math.min(root.length, p)) : Math.max(0, p)
    }
    readonly property real progress: length > 0 ? Math.max(0, Math.min(1, position / length)) : 0

    // Re-anchor on real position / state / track changes
    property Connections _anchorConn: Connections {
        target: root.active
        ignoreUnknownSignals: true
        function onPositionChanged()      { root._reanchor() }
        function onPlaybackStateChanged() { root._reanchor() }
        function onTrackTitleChanged()    { root._reanchor() }
    }
    onActiveChanged: _reanchor()

    // Fast tick → smooth UI updates
    property Timer _smooth: Timer {
        interval: 200; repeat: true; running: root.active !== null && root.playing
        onTriggered: root._ptick++
    }

    readonly property bool canNext: ytmActive ? true : (active?.canGoNext     ?? false)
    readonly property bool canPrev: ytmActive ? true : (active?.canGoPrevious ?? false)
    readonly property bool canSeek: ytmActive ? (YtmCompanionService.durationMs > 0) : (active?.canSeek ?? false)
    readonly property bool canRaise: ytmActive ? true : (active?.canRaise ?? false)
    readonly property bool shuffle:      ytmActive ? false : (active?.shuffle          ?? false)
    readonly property bool canShuffle:   ytmActive ? false : (active?.shuffleSupported ?? false)
    readonly property bool canLoop:      ytmActive ? true  : (active?.loopSupported    ?? false)
    readonly property int  loopState: { const _ = root._tick; return active?.loopState ?? MprisLoopState.None }

    // Pause every player that's currently playing except `except`
    // (handles both MPRIS players and the YouTube Music companion).
    function _pauseOthers(except) {
        for (const p of players) {
            if (p === except) continue
            if (p === YtmCompanionService) {
                if (YtmCompanionService.playing) YtmCompanionService.playPause()
            } else if (p.playbackState === MprisPlaybackState.Playing && p.canTogglePlaying) {
                p.togglePlaying()
            }
        }
    }

    function playPause() {
        if (ytmActive) {
            if (!YtmCompanionService.playing) _pauseOthers(YtmCompanionService)   // about to start
            YtmCompanionService.playPause()
            return
        }
        if (!active?.canTogglePlaying) return
        // Starting playback → pause any other player that's currently playing
        if (active.playbackState !== MprisPlaybackState.Playing) _pauseOthers(active)
        active.togglePlaying()
    }

    // Auto-pause others when YT Music starts playing — even from the app itself
    // (the companion pushes the play state, which we watch here).
    property bool _ytmWasPlaying: false
    property Connections _ytmWatch: Connections {
        target: YtmCompanionService
        function onPlayingChanged() {
            if (YtmCompanionService.playing && !root._ytmWasPlaying)
                root._pauseOthers(YtmCompanionService)
            root._ytmWasPlaying = YtmCompanionService.playing
        }
    }

    // Auto-pause others when any MPRIS player starts playing (incl. from the app).
    // One Connections per live player; a →Playing transition pauses the rest.
    property Instantiator _mprisWatch: Instantiator {
        model: root.players
        delegate: Connections {
            required property var modelData
            target: modelData
            ignoreUnknownSignals: true   // companion sentinel has no such signal
            function onPlaybackStateChanged() {
                if (modelData !== YtmCompanionService &&
                    modelData.playbackState === MprisPlaybackState.Playing)
                    root._pauseOthers(modelData)
            }
        }
    }
    function next()      { if (ytmActive) { YtmCompanionService.next(); return }     if (active?.canGoNext)     active.next() }
    function previous()  { if (ytmActive) { YtmCompanionService.previous(); return } if (active?.canGoPrevious) active.previous() }
    function select(p)   { _selected = p; _tick++ }

    function seekTo(frac) {
        if (ytmActive) {
            if (YtmCompanionService.durationMs > 0)
                YtmCompanionService.seek(Math.max(0, Math.min(1, frac)) * YtmCompanionService.durationMs)
            _ptick++
            return
        }
        if (active && active.canSeek && active.length > 0) {
            const pos = Math.max(0, Math.min(1, frac)) * active.length
            active.position = pos
            _anchorPos = pos; _anchorMs = Date.now(); _ptick++   // optimistic jump
        }
    }
    function toggleShuffle() { if (!ytmActive && active) active.shuffle = !active.shuffle }
    function cycleLoop() {
        if (ytmActive) { YtmCompanionService.cycleRepeat(); return }
        if (!active) return
        active.loopState = active.loopState === MprisLoopState.None     ? MprisLoopState.Playlist
                         : active.loopState === MprisLoopState.Playlist ? MprisLoopState.Track
                                                                        : MprisLoopState.None
    }
    function raise() { if (ytmActive) return; if (active?.canRaise) active.raise() }

    // Format seconds → m:ss
    function fmt(sec) {
        if (!sec || sec < 0) return "0:00"
        const m = Math.floor(sec / 60)
        const s = Math.floor(sec % 60)
        return m + ":" + (s < 10 ? "0" + s : s)
    }

    // Drive position refresh + active re-pick.
    property Timer _poll: Timer {
        interval: 1000; repeat: true; running: true
        onTriggered: root._tick++
    }
}
