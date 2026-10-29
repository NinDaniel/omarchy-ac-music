import QtQuick
import qs.Commons
import qs.Ui
import "Model.js" as Model
import "Data.js" as Data

Column {
  id: page

  property var p

  readonly property var kk: p.cfg.kk
  readonly property var concerts: kk.concerts
  readonly property var dayLetters: ["Su", "Mo", "Tu", "We", "Th", "Fr", "Sa"]

  function startOptions() {
    var out = []
    for (var h = 0; h < 24; h++) out.push({ value: String(h), label: Model.hourLabel(h) })
    return out
  }

  function endOptions() {
    var out = []
    for (var h = 1; h <= 24; h++) {
      var label = h === 24 ? "Midnight" : Model.hourLabel(h) + (h <= page.concerts.start ? " (next day)" : "")
      out.push({ value: String(h), label: label })
    }
    return out
  }

  function hoursCaption() {
    var mode = kk.between.mode
    if (mode === "off") return "When the hour changes, K.K. can play one song before that hour's music starts."
    return "K.K. plays one song as the hour changes, then that hour's music starts, a few minutes late. "
      + "It's skipped while K.K. is already on or the music is paused."
  }

  width: parent ? parent.width : 0
  spacing: Style.space(12)

  PageHeader { p: page.p; title: "K.K. Slider" }

  // ---- Concerts ----

  PanelSectionHeader { text: "CONCERTS"; foreground: page.p.foreground; fontFamily: page.p.fontFamily }

  Toggle {
    width: parent.width
    label: "Concerts"
    description: Model.concertText(page.concerts)
    checked: page.concerts.enabled
    foreground: page.p.foreground
    fontFamily: page.p.fontFamily
    onClicked: page.p.svc.setConcerts({ enabled: !page.concerts.enabled })
  }

  Row {
    visible: page.concerts.enabled
    spacing: Style.space(4)

    Repeater {
      model: 7
      delegate: Button {
        required property int index
        readonly property bool on: page.concerts.days.indexOf(index) >= 0
        text: page.dayLetters[index]
        tooltipText: Model.DAY_NAMES[index]
        selected: on
        bordered: true
        horizontalPadding: Style.space(7)
        foreground: page.p.foreground
        fontFamily: page.p.fontFamily
        onClicked: {
          var days = page.concerts.days.filter(function(d) { return d !== index })
          if (!on) days.push(index)
          page.p.svc.setConcerts({ days: days })
        }
      }
    }
  }

  Row {
    visible: page.concerts.enabled
    spacing: Style.space(8)

    Text {
      anchors.verticalCenter: parent.verticalCenter
      text: "From"
      color: page.p.dim
      font.family: page.p.fontFamily
      font.pixelSize: Style.font.body
    }

    Dropdown {
      width: Style.space(96)
      showLabel: false
      value: String(page.concerts.start)
      options: page.startOptions()
      foreground: page.p.foreground
      fontFamily: page.p.fontFamily
      onChanged: function(v) { page.p.svc.setConcerts({ start: parseInt(v, 10) }) }
    }

    Text {
      anchors.verticalCenter: parent.verticalCenter
      text: "to"
      color: page.p.dim
      font.family: page.p.fontFamily
      font.pixelSize: Style.font.body
    }

    Dropdown {
      width: Style.space(150)
      showLabel: false
      value: String(page.concerts.end)
      options: page.endOptions()
      foreground: page.p.foreground
      fontFamily: page.p.fontFamily
      onChanged: function(v) { page.p.svc.setConcerts({ end: parseInt(v, 10) }) }
    }
  }

  Toggle {
    width: parent.width
    label: "K.K. all the time"
    description: "Play K.K. Slider songs instead of the hourly music"
    checked: page.kk.always
    foreground: page.p.foreground
    fontFamily: page.p.fontFamily
    onClicked: page.p.svc.setKK({ always: !page.kk.always })
  }

  // ---- In the hourly mix ----

  PanelSectionHeader { text: "IN THE HOURLY MIX"; foreground: page.p.foreground; fontFamily: page.p.fontFamily }

  Text {
    width: parent.width
    text: {
      var n = Model.kkHourCount(page.p.cfg)
      var lead = "Tick the KK column in the Hourly music grids and Random can pick K.K. for that hour, in whichever weather you like. "
        + "With Every few minutes, he becomes one of the hour's slots. "
      return lead + (n > 0 ? "K.K. is ticked in " + n + " hour" + (n === 1 ? "" : "s") + " right now." : "He isn't ticked anywhere yet.")
    }
    color: page.p.dim
    wrapMode: Text.WordWrap
    font.family: page.p.fontFamily
    font.pixelSize: Style.font.bodySmall
  }

  Button {
    bordered: true
    text: "Open the hourly grids"
    foreground: page.p.foreground
    fontFamily: page.p.fontFamily
    onClicked: page.p.view = "hourly"
  }

  // ---- Between hours ----

  PanelSectionHeader { text: "BETWEEN HOURS"; foreground: page.p.foreground; fontFamily: page.p.fontFamily }

  Text {
    width: parent.width
    text: page.hoursCaption()
    color: page.p.dim
    wrapMode: Text.WordWrap
    font.family: page.p.fontFamily
    font.pixelSize: Style.font.bodySmall
  }

  Dropdown {
    width: Style.space(200)
    showLabel: false
    value: page.kk.between.mode
    options: [
      { value: "off", label: "Off" },
      { value: "every", label: "Every hour" },
      { value: "2", label: "Every 2 hours" },
      { value: "3", label: "Every 3 hours" },
      { value: "hours", label: "Hours I pick" }
    ]
    foreground: page.p.foreground
    fontFamily: page.p.fontFamily
    onChanged: function(v) { page.p.svc.setBetween({ mode: v }) }
  }

  Grid {
    visible: page.kk.between.mode === "hours"
    columns: 12
    columnSpacing: 0
    rowSpacing: Style.space(2)

    Repeater {
      model: 24
      delegate: Column {
        required property int index
        readonly property bool on: page.kk.between.hours.indexOf(index) >= 0
        width: page.width / 12

        Text {
          anchors.horizontalCenter: parent.horizontalCenter
          text: Model.hourLabel(index).replace(" ", "").replace("M", "").toLowerCase()
          color: page.p.dim
          font.family: page.p.fontFamily
          font.pixelSize: Style.font.caption
        }

        TickBox {
          anchors.horizontalCenter: parent.horizontalCenter
          p: page.p
          checked: parent.on
          onToggled: {
            var hours = page.kk.between.hours.filter(function(h) { return h !== index })
            if (!parent.on) hours.push(index)
            page.p.svc.setBetween({ hours: hours })
          }
        }
      }
    }
  }

  // ---- Songs ----

  PanelSectionHeader { text: "SONGS"; foreground: page.p.foreground; fontFamily: page.p.fontFamily }

  MenuRow {
    p: page.p
    title: "Choose songs"
    summary: {
      var n = Model.kkCounts(page.p.cfg, Data.kkSongs)
      return n.live + " live · " + n.aircheck + " aircheck · " + n.any + " of " + n.total + " songs can play"
    }
    onClicked: page.p.view = "kksongs"
  }
}
