import QtQuick
import qs.Commons
import qs.Ui

// Back arrow + page title at the top of every settings page.
Row {
  id: header

  property var p
  property string title: ""

  spacing: Style.space(8)

  PanelActionButton {
    anchors.verticalCenter: parent.verticalCenter
    iconText: header.p.iconBack
    tooltipText: "Back"
    foreground: header.p.foreground
    fontFamily: header.p.fontFamily
    onClicked: header.p.back()
  }

  Text {
    anchors.verticalCenter: parent.verticalCenter
    text: header.title
    color: header.p.foreground
    font.family: header.p.fontFamily
    font.pixelSize: Style.font.title
    font.bold: true
  }
}
