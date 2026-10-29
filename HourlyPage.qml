import QtQuick
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Which games Random may pick for each hour (one grid per weather), and how
// often Random picks.
Column {
  id: page

  property var p
  // Grid being edited; opens on whatever the weather is right now.
  property string gridWeather: p.svc ? p.svc.weather : "sunny"
  property bool copied: false
  // Custom shuffle interval picked (keeps the minutes field showing even
  // when the value happens to match a preset).
  property bool customShuffle: false
  readonly property var shufflePresets: [10, 15, 30]
  readonly property bool intervalMode: p.cfg.randomMode === "interval"
  readonly property bool showMinutes: customShuffle || shufflePresets.indexOf(p.cfg.shuffleMinutes) < 0

  width: parent ? parent.width : 0
  spacing: Style.space(12)

  Component.onCompleted: gridWeather = p.svc ? p.svc.weather : "sunny"

  function randomModeCaption() {
    if (p.cfg.randomMode === "daily")
      return "One game plays all day, so you might get New Leaf from midnight to midnight. "
        + "If that game is unticked for an hour above, that hour picks from its ticked games instead."
    if (p.cfg.randomMode === "interval")
      return "Every few minutes it switches to a different game's version of the current hour's song. Choose how often:"
    return "Each hour picks a game from the ones ticked for it above."
  }

  PageHeader { p: page.p; title: "Hourly music" }

  Text {
    visible: page.p.cfg.game !== "random"
    width: parent.width
    text: "These settings shape Random. Right now " + Model.gameName(page.p.cfg.game)
      + " is picked on the main panel, so you hear all of it."
    color: page.p.accent
    wrapMode: Text.WordWrap
    font.family: page.p.fontFamily
    font.pixelSize: Style.font.bodySmall
  }

  PanelSectionHeader { text: "WHICH GAMES CAN PLAY"; foreground: page.p.foreground; fontFamily: page.p.fontFamily }

  Text {
    width: parent.width
    text: "Each weather has its own grid, so you can keep New Leaf's rainy 11 AM and skip its sunny one. "
      + "Tick KK to let Random pick K.K. Slider for that hour. "
      + "Click a box for one game and hour, an hour to flip its row, or a heading to flip its column."
    color: page.p.dim
    wrapMode: Text.WordWrap
    font.family: page.p.fontFamily
    font.pixelSize: Style.font.bodySmall
  }

  ButtonGroup {
    spacing: Style.space(6)
    value: page.gridWeather
    foreground: page.p.foreground
    fontFamily: page.p.fontFamily
    focusable: false
    options: [
      { value: "sunny", label: "Sunny", icon: page.p.iconSun },
      { value: "raining", label: "Rain", icon: page.p.iconRain },
      { value: "snowing", label: "Snow", icon: page.p.iconSnow }
    ]
    onChanged: function(v) { page.gridWeather = v; page.copied = false }
  }

  Row {
    width: parent.width
    spacing: Style.space(16)

    HourTable { p: page.p; weatherId: page.gridWeather; firstHour: 0; width: (parent.width - parent.spacing) / 2 }
    HourTable { p: page.p; weatherId: page.gridWeather; firstHour: 12; width: (parent.width - parent.spacing) / 2 }
  }

  Text {
    visible: page.gridWeather === "raining"
    width: parent.width
    text: "GameCube has no rain music, so on rainy days it follows your Sunny grid. Its column here just shows that."
    color: page.p.dim
    wrapMode: Text.WordWrap
    font.family: page.p.fontFamily
    font.pixelSize: Style.font.bodySmall
  }

  Button {
    bordered: true
    text: page.copied ? "Copied to the other weathers" : "Copy this grid to the other weathers"
    tooltipText: "Make the " + Model.weatherName(page.gridWeather).toLowerCase() + " grid the grid for every weather"
    foreground: page.p.foreground
    fontFamily: page.p.fontFamily
    onClicked: {
      page.p.svc.copyGridToAll(page.gridWeather)
      page.copied = true
    }
  }

  PanelSeparator { width: parent.width; foreground: page.p.foreground }

  PanelSectionHeader { text: "RANDOM PICKS"; foreground: page.p.foreground; fontFamily: page.p.fontFamily }

  ButtonGroup {
    spacing: Style.space(6)
    value: page.p.cfg.randomMode
    foreground: page.p.foreground
    fontFamily: page.p.fontFamily
    focusable: false
    options: [
      { value: "hourly", label: "Every hour", tooltip: "A new game each hour" },
      { value: "daily", label: "Once a day", tooltip: "One game all day, from midnight to midnight" },
      { value: "interval", label: "Every few minutes", tooltip: "Switch between games' versions of this hour's song" }
    ]
    onChanged: function(v) { page.p.svc.update({ randomMode: v }) }
  }

  Text {
    width: parent.width
    text: page.randomModeCaption()
    color: page.p.dim
    wrapMode: Text.WordWrap
    font.family: page.p.fontFamily
    font.pixelSize: Style.font.bodySmall
  }

  ButtonGroup {
    visible: page.intervalMode
    spacing: Style.space(6)
    value: page.showMinutes ? "custom" : String(page.p.cfg.shuffleMinutes)
    foreground: page.p.foreground
    fontFamily: page.p.fontFamily
    focusable: false
    options: page.shufflePresets.map(function(m) { return { value: String(m), label: m + " min" } })
      .concat([{ value: "custom", label: "Custom" }])
    onChanged: function(v) {
      if (v === "custom") {
        page.customShuffle = true
        return
      }
      page.customShuffle = false
      page.p.svc.update({ shuffleMinutes: parseInt(v, 10) })
    }
  }

  NumberField {
    visible: page.intervalMode && page.showMinutes
    label: "Minutes between switches"
    from: 1
    to: 60
    value: page.p.cfg.shuffleMinutes
    foreground: page.p.foreground
    fontFamily: page.p.fontFamily
    onModified: function(v) { page.p.svc.update({ shuffleMinutes: v }) }
  }
}
