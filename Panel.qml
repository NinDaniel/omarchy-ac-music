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

  // Which page is showing: "main", the "settings" menu, or a settings page.
  property string view: "main"
  readonly property var parentView: ({
    settings: "main", hourly: "settings", kk: "settings", playback: "settings",
    about: "settings", kksongs: "kk"
  })

  function back() {
    view = parentView[view] || "main"
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  readonly property string iconSun: String.fromCodePoint(0xF0599)
  readonly property string iconRain: String.fromCodePoint(0xF0597)
  readonly property string iconSnow: String.fromCodePoint(0xF0598)
  readonly property string iconAuto: String.fromCodePoint(0xF0595)
  readonly property string iconVolume: String.fromCodePoint(0xF057E)
  readonly property string iconShuffle: String.fromCodePoint(0xF049D)
  readonly property string iconSkip: String.fromCodePoint(0xF04AD)
  readonly property string iconCog: String.fromCodePoint(0xF0493)
  readonly property string iconBack: String.fromCodePoint(0xF0141)
  readonly property string iconChevron: String.fromCodePoint(0xF0142)
  readonly property string iconPlay: String.fromCodePoint(0xF040A)
  readonly property string iconStop: String.fromCodePoint(0xF04DB)

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
        if (root.view !== "main") root.back()
        else root.close()
      }
      onTabRequested: function(direction) { root.switchPanel(direction) }
      // Space and Enter arrive here rather than as text keys.
      onActivateRequested: if (root.svc) root.svc.togglePlaying()
      onTextKey: function(t) {
        if (!root.svc) return
        if (t === "p") root.svc.togglePlaying()
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
        ScrollBar.vertical: ScrollBar { id: vbar; policy: ScrollBar.AsNeeded }

        Column {
          id: column
          // When the page scrolls, leave a lane for the scroll bar so it
          // never sits on top of buttons at the right edge.
          width: panelFlick.width - (panelFlick.interactive ? vbar.width + Style.space(8) : 0)
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
            // K.K.'s album cover while he's playing; the leaf otherwise (or
            // if the cover can't load).
            iconComponent: Component {
              Item {
                readonly property bool showArt: cover.status === Image.Ready && cover.source != ""
                implicitWidth: showArt ? cover.width : leaf.width
                implicitHeight: showArt ? cover.height : leaf.height

                LeafIcon {
                  id: leaf
                  anchors.centerIn: parent
                  visible: !parent.showArt
                  iconSize: Style.font.display * 1.3
                  color: root.accent
                }

                Image {
                  id: cover
                  anchors.centerIn: parent
                  visible: parent.showArt
                  width: Style.space(52)
                  height: width
                  source: root.svc ? Model.kkArtUrl(root.svc.artSong) : ""
                  sourceSize.width: 128
                  sourceSize.height: 128
                  asynchronous: true
                  smooth: true
                  fillMode: Image.PreserveAspectCrop
                }

                Rectangle {
                  anchors.fill: cover
                  visible: parent.showArt
                  color: "transparent"
                  radius: Math.min(4, Style.cornerRadius)
                  border.width: 1
                  border.color: Qt.darker(root.foreground, 2.2)
                }
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
              readonly property string mode: !root.svc ? "" : (root.svc.betweenActive ? "between" : (root.svc.kkActive ? "kk" : (root.cfg.game === "random" ? "shuffle" : "")))
              visible: mode !== ""
              anchors.left: parent.left
              bordered: true
              iconText: mode === "shuffle" ? root.iconShuffle : root.iconSkip
              text: mode === "between" ? "Skip to the hour" : (mode === "kk" ? "Next song" : "Shuffle game")
              tooltipText: mode === "between" ? "Skip K.K. and start this hour's music"
                : (mode === "kk" ? "Skip to another K.K. song" : "Pick a different game for this hour")
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

          // ================= Settings pages =================

          Loader {
            id: pageLoader
            width: parent.width
            active: root.view !== "main"
            visible: active
            sourceComponent: {
              switch (root.view) {
                case "hourly": return hourlyPage
                case "kk": return kkPage
                case "kksongs": return kkSongsPage
                case "playback": return playbackPage
                case "about": return aboutPage
                default: return settingsMenu
              }
            }
          }
        }
      }
    }
  }

  Component { id: settingsMenu; SettingsMenu { p: root } }
  Component { id: hourlyPage; HourlyPage { p: root } }
  Component { id: kkPage; KKPage { p: root } }
  Component { id: kkSongsPage; KKSongsPage { p: root } }
  Component { id: playbackPage; PlaybackPage { p: root } }
  Component { id: aboutPage; AboutPage { p: root } }
}
