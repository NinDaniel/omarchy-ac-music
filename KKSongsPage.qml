import QtQuick
import qs.Commons
import qs.Ui
import "Model.js" as Model
import "Data.js" as Data

// Every K.K. song, grouped by the game it first appeared in, with search,
// per-group tick-all, and a preview button on each song.
Column {
  id: page

  property var p
  property string query: ""

  readonly property var skip: p.cfg.kk.skip
  readonly property int tickedCount: Data.kkSongs.filter(function(s) { return skip.indexOf(s) < 0 }).length

  function matches(song) {
    var q = query.trim().toLowerCase()
    return q === "" || Model.kkTitle(song).toLowerCase().indexOf(q) >= 0
  }

  function visibleSongs(prefix) {
    return Data.kkSongs.filter(function(s) { return Model.kkGroup(s) === prefix && page.matches(s) })
  }

  width: parent ? parent.width : 0
  spacing: Style.space(10)

  PageHeader { p: page.p; title: "K.K. songs" }

  Text {
    width: parent.width
    text: "Untick songs you don't want K.K. to play. The play button previews a song now, and your music picks back up when it ends."
    color: page.p.dim
    wrapMode: Text.WordWrap
    font.family: page.p.fontFamily
    font.pixelSize: Style.font.bodySmall
  }

  Row {
    width: parent.width
    spacing: Style.space(6)

    TextField {
      id: search
      width: parent.width - allButton.width - noneButton.width - parent.spacing * 2
      placeholderText: "Search songs"
      foreground: page.p.foreground
      font.family: page.p.fontFamily
      onTextChanged: page.query = text
      Keys.onEscapePressed: function(event) {
        if (text !== "") text = ""
        else page.p.back()
        event.accepted = true
      }
    }

    Button {
      id: allButton
      anchors.verticalCenter: parent.verticalCenter
      bordered: true
      text: "All"
      tooltipText: page.query ? "Tick every song matching the search" : "Tick every song"
      foreground: page.p.foreground
      fontFamily: page.p.fontFamily
      onClicked: page.p.svc.setKKSongs(Data.kkSongs.filter(page.matches), true)
    }

    Button {
      id: noneButton
      anchors.verticalCenter: parent.verticalCenter
      bordered: true
      text: "None"
      tooltipText: page.query ? "Untick every song matching the search" : "Untick every song"
      foreground: page.p.foreground
      fontFamily: page.p.fontFamily
      onClicked: page.p.svc.setKKSongs(Data.kkSongs.filter(page.matches), false)
    }
  }

  Text {
    width: parent.width
    text: page.tickedCount === 0
      ? "Nothing ticked, so K.K. plays from every song."
      : page.tickedCount + " of " + Data.kkSongs.length + " songs ticked"
    color: page.tickedCount === 0 ? page.p.accent : page.p.dim
    font.family: page.p.fontFamily
    font.pixelSize: Style.font.bodySmall
  }

  Repeater {
    model: Model.KK_GROUPS
    delegate: Column {
      id: group
      required property var modelData
      readonly property var songs: page.visibleSongs(modelData.prefix)
      readonly property int ticked: songs.filter(function(s) { return page.skip.indexOf(s) < 0 }).length

      visible: songs.length > 0
      width: page.width
      spacing: Style.space(1)

      Row {
        spacing: Style.space(6)
        TickBox {
          p: page.p
          checked: group.ticked === group.songs.length
          partial: group.ticked > 0
          onToggled: page.p.svc.setKKSongs(group.songs, group.ticked !== group.songs.length)
        }
        Text {
          anchors.verticalCenter: parent.verticalCenter
          text: group.modelData.name.toUpperCase() + "  " + group.ticked + "/" + group.songs.length
          color: page.p.foreground
          font.family: page.p.fontFamily
          font.pixelSize: Style.font.caption
          font.bold: true
        }
      }

      Repeater {
        model: group.songs
        delegate: Item {
          id: songRow
          required property string modelData
          readonly property bool ticked: page.skip.indexOf(modelData) < 0
          readonly property bool previewing: !!page.p.svc && page.p.svc.previewSong === modelData
          width: group.width
          height: Style.space(22)

          TickBox {
            id: songBox
            anchors.left: parent.left
            anchors.leftMargin: Style.space(14)
            anchors.verticalCenter: parent.verticalCenter
            p: page.p
            checked: songRow.ticked
            onToggled: page.p.svc.setKKSongs([songRow.modelData], !songRow.ticked)
          }

          Text {
            anchors.left: songBox.right
            anchors.leftMargin: Style.space(6)
            anchors.right: previewButton.left
            anchors.verticalCenter: parent.verticalCenter
            text: Model.kkTitle(songRow.modelData)
            color: songRow.previewing ? page.p.accent : (songRow.ticked ? page.p.foreground : page.p.dim)
            elide: Text.ElideRight
            font.family: page.p.fontFamily
            font.pixelSize: Style.font.body

            MouseArea {
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              onClicked: page.p.svc.setKKSongs([songRow.modelData], !songRow.ticked)
            }
          }

          PanelActionButton {
            id: previewButton
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            size: Style.space(20)
            fontSize: Style.font.body
            iconText: songRow.previewing ? page.p.iconStop : page.p.iconPlay
            tooltipText: songRow.previewing ? "Stop preview" : "Preview"
            foreground: songRow.previewing ? page.p.accent : page.p.dim
            hoverColor: page.p.foreground
            fontFamily: page.p.fontFamily
            onClicked: page.p.svc.playPreview(songRow.modelData)
          }
        }
      }
    }
  }
}
