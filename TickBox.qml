import QtQuick
import qs.Commons

// Small checkbox used by the hour grid and the K.K. song list. `partial`
// draws a dash for a group where only some items are ticked.
Item {
  id: box

  property var p
  property bool checked: false
  property bool partial: false
  // Read-only boxes show their state dimmed and ignore clicks.
  property bool interactive: true

  signal toggled()

  implicitWidth: Style.space(20)
  implicitHeight: Style.space(20)
  opacity: interactive ? 1.0 : 0.35

  Rectangle {
    anchors.centerIn: parent
    width: Style.space(14)
    height: width
    radius: Math.min(3, Style.cornerRadius)
    color: box.checked ? box.p.accent : (mouse.containsMouse && box.interactive ? Style.hoverFillFor(box.p.foreground, box.p.accent) : "transparent")
    border.width: box.checked ? 0 : 1
    border.color: mouse.containsMouse && box.interactive ? box.p.foreground : box.p.dim

    Rectangle {
      visible: box.partial && !box.checked
      anchors.centerIn: parent
      width: parent.width * 0.5
      height: Math.max(2, Style.space(2))
      color: box.p.accent
    }
  }

  MouseArea {
    id: mouse
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: box.interactive ? Qt.PointingHandCursor : Qt.ArrowCursor
    onClicked: if (box.interactive) box.toggled()
  }
}
