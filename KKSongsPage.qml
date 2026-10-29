import QtQuick
import qs.Commons
import qs.Ui
import "Model.js" as Model
import "Data.js" as Data

// Every K.K. song, grouped by the game it's credited to. Each song has a live
// and an aircheck box (with a preview for each), and each group has tick-all
// boxes for both columns. Search narrows the list.
Column {
  id: page

  property var p
  property string query: ""

  readonly property var cfg: p.cfg
  readonly property var counts: Model.kkCounts(cfg, Data.kkSongs)
  readonly property real columnWidth: Style.space(46)
  // Small breathing room on the right; the panel itself keeps a lane
  // clear for its scroll bar.
  readonly property real rightInset: Style.space(4)

  function matches(song) {
    var q = query.trim().toLowerCase()
    return q === "" || Model.kkTitle(song).toLowerCase().indexOf(q) >= 0
  }

  function visibleSongs(prefix) {
    return Data.kkSongs.filter(function(s) { return Model.kkGroup(s) === prefix && page.matches(s) })
  }

  function keys(songs, version) {
    return songs.map(function(s) { return Model.kkKey(version, s) })
  }

  function onCount(songs, version) {
    return songs.filter(function(s) { return Model.kkOn(page.cfg, version, s) }).length
  }

  width: parent ? parent.width : 0
  spacing: Style.space(10)

  PageHeader { p: page.p; title: "K.K. songs" }

  Text {
    width: parent.width
    text: "Tick the live (L) and aircheck (A) versions K.K. may play. When a song has both ticked, he picks either. "
      + "The play buttons preview a version now, and your music picks back up when it ends."
    color: page.p.dim
    wrapMode: Text.WordWrap
    font.family: page.p.fontFamily
    font.pixelSize: Style.font.bodySmall
  }

  TextField {
    width: parent.width
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

  Row {
    spacing: Style.space(6)

    Button {
      bordered: true
      text: "All live"
      tooltipText: page.query ? "Tick the live version of every matching song" : "Tick the live version of every song"
      foreground: page.p.foreground
      fontFamily: page.p.fontFamily
      onClicked: page.p.svc.setKKSongs(page.keys(Data.kkSongs.filter(page.matches), "live"), true)
    }

    Button {
      bordered: true
      text: "All aircheck"
      tooltipText: page.query ? "Tick the aircheck version of every matching song" : "Tick the aircheck version of every song"
      foreground: page.p.foreground
      fontFamily: page.p.fontFamily
      onClicked: page.p.svc.setKKSongs(page.keys(Data.kkSongs.filter(page.matches), "aircheck"), true)
    }

    Button {
      bordered: true
      text: "None"
      tooltipText: page.query ? "Untick both versions of every matching song" : "Untick everything"
      foreground: page.p.foreground
      fontFamily: page.p.fontFamily
      onClicked: {
        var songs = Data.kkSongs.filter(page.matches)
        page.p.svc.setKKSongs(page.keys(songs, "live").concat(page.keys(songs, "aircheck")), false)
      }
    }
  }

  Text {
    width: parent.width
    text: page.counts.any === 0
      ? "Nothing ticked, so K.K. plays from every song."
      : page.counts.live + " live · " + page.counts.aircheck + " aircheck · " + page.counts.any + " of " + page.counts.total + " songs can play"
    color: page.counts.any === 0 ? page.p.accent : page.p.dim
    font.family: page.p.fontFamily
    font.pixelSize: Style.font.bodySmall
  }

  // Column headings, lined up with the boxes below.
  Item {
    width: parent.width
    height: liveHeading.implicitHeight

    Text {
      id: liveHeading
      x: parent.width - page.rightInset - page.columnWidth * 2
      width: page.columnWidth
      horizontalAlignment: Text.AlignHCenter
      text: "LIVE"
      color: page.p.dim
      font.family: page.p.fontFamily
      font.pixelSize: Style.font.caption
      font.bold: true
    }

    Text {
      x: parent.width - page.rightInset - page.columnWidth
      width: page.columnWidth
      horizontalAlignment: Text.AlignHCenter
      text: "AIRCHECK"
      color: page.p.dim
      font.family: page.p.fontFamily
      font.pixelSize: Style.font.caption
      font.bold: true
    }
  }

  Repeater {
    model: Model.KK_GROUPS
    delegate: Column {
      id: group
      required property var modelData
      readonly property var songs: page.visibleSongs(modelData.prefix)
      readonly property int liveOn: page.onCount(songs, "live")
      readonly property int aircheckOn: page.onCount(songs, "aircheck")

      visible: songs.length > 0
      width: page.width
      spacing: Style.space(1)

      Item {
        width: parent.width
        height: Style.space(22)

        Text {
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          text: group.modelData.name.toUpperCase() + "  " + group.songs.length
          color: page.p.foreground
          font.family: page.p.fontFamily
          font.pixelSize: Style.font.caption
          font.bold: true
        }

        Repeater {
          model: Model.KK_VERSIONS
          delegate: Item {
            required property string modelData
            required property int index
            readonly property int on: modelData === "live" ? group.liveOn : group.aircheckOn
            x: parent.width - page.rightInset - page.columnWidth * (2 - index)
            width: page.columnWidth
            height: parent.height

            TickBox {
              anchors.left: parent.left
              anchors.leftMargin: Style.space(4)
              anchors.verticalCenter: parent.verticalCenter
              p: page.p
              checked: parent.on === group.songs.length
              partial: parent.on > 0
              onToggled: page.p.svc.setKKSongs(page.keys(group.songs, parent.modelData), parent.on !== group.songs.length)
            }
          }
        }
      }

      Repeater {
        model: group.songs
        delegate: Item {
          id: songRow
          required property string modelData
          readonly property bool anyOn: Model.kkVersionsFor(page.cfg, modelData).length > 0
          width: group.width
          height: Style.space(22)

          Text {
            anchors.left: parent.left
            anchors.leftMargin: Style.space(10)
            anchors.right: parent.right
            anchors.rightMargin: page.rightInset + page.columnWidth * 2 + Style.space(4)
            anchors.verticalCenter: parent.verticalCenter
            text: Model.kkTitle(songRow.modelData)
            color: page.p.svc && page.p.svc.previewSong === songRow.modelData ? page.p.accent
              : (songRow.anyOn ? page.p.foreground : page.p.dim)
            elide: Text.ElideRight
            font.family: page.p.fontFamily
            font.pixelSize: Style.font.body
          }

          Repeater {
            model: Model.KK_VERSIONS
            delegate: Item {
              id: versionCell
              required property string modelData
              required property int index
              readonly property bool on: Model.kkOn(page.cfg, modelData, songRow.modelData)
              readonly property bool previewing: !!page.p.svc && page.p.svc.previewSong === songRow.modelData
                && page.p.svc.previewVersion === modelData
              x: songRow.width - page.rightInset - page.columnWidth * (2 - index)
              width: page.columnWidth
              height: songRow.height

              TickBox {
                id: versionBox
                anchors.left: parent.left
                anchors.leftMargin: Style.space(4)
                anchors.verticalCenter: parent.verticalCenter
                p: page.p
                checked: versionCell.on
                onToggled: page.p.svc.setKKSongs([Model.kkKey(versionCell.modelData, songRow.modelData)], !versionCell.on)
              }

              PanelActionButton {
                anchors.left: versionBox.right
                anchors.verticalCenter: parent.verticalCenter
                size: Style.space(20)
                fontSize: Style.font.bodySmall
                iconText: versionCell.previewing ? page.p.iconStop : page.p.iconPlay
                tooltipText: (versionCell.previewing ? "Stop " : "Preview ") + Model.versionName(versionCell.modelData).toLowerCase()
                foreground: versionCell.previewing ? page.p.accent : page.p.dim
                hoverColor: page.p.foreground
                fontFamily: page.p.fontFamily
                onClicked: page.p.svc.playPreview(songRow.modelData, versionCell.modelData)
              }
            }
          }
        }
      }
    }
  }
}
