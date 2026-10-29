import QtQuick
import QtQuick.Controls
import Quickshell
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "Model.js" as Model
import "bridge" as AcBridge

// Bar widget: the leaf icon plus its popup. One of these exists per bar
// (per monitor); all of them drive the single Service instance.
Panel {
  id: root
  moduleName: "danr.ac-music"
  // One widget per monitor, so no per-widget IPC target; the service owns
  // "danr.ac-music" and `omarchy-shell shell toggle danr.ac-music` opens this.
  manageIpc: false

  readonly property var svc: {
    var viaHost = bar && bar.shell && typeof bar.shell.serviceFor === "function"
      ? bar.shell.serviceFor("danr.ac-music") : null
    return viaHost || AcBridge.Bridge.service
  }
  readonly property var cfg: svc ? svc.config : Model.defaultConfig()
  readonly property bool playing: !!svc && svc.playing
  readonly property bool audible: !!svc && svc.audible
  readonly property bool held: !!svc && svc.otherMediaHold && cfg.otherMedia !== "ignore"

  readonly property color foreground: bar ? bar.foreground : Commons.Color.foreground
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property color accent: Commons.Color.accent
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  // "main" or "settings"
  property string view: "main"
  // Custom shuffle interval picked (shows the minutes field even when the
  // value happens to match a preset).
  property bool customShuffle: false
  readonly property var shufflePresets: [10, 15, 30]

  readonly property string iconSun: String.fromCodePoint(0xF0599)
  readonly property string iconRain: String.fromCodePoint(0xF0597)
  readonly property string iconSnow: String.fromCodePoint(0xF0598)
  readonly property string iconAuto: String.fromCodePoint(0xF0595)
  readonly property string iconVolume: String.fromCodePoint(0xF057E)
  readonly property string iconShuffle: String.fromCodePoint(0xF049D)
  readonly property string iconSkip: String.fromCodePoint(0xF04AD)
  readonly property string iconCog: String.fromCodePoint(0xF0493)
  readonly property string iconBack: String.fromCodePoint(0xF0141)

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onOpenedChanged: if (opened) {
    view = svc && svc.requestedView ? svc.requestedView : "main"
    if (svc) svc.requestedView = ""
    if (panelFlick) panelFlick.contentY = 0
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }
  onViewChanged: if (panelFlick) panelFlick.contentY = 0

  function holdText() {
    if (!svc) return ""
    var verb = cfg.otherMedia === "lower" ? "Quieter" : "Paused"
    return verb + " while " + svc.otherMediaName + " plays"
  }

  function weatherCaption() {
    if (!svc) return ""
    if (cfg.weather !== "auto") return "Weather locked to " + Model.weatherName(cfg.weather).toLowerCase()
    if (!svc.liveWeather) return "Checking the weather…"
    var place = svc.weatherPlace ? " in " + svc.weatherPlace : ""
    var text = Model.weatherName(svc.liveWeather) + place
    if (svc.game === "animal-crossing" && svc.liveWeather === "raining" && !svc.kkActive)
      text += " (the GameCube game has no rain music)"
    return text
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    tooltipText: root.svc ? (root.playing ? (root.held ? root.holdText() + " · " : "") : "Paused · ") + root.svc.title + " · " + root.svc.subtitle : "AC Hourly Music"
    iconComponent: Component {
      Item {
        LeafIcon {
          anchors.centerIn: parent
          iconSize: Style.space(15)
          color: root.barForeground
          opacity: root.audible && !root.svc.heldQuiet ? 1.0 : 0.45
        }
      }
    }
    onPressed: function(buttonCode) {
      if (!root.svc) return
      if (buttonCode === Qt.RightButton) root.svc.togglePlaying()
      else if (buttonCode === Qt.MiddleButton) root.svc.next()
      else root.toggle()
    }
    onWheelMoved: function(delta) {
      if (root.svc) root.svc.nudgeVolume(delta > 0 ? 0.05 : -0.05)
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(400))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(620))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: {
        if (root.view !== "main") root.view = "main"
        else root.close()
      }
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) {
        if (!root.svc) return
        if (t === "p" || t === " ") root.svc.togglePlaying()
        else if (t === "n") root.svc.next()
        else if (t === "s") root.view = root.view === "main" ? "settings" : "main"
      }

      Flickable {
        id: panelFlick
        anchors.fill: parent
        contentWidth: width
        contentHeight: column.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Column {
          id: column
          width: panelFlick.width
          spacing: Style.space(12)

          // ================= Main view =================

          PanelHero {
            id: hero
            visible: root.view === "main"
            width: parent.width
            title: root.svc ? root.svc.title : "AC Hourly Music"
            meta: root.svc ? root.svc.subtitle : "Starting…"
            detail: !root.playing ? "Paused" : (root.held ? "On hold" : "")
            foreground: root.foreground
            fontFamily: root.fontFamily
            iconOpacity: root.audible ? 1.0 : 0.5
            iconComponent: Component {
              LeafIcon {
                iconSize: Style.font.display * 1.3
                color: root.accent
              }
            }
            trailingControl: Component {
              ToggleSwitch {
                checked: root.playing
                foreground: hero.foreground
                onToggled: if (root.svc) root.svc.togglePlaying()
              }
            }
          }

          Row {
            visible: root.view === "main"
            width: parent.width
            spacing: Style.space(10)

            Text {
              id: volumeIcon
              anchors.verticalCenter: parent.verticalCenter
              text: root.iconVolume
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.title
            }

            PanelSlider {
              anchors.verticalCenter: parent.verticalCenter
              width: parent.width - volumeIcon.width - volumeLabel.width - parent.spacing * 2
              bar: root.bar
              minimum: 0
              maximum: 1
              step: 0.05
              value: root.cfg.volume
              onMoved: function(v) { if (root.svc) root.svc.setVolume(v) }
            }

            Text {
              id: volumeLabel
              anchors.verticalCenter: parent.verticalCenter
              width: Style.space(34)
              horizontalAlignment: Text.AlignRight
              text: Math.round(root.cfg.volume * 100) + "%"
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
            }
          }

          PanelSeparator { visible: root.view === "main"; width: parent.width; foreground: root.foreground }

          PanelSectionHeader { visible: root.view === "main"; text: "GAME"; foreground: root.foreground; fontFamily: root.fontFamily }

          ButtonGroup {
            visible: root.view === "main"
            spacing: Style.space(6)
            value: root.cfg.game
            foreground: root.foreground
            fontFamily: root.fontFamily
            focusable: false
            options: Model.GAMES.map(function(g) {
              return { value: g.id, label: g.short, tooltip: g.tooltip }
            }).concat([{ value: "random", label: "Random", tooltip: "A different game each hour (or day), from the ones you tick in Settings" }])
            onChanged: function(v) { if (root.svc) root.svc.setGame(v) }
          }

          PanelSectionHeader { visible: root.view === "main"; text: "WEATHER"; foreground: root.foreground; fontFamily: root.fontFamily }

          ButtonGroup {
            visible: root.view === "main"
            spacing: Style.space(6)
            value: root.cfg.weather
            foreground: root.foreground
            fontFamily: root.fontFamily
            focusable: false
            options: [
              { value: "auto", label: "Auto", icon: root.iconAuto, tooltip: "Follow the real weather where you are" },
              { value: "sunny", label: "Sunny", icon: root.iconSun },
              { value: "raining", label: "Rain", icon: root.iconRain },
              { value: "snowing", label: "Snow", icon: root.iconSnow }
            ]
            onChanged: function(v) { if (root.svc) root.svc.setWeather(v) }
          }

          Text {
            visible: root.view === "main" && text !== ""
            width: parent.width
            text: root.weatherCaption()
            color: root.dim
            wrapMode: Text.WordWrap
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
          }

          Text {
            visible: root.view === "main" && root.playing && root.held
            width: parent.width
            text: root.holdText() + ". It comes back on its own when that stops."
            color: root.accent
            wrapMode: Text.WordWrap
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
          }

          Text {
            visible: root.view === "main" && !!root.svc && root.svc.lastError !== ""
            width: parent.width
            text: root.svc ? root.svc.lastError + ". Retrying shortly." : ""
            color: root.bar ? root.bar.urgent : Commons.Color.urgent
            wrapMode: Text.WordWrap
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
          }

          PanelSeparator { visible: root.view === "main"; width: parent.width; foreground: root.foreground }

          Item {
            visible: root.view === "main"
            width: parent.width
            height: settingsButton.implicitHeight

            Button {
              visible: !!root.svc && (root.svc.kkActive || root.cfg.game === "random")
              anchors.left: parent.left
              bordered: true
              iconText: root.svc && root.svc.kkActive ? root.iconSkip : root.iconShuffle
              text: root.svc && root.svc.kkActive ? "Next song" : "Shuffle game"
              tooltipText: root.svc && root.svc.kkActive ? "Skip to another K.K. song" : "Pick a different game for this hour"
              foreground: root.foreground
              fontFamily: root.fontFamily
              onClicked: root.svc.next()
            }

            Button {
              id: settingsButton
              anchors.right: parent.right
              bordered: true
              iconText: root.iconCog
              text: "Settings"
              foreground: root.foreground
              fontFamily: root.fontFamily
              onClicked: root.view = "settings"
            }
          }

          // ================= Settings view =================

          Row {
            visible: root.view === "settings"
            spacing: Style.space(8)

            PanelActionButton {
              anchors.verticalCenter: parent.verticalCenter
              iconText: root.iconBack
              tooltipText: "Back"
              foreground: root.foreground
              fontFamily: root.fontFamily
              onClicked: root.view = "main"
            }

            Text {
              anchors.verticalCenter: parent.verticalCenter
              text: "Settings"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.title
              font.bold: true
            }
          }

          PanelSectionHeader { visible: root.view === "settings"; text: "HOURLY GAMES"; foreground: root.foreground; fontFamily: root.fontFamily }

          Text {
            visible: root.view === "settings"
            width: parent.width
            text: "When the game is set to Random, each hour only picks from the games ticked here. Click an hour or a game heading to flip the whole row or column."
            color: root.dim
            wrapMode: Text.WordWrap
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
          }

          Row {
            visible: root.view === "settings"
            width: parent.width
            spacing: Style.space(16)

            HourTable { firstHour: 0; width: (parent.width - parent.spacing) / 2 }
            HourTable { firstHour: 12; width: (parent.width - parent.spacing) / 2 }
          }

          PanelSectionHeader { visible: root.view === "settings"; text: "RANDOM PICKS"; foreground: root.foreground; fontFamily: root.fontFamily }

          ButtonGroup {
            visible: root.view === "settings"
            spacing: Style.space(6)
            value: root.cfg.randomMode
            foreground: root.foreground
            fontFamily: root.fontFamily
            focusable: false
            options: [
              { value: "hourly", label: "Every hour" },
              { value: "daily", label: "Once a day" },
              { value: "interval", label: "Every few minutes", tooltip: "Switch to a different game's version of this hour's song" }
            ]
            onChanged: function(v) { if (root.svc) root.svc.update({ randomMode: v }) }
          }

          ButtonGroup {
            visible: root.view === "settings" && root.cfg.randomMode === "interval"
            spacing: Style.space(6)
            value: root.customShuffle || root.shufflePresets.indexOf(root.cfg.shuffleMinutes) < 0 ? "custom" : String(root.cfg.shuffleMinutes)
            foreground: root.foreground
            fontFamily: root.fontFamily
            focusable: false
            options: root.shufflePresets.map(function(m) { return { value: String(m), label: m + " min" } })
              .concat([{ value: "custom", label: "Custom" }])
            onChanged: function(v) {
              if (v === "custom") {
                root.customShuffle = true
                return
              }
              root.customShuffle = false
              if (root.svc) root.svc.update({ shuffleMinutes: parseInt(v, 10) })
            }
          }

          NumberField {
            visible: root.view === "settings" && root.cfg.randomMode === "interval"
              && (root.customShuffle || root.shufflePresets.indexOf(root.cfg.shuffleMinutes) < 0)
            label: "Minutes between switches"
            from: 1
            to: 60
            value: root.cfg.shuffleMinutes
            foreground: root.foreground
            fontFamily: root.fontFamily
            onModified: function(v) { if (root.svc) root.svc.update({ shuffleMinutes: v }) }
          }

          Text {
            visible: root.view === "settings" && root.cfg.randomMode === "interval" && root.cfg.game !== "random"
            width: parent.width
            text: "Switches only happen while the game is set to Random."
            color: root.dim
            wrapMode: Text.WordWrap
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
          }

          PanelSectionHeader { visible: root.view === "settings"; text: "K.K. SLIDER"; foreground: root.foreground; fontFamily: root.fontFamily }

          Toggle {
            visible: root.view === "settings"
            width: parent.width
            label: "Saturday night concerts"
            description: "K.K. takes over on Saturdays from 8 PM until midnight"
            checked: root.cfg.kk.saturday
            foreground: root.foreground
            fontFamily: root.fontFamily
            onClicked: root.svc.setKK({ saturday: !root.cfg.kk.saturday })
          }

          Toggle {
            visible: root.view === "settings"
            width: parent.width
            label: "K.K. all the time"
            description: "Play K.K. Slider songs instead of the hourly music"
            checked: root.cfg.kk.always
            foreground: root.foreground
            fontFamily: root.fontFamily
            onClicked: root.svc.setKK({ always: !root.cfg.kk.always })
          }

          ButtonGroup {
            visible: root.view === "settings"
            spacing: Style.space(6)
            value: root.cfg.kk.version
            foreground: root.foreground
            fontFamily: root.fontFamily
            focusable: false
            options: [
              { value: "live", label: "Live", tooltip: "K.K. performing with his guitar" },
              { value: "aircheck", label: "Aircheck", tooltip: "The full-band radio versions" },
              { value: "both", label: "Both" }
            ]
            onChanged: function(v) { if (root.svc) root.svc.setKK({ version: v }) }
          }

          PanelSectionHeader { visible: root.view === "settings"; text: "PLAYBACK"; foreground: root.foreground; fontFamily: root.fontFamily }

          Toggle {
            visible: root.view === "settings"
            width: parent.width
            label: "Fade between tracks"
            description: "Fade out the old song when the hour or weather changes"
            checked: root.cfg.fade
            foreground: root.foreground
            fontFamily: root.fontFamily
            onClicked: root.svc.update({ fade: !root.cfg.fade })
          }

          Toggle {
            visible: root.view === "settings"
            width: parent.width
            label: "Notify on new track"
            description: "Show a notification when the music changes"
            checked: root.cfg.notify
            foreground: root.foreground
            fontFamily: root.fontFamily
            onClicked: root.svc.update({ notify: !root.cfg.notify })
          }

          PanelSectionHeader { visible: root.view === "settings"; text: "WHEN OTHER MEDIA PLAYS"; foreground: root.foreground; fontFamily: root.fontFamily }

          Text {
            visible: root.view === "settings"
            width: parent.width
            text: "YouTube Music, Spotify, a video in your browser, or any other media player. The music comes back a few seconds after it stops."
            color: root.dim
            wrapMode: Text.WordWrap
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
          }

          ButtonGroup {
            visible: root.view === "settings"
            spacing: Style.space(6)
            value: root.cfg.otherMedia
            foreground: root.foreground
            fontFamily: root.fontFamily
            focusable: false
            options: [
              { value: "pause", label: "Pause" },
              { value: "lower", label: "Lower volume", tooltip: "Drop to a quarter of your volume" },
              { value: "ignore", label: "Keep playing" }
            ]
            onChanged: function(v) { if (root.svc) root.svc.update({ otherMedia: v }) }
          }

          PanelSectionHeader { visible: root.view === "settings"; text: "WHEN I LOG IN"; foreground: root.foreground; fontFamily: root.fontFamily }

          ButtonGroup {
            visible: root.view === "settings"
            spacing: Style.space(6)
            value: root.cfg.atLogin
            foreground: root.foreground
            fontFamily: root.fontFamily
            focusable: false
            options: [
              { value: "play", label: "Start playing" },
              { value: "wait", label: "Wait for me", tooltip: "Stay paused until you press play" },
              { value: "resume", label: "Remember", tooltip: "Play if it was playing when you logged out" }
            ]
            onChanged: function(v) { if (root.svc) root.svc.update({ atLogin: v }) }
          }

          PanelSectionHeader { visible: root.view === "settings"; text: "WEATHER LOCATION"; foreground: root.foreground; fontFamily: root.fontFamily }

          Text {
            visible: root.view === "settings"
            width: parent.width
            text: {
              if (!root.svc) return ""
              var place = root.svc.weatherPlace || "your location"
              if (root.svc.location.latitude !== null)
                return "Using " + place + " from Omarchy's weather widget."
              return "Using " + place + ", detected automatically. To change it, set a location in Omarchy's weather widget and this follows along."
            }
            color: root.dim
            wrapMode: Text.WordWrap
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
          }

          Text {
            visible: root.view === "settings"
            width: parent.width
            text: "Music streamed from the Animal Crossing Music extension project (acmusicext.com)."
            color: root.dim
            opacity: 0.7
            wrapMode: Text.WordWrap
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
        }
      }
    }
  }

  // Twelve hours x four games of checkboxes. Clicking an hour flips its row,
  // clicking a game heading flips its column (for these twelve hours).
  component HourTable: Column {
    id: table
    property int firstHour: 0
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
          required property var modelData
          width: table.cellWidth
          horizontalAlignment: Text.AlignHCenter
          text: modelData.short
          color: headerMouse.containsMouse ? root.foreground : root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          font.bold: true

          MouseArea {
            id: headerMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: {
              var g = parent.modelData.id
              var allOn = table.hourList.every(function(h) { return root.cfg.hours[String(h)].indexOf(g) >= 0 })
              root.svc.setHoursGames(table.hourList, [g], !allOn)
            }
          }
          PanelToolTip { visible: headerMouse.containsMouse; text: parent.modelData.tooltip }
        }
      }
    }

    Repeater {
      model: table.hourList
      delegate: Row {
        id: hourRow
        required property int modelData
        readonly property bool isNow: !!root.svc && root.svc.hour === modelData

        Text {
          width: table.labelWidth
          height: Style.space(20)
          verticalAlignment: Text.AlignVCenter
          text: Model.hourLabel(hourRow.modelData)
          color: hourRow.isNow ? root.accent : (hourMouse.containsMouse ? root.foreground : root.dim)
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          font.bold: hourRow.isNow

          MouseArea {
            id: hourMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: {
              var h = hourRow.modelData
              var allOn = root.cfg.hours[String(h)].length === Model.GAME_IDS.length
              root.svc.setHoursGames([h], Model.GAME_IDS, !allOn)
            }
          }
        }

        Repeater {
          model: Model.GAMES
          delegate: Item {
            id: cell
            required property var modelData
            readonly property bool checked: root.cfg.hours[String(hourRow.modelData)].indexOf(modelData.id) >= 0
            width: table.cellWidth
            height: Style.space(20)

            Rectangle {
              anchors.centerIn: parent
              width: Style.space(14)
              height: width
              radius: Math.min(3, Style.cornerRadius)
              color: cell.checked ? root.accent : (cellMouse.containsMouse ? Style.hoverFillFor(root.foreground, root.accent) : "transparent")
              border.width: cell.checked ? 0 : 1
              border.color: cellMouse.containsMouse ? root.foreground : root.dim
            }

            MouseArea {
              id: cellMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.svc.setHourGame(hourRow.modelData, cell.modelData.id, !cell.checked)
            }
          }
        }
      }
    }
  }
}
