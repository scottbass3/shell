import QtQuick
import QtQuick.Effects

// Reusable Material elevation shadow. Use as:
//   SomeRectangle { layer.enabled: true; layer.effect: Elevation {} }
// Optionally override `level` (1..5) for stronger/weaker elevation.
MultiEffect {
    property int level: 3        // M3 elevation level

    shadowEnabled:          true
    shadowColor:            Qt.rgba(0, 0, 0, 0.10 + level * 0.07)
    shadowBlur:             Math.min(1.0, 0.25 + level * 0.18)
    blurMax:                64
    shadowVerticalOffset:   level * 2
    shadowHorizontalOffset: 0
    autoPaddingEnabled:     true
}
