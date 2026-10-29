import QtQuick
import qs.Commons

// A row in the Settings menu: title, a one-line summary of the current
// settings on that page, and a chevron. The whole row is clickable.
Item {
  id: row

  property var p
  property string title: ""
  property string summary: ""

  signal clicked()

  width: parent ? parent.width : 0
  implicitHeight: labels.implicitHeight + Style.space(16)

  Rectangle {
    anchors.fill: parent
    radius: Style.cornerRadius
    color: mouse.containsMouse ? Style.hoverFillFor(row.p.foreground, row.p.accent) : "transparent"
    border.width: 1
    border.color: mouse.containsMouse ? Qt.darker(row.p.foreground, 1.2) : Qt.darker(row.p.foreground, 2.6)
  }

  Column {
    id: labels
    anchors.left: parent.left
    anchors.right: chevron.left
    anchors.leftMargin: Style.space(12)
    anchors.rightMargin: Style.space(8)
    anchors.verticalCenter: parent.verticalCenter
    spacing: Style.space(3)

    Text {
      text: row.title
      color: row.p.foreground
      font.family: row.p.fontFamily
      font.pixelSize: Style.font.subtitle
      font.bold: true
    }

    Text {
      width: parent.width
      text: row.summary
      visible: text !== ""
      color: row.p.dim
      wrapMode: Text.WordWrap
      font.family: row.p.fontFamily
      font.pixelSize: Style.font.bodySmall
    }
  }

  Text {
    id: chevron
    anchors.right: parent.right
    anchors.rightMargin: Style.space(12)
    anchors.verticalCenter: parent.verticalCenter
    text: row.p.iconChevron
    color: mouse.containsMouse ? row.p.foreground : row.p.dim
    font.family: row.p.fontFamily
    font.pixelSize: Style.font.title
  }

  MouseArea {
    id: mouse
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: row.clicked()
  }
}
