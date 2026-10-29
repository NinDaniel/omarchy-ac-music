import QtQuick
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Twelve hours of checkboxes for one weather's grid: the four games plus K.K.
// Clicking an hour flips its row; clicking a heading flips that column (these
// twelve hours only). On the Rain tab the GameCube column is read-only: that
// game has no rain music, so it follows the Sunny grid.
Column {
  id: table

  property var p
  property string weatherId: "sunny"
  property int firstHour: 0

  readonly property var hourList: {
    var list = []
    for (var h = firstHour; h < firstHour + 12; h++) list.push(h)
    return list
  }
  readonly property real labelWidth: Style.space(44)
  readonly property real cellWidth: (width - labelWidth) / Model.GRID_COLUMNS.length

  function mirrored(id) {
    return weatherId === "raining" && id === "animal-crossing"
  }

  function isTicked(hour, id) {
    return Model.ticked(table.p.cfg, weatherId, hour, id)
  }

  // Columns a row click flips (everything except a mirrored column).
  readonly property var editableIds: Model.GRID_IDS.filter(function(id) { return !table.mirrored(id) })

  spacing: Style.space(2)

  Row {
    Item { width: table.labelWidth; height: 1 }
    Repeater {
      model: Model.GRID_COLUMNS
      delegate: Text {
        id: heading
        required property var modelData
        readonly property bool mirrored: table.mirrored(modelData.id)
        width: table.cellWidth
        horizontalAlignment: Text.AlignHCenter
        text: modelData.short
        opacity: mirrored ? 0.5 : 1.0
        color: headerMouse.containsMouse && !mirrored ? table.p.foreground
          : (modelData.id === Model.KK_ID ? table.p.accent : table.p.dim)
        font.family: table.p.fontFamily
        font.pixelSize: Style.font.caption
        font.bold: true

        MouseArea {
          id: headerMouse
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: heading.mirrored ? Qt.ArrowCursor : Qt.PointingHandCursor
          onClicked: {
            if (heading.mirrored) return
            var g = heading.modelData.id
            var allOn = table.hourList.every(function(h) { return table.isTicked(h, g) })
            table.p.svc.setHoursGames(table.weatherId, table.hourList, [g], !allOn)
          }
        }

        PanelToolTip {
          visible: headerMouse.containsMouse
          text: heading.mirrored
            ? "GameCube has no rain music, so on rainy days it follows your Sunny grid"
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
            var allOn = table.editableIds.every(function(id) { return table.isTicked(h, id) })
            table.p.svc.setHoursGames(table.weatherId, [h], table.editableIds, !allOn)
          }
        }
      }

      Repeater {
        model: Model.GRID_COLUMNS
        delegate: Item {
          id: cell
          required property var modelData
          readonly property bool checked: table.isTicked(hourRow.modelData, modelData.id)
          width: table.cellWidth
          height: Style.space(20)

          TickBox {
            anchors.centerIn: parent
            p: table.p
            checked: cell.checked
            interactive: !table.mirrored(cell.modelData.id)
            onToggled: table.p.svc.setHoursGames(table.weatherId, [hourRow.modelData], [cell.modelData.id], !cell.checked)
          }
        }
      }
    }
  }
}
