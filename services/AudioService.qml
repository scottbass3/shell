pragma Singleton
import QtQuick
import Quickshell.Services.Pipewire

// Owns all Pipewire bindings + control functions.
// Single authoritative reference — avoids stale-node issues from multiple
// per-component bindings created at different initialization times.
//
// CRITICAL: Pipewire.defaultAudioSink/Source return UNBOUND nodes by default.
// An unbound node reports ready=false, volume=0, and rejects volume writes
// ("PwNode ... which is not bound"). A PwObjectTracker must hold the nodes to
// bind them — only then do ready/volume/muted populate and become writable.
QtObject {
    id: root

    readonly property var sink:   Pipewire.defaultAudioSink
    readonly property var source: Pipewire.defaultAudioSource

    // All audio nodes (for device list)
    readonly property var _allNodes: Pipewire.nodes.values
    readonly property var sinks:   _allNodes ? _allNodes.filter(n => n.audio && n.isSink  && !n.isStream) : []
    readonly property var sources: _allNodes ? _allNodes.filter(n => n.audio && !n.isSink && !n.isStream) : []

    // Tracks default nodes + all audio nodes so params stay live.
    property PwObjectTracker _tracker: PwObjectTracker {
        objects: [root.sink, root.source, ...root._allNodes]
    }

    readonly property real sinkVolume:   sink?.audio?.volume   ?? 0
    readonly property bool sinkMuted:    sink?.audio?.muted    ?? false
    readonly property int  sinkVolPct:   Math.round(sinkVolume * 100)

    readonly property real sourceVolume: source?.audio?.volume ?? 0
    readonly property bool sourceMuted:  source?.audio?.muted  ?? false
    readonly property int  sourceVolPct: Math.round(sourceVolume * 100)

    // ── Output controls ───────────────────────────────────────────────────────
    function setSinkVolume(v) {
        const node = Pipewire.defaultAudioSink
        if (!node?.audio || !node.ready) return
        node.audio.volume = Math.max(0.0, Math.min(1.5, v))
        if (node.audio.muted && v > 0.01) node.audio.muted = false
    }

    function adjustSinkVolume(delta) {
        const node = Pipewire.defaultAudioSink
        if (!node?.audio || !node.ready) return
        setSinkVolume(node.audio.volume + delta)
    }

    function toggleSinkMute() {
        const node = Pipewire.defaultAudioSink
        if (node?.audio && node.ready) node.audio.muted = !node.audio.muted
    }

    // ── Input controls ────────────────────────────────────────────────────────
    function setSourceVolume(v) {
        const node = Pipewire.defaultAudioSource
        if (!node?.audio || !node.ready) return
        node.audio.volume = Math.max(0.0, Math.min(1.0, v))
        if (node.audio.muted && v > 0.01) node.audio.muted = false
    }

    function adjustSourceVolume(delta) {
        const node = Pipewire.defaultAudioSource
        if (!node?.audio || !node.ready) return
        setSourceVolume(node.audio.volume + delta)
    }

    function toggleSourceMute() {
        const node = Pipewire.defaultAudioSource
        if (node?.audio && node.ready) node.audio.muted = !node.audio.muted
    }

    function setDefaultSink(node) {
        Pipewire.preferredDefaultAudioSink = node
    }

    function setDefaultSource(node) {
        Pipewire.preferredDefaultAudioSource = node
    }
}
