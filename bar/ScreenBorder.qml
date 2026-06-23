import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Wayland
import "../theme"

PanelWindow {
    id: frame

    required property var modelData

    screen:        modelData
    anchors        { top: true; bottom: true; left: true; right: true }
    // Respect exclusive zones (bar + any waybar) so this window auto-positions
    // in the usable area BELOW the bar. Reserve no space of its own.
    exclusionMode:  ExclusionMode.Normal
    exclusiveZone:  0
    color:          "transparent"

    readonly property int borderWidth: ThemeManager.borderWidth
    readonly property int innerRad:    ThemeManager.panelRadius

    // Content hole edges. Top = 0: the bar (its own window, just above) forms
    // the top edge; this frame draws sides, bottom, and rounded corners.
    readonly property int holeLeft:   borderWidth
    readonly property int holeRight:  width - borderWidth
    readonly property int holeTop:    0
    readonly property int holeBottom: height - borderWidth

    // Only the frame is clickable; the content hole passes clicks through.
    mask: Region {
        x: 0; y: 0
        width:  frame.width
        height: frame.height
        Region {
            x:      frame.holeLeft
            y:      frame.holeTop
            width:  frame.holeRight  - frame.holeLeft
            height: frame.holeBottom - frame.holeTop
            intersection: Intersection.Subtract
        }
    }

    // ── Inner shadow (gradient strips along hole edges) ───────────────────
    readonly property int _shadowLen: 20

    // Top: shadow from bar-bottom downward
    Rectangle {
        x: holeLeft; y: holeTop
        width: holeRight - holeLeft; height: frame._shadowLen
        gradient: Gradient {
            GradientStop { position: 0.0; color: "#50000000" }
            GradientStop { position: 1.0; color: "transparent" }
        }
    }
    // Left: shadow inward from left border
    Rectangle {
        x: holeLeft; y: holeTop
        width: frame._shadowLen; height: holeBottom - holeTop
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0.0; color: "#35000000" }
            GradientStop { position: 1.0; color: "transparent" }
        }
    }
    // Right: shadow inward from right border
    Rectangle {
        x: holeRight - frame._shadowLen; y: holeTop
        width: frame._shadowLen; height: holeBottom - holeTop
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0.0; color: "transparent" }
            GradientStop { position: 1.0; color: "#35000000" }
        }
    }
    // Bottom: shadow inward from bottom border
    Rectangle {
        x: holeLeft; y: holeBottom - frame._shadowLen
        width: holeRight - holeLeft; height: frame._shadowLen
        gradient: Gradient {
            GradientStop { position: 0.0; color: "transparent" }
            GradientStop { position: 1.0; color: "#35000000" }
        }
    }

    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            fillColor:   ThemeManager.surface
            strokeWidth: 0
            fillRule:    ShapePath.OddEvenFill

            // ── Outer rect: square corners, flush to screen edges ─────────
            PathMove { x: 0;           y: 0 }
            PathLine { x: frame.width; y: 0 }
            PathLine { x: frame.width; y: frame.height }
            PathLine { x: 0;           y: frame.height }
            PathLine { x: 0;           y: 0 }

            // ── Inner rounded rect (content hole, carved via OddEvenFill) ──
            PathMove { x: frame.holeLeft + frame.innerRad; y: frame.holeTop }
            PathLine { x: frame.holeRight - frame.innerRad; y: frame.holeTop }
            PathArc  { x: frame.holeRight; y: frame.holeTop + frame.innerRad
                       radiusX: frame.innerRad; radiusY: frame.innerRad }
            PathLine { x: frame.holeRight; y: frame.holeBottom - frame.innerRad }
            PathArc  { x: frame.holeRight - frame.innerRad; y: frame.holeBottom
                       radiusX: frame.innerRad; radiusY: frame.innerRad }
            PathLine { x: frame.holeLeft + frame.innerRad; y: frame.holeBottom }
            PathArc  { x: frame.holeLeft; y: frame.holeBottom - frame.innerRad
                       radiusX: frame.innerRad; radiusY: frame.innerRad }
            PathLine { x: frame.holeLeft; y: frame.holeTop + frame.innerRad }
            PathArc  { x: frame.holeLeft + frame.innerRad; y: frame.holeTop
                       radiusX: frame.innerRad; radiusY: frame.innerRad }
        }
    }
}
