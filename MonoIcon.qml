import QtQuick
import QtQuick.Effects

// A status icon, drawn as-is or tinted to the theme color.
//
// Same trick as Omarchy's Tray.qml: MultiEffect colorization multiplies the
// source's value channel by the tint, so the pure-white masters in assets/mono/
// come out as the tint exactly. A gray pixel there would come out darkened.
//
// The image is always layered and always hidden, and only `colorization` is
// switched -- at 0.0 the effect passes the source through untouched, which is
// how assets/brand/ is drawn. Toggling layer.enabled or visible at runtime
// instead leaves the effect sampling a texture that was never rendered, and
// the icon disappears on the switch.
Item {
  id: root

  property url source
  property color tint: "#ffffff"
  property bool colorize: true

  Image {
    id: image
    anchors.fill: parent
    source: root.source
    // Decode at physical pixels so the SVG stays crisp on HiDPI.
    sourceSize.width: Math.round(Math.min(width, height) * Screen.devicePixelRatio)
    sourceSize.height: Math.round(Math.min(width, height) * Screen.devicePixelRatio)
    fillMode: Image.PreserveAspectFit
    smooth: true
    visible: false
    layer.enabled: true
  }

  MultiEffect {
    anchors.fill: image
    source: image
    colorization: root.colorize ? 1.0 : 0.0
    colorizationColor: root.tint
  }
}
