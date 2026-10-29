import QtQuick
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Twelve hours x four games of checkboxes for one weather's grid. Clicking an
// hour flips its row; clicking a game heading flips its column (these twelve
// hours only).
Column {
  id: table

  property var p
  property string weatherId: "sunny"
  property int firstHour: 0

  readonly property var grid: p.cfg.hours[weatherId]
  readonly property var hourList: {
    var list = []
    for (var h = firstHour; h < firstHour + 12; h++) list.push(h)
    return list
  }
  readonly property real labelWidth: Style.space(48)
  readonly property real cellWidth: (width - labelWidth) / Model.GAMES.length

  spacing: Style.space(2)

  Row {
    Item { width: table.labelWidth; height: 1 }
    Repeater {
      model: Model.GAMES
      delegate: Text {
        id: heading
        required property var modelData
        width: table.cellWidth
        horizontalAlignment: Text.AlignHCenter
        text: modelData.short
        color: headerMouse.containsMouse ? table.p.foreground : table.p.dim
        font.family: table.p.fontFamily
        font.pixelSize: Style.font.caption
        font.bold: true

        MouseArea {
          id: headerMouse
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: {
            var g = heading.modelData.id
            var allOn = table.hourList.every(function(h) { return table.grid[String(h)].indexOf(g) >= 0 })
            table.p.svc.setHoursGames(table.weatherId, table.hourList, [g], !allOn)
          }
        }

        PanelToolTip {
          visible: headerMouse.containsMouse
          text: heading.modelData.id === "animal-crossing" && table.weatherId === "raining"
            ? "GameCube has no rain music: ticking it here allows its sunny track on rainy days"
            : heading.modelData.tooltip
        }
      }
    }
  }

  Repeater {
    model: table.hourList
    delegate: Row {
      id: hourRow
      required property int modelData
      readonly property bool isNow: !!table.p.svc && table.p.svc.hour === modelData

      Text {
        width: table.labelWidth
        height: Style.space(20)
        verticalAlignment: Text.AlignVCenter
        text: Model.hourLabel(hourRow.modelData)
        color: hourRow.isNow ? table.p.accent : (hourMouse.containsMouse ? table.p.foreground : table.p.dim)
        font.family: table.p.fontFamily
        font.pixelSize: Style.font.bodySmall
        font.bold: hourRow.isNow

        MouseArea {
          id: hourMouse
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: {
            var h = hourRow.modelData
            var allOn = table.grid[String(h)].length === Model.GAME_IDS.length
            table.p.svc.setHoursGames(table.weatherId, [h], Model.GAME_IDS, !allOn)
          }
        }
      }

      Repeater {
        model: Model.GAMES
        delegate: Item {
          id: cell
          required property var modelData
          readonly property bool checked: table.grid[String(hourRow.modelData)].indexOf(modelData.id) >= 0
          width: table.cellWidth
          height: Style.space(20)

          TickBox {
            anchors.centerIn: parent
            p: table.p
            checked: cell.checked
            onToggled: table.p.svc.setHoursGames(table.weatherId, [hourRow.modelData], [cell.modelData.id], !cell.checked)
          }
        }
      }
    }
  }
}
