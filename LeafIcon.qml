import QtQuick
import QtQuick.Shapes

// The leaf, drawn on a 24x24 grid: a rounded leaf body with its center vein
// cut out, plus a short stem, tilted like the Animal Crossing logo.
Item {
  id: root

  property real iconSize: 16
  property color color: "white"

  width: iconSize
  height: iconSize
  implicitWidth: iconSize
  implicitHeight: iconSize

  Shape {
    anchors.centerIn: parent
    width: 24
    height: 24
    scale: root.iconSize / 24
    rotation: 28
    antialiasing: true
    layer.enabled: true
    layer.samples: 4
    preferredRendererType: Shape.CurveRenderer

    ShapePath {
      fillColor: root.color
      strokeWidth: 0
      fillRule: ShapePath.OddEvenFill
      PathSvg {
        path: "M12 1.5 C17.5 5.5 20.5 10.5 19 15.5 C18 19 15 20.6 12 20.6 C9 20.6 6 19 5 15.5 C3.5 10.5 6.5 5.5 12 1.5 Z "
          + "M11.25 6.5 L12.75 6.5 L12.75 18.6 L11.25 18.6 Z"
      }
    }

    ShapePath {
      fillColor: root.color
      strokeWidth: 0
      PathSvg { path: "M11.2 20.4 L12.8 20.4 L12.8 23.5 L11.2 23.5 Z" }
    }
  }
}
