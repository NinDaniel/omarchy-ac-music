import QtQuick
import qs.Commons
import qs.Ui
import "Model.js" as Model

Column {
  id: page

  property var p

  width: parent ? parent.width : 0
  spacing: Style.space(12)

  readonly property var svc: p.svc
  readonly property var quiet: p.cfg.quiet

  Component.onCompleted: if (svc) svc.refreshCacheSize()

  function hourOptions(from, to, isEnd) {
    var out = []
    for (var h = from; h <= to; h++) {
      var label = h === 24 ? "Midnight" : Model.hourLabel(h % 24) + (isEnd && h <= page.quiet.start ? " (next day)" : "")
      out.push({ value: String(h), label: label })
    }
    return out
  }

  function megabytes(bytes) {
    if (bytes < 0) return "…"
    return bytes < 1048576 ? "under 1 MB" : Math.round(bytes / 1048576) + " MB"
  }

  PageHeader { p: page.p; title: "Playback" }

  Toggle {
    width: parent.width
    label: "Fade between tracks"
    description: "Fade out the old song when the hour, weather, or game changes"
    checked: page.p.cfg.fade
    foreground: page.p.foreground
    fontFamily: page.p.fontFamily
    onClicked: page.p.svc.update({ fade: !page.p.cfg.fade })
  }

  Toggle {
    width: parent.width
    label: "Notify on new track"
    description: "Show a notification when the music changes"
    checked: page.p.cfg.notify
    foreground: page.p.foreground
    fontFamily: page.p.fontFamily
    onClicked: page.p.svc.update({ notify: !page.p.cfg.notify })
  }

  Toggle {
    width: parent.width
    label: "Even out volume"
    description: page.p.cfg.cache.enabled
      ? "Brings every song to the same loudness, so quiet ones (like the GameCube airchecks) aren't drowned out"
      : "Needs the song cache below, which is where songs are measured"
    checked: page.p.cfg.levelVolume
    foreground: page.p.foreground
    fontFamily: page.p.fontFamily
    onClicked: page.svc.update({ levelVolume: !page.p.cfg.levelVolume })
  }

  PanelSectionHeader { text: "WHEN OTHER MEDIA PLAYS"; foreground: page.p.foreground; fontFamily: page.p.fontFamily }

  Text {
    width: parent.width
    text: "YouTube Music, Spotify, a video in your browser, or any other media player. The music comes back a few seconds after it stops."
    color: page.p.dim
    wrapMode: Text.WordWrap
    font.family: page.p.fontFamily
    font.pixelSize: Style.font.bodySmall
  }

  ButtonGroup {
    spacing: Style.space(6)
    value: page.p.cfg.otherMedia
    foreground: page.p.foreground
    fontFamily: page.p.fontFamily
    focusable: false
    options: [
      { value: "pause", label: "Pause" },
      { value: "lower", label: "Lower volume", tooltip: "Drop to a quarter of your volume" },
      { value: "ignore", label: "Keep playing" }
    ]
    onChanged: function(v) { page.p.svc.update({ otherMedia: v }) }
  }

  PanelSectionHeader { text: "WHEN I LOG IN"; foreground: page.p.foreground; fontFamily: page.p.fontFamily }

  ButtonGroup {
    spacing: Style.space(6)
    value: page.p.cfg.atLogin
    foreground: page.p.foreground
    fontFamily: page.p.fontFamily
    focusable: false
    options: [
      { value: "play", label: "Start playing" },
      { value: "wait", label: "Wait for me", tooltip: "Stay paused until you press play" },
      { value: "resume", label: "Remember", tooltip: "Play if it was playing when you logged out" }
    ]
    onChanged: function(v) { page.p.svc.update({ atLogin: v }) }
  }

  Text {
    width: parent.width
    text: page.p.cfg.atLogin === "wait"
      ? "The music stays paused after you log in until you press play."
      : page.p.cfg.atLogin === "resume"
        ? "The music plays if it was playing when you logged out."
        : "The music starts every time you log in."
    color: page.p.dim
    wrapMode: Text.WordWrap
    font.family: page.p.fontFamily
    font.pixelSize: Style.font.bodySmall
  }

  // ---- Sleep timer ----

  PanelSectionHeader { text: "SLEEP TIMER"; foreground: page.p.foreground; fontFamily: page.p.fontFamily }

  Text {
    width: parent.width
    text: "Fades the music out and pauses it after a while. It's for this session only, and won't carry over to your next login."
    color: page.p.dim
    wrapMode: Text.WordWrap
    font.family: page.p.fontFamily
    font.pixelSize: Style.font.bodySmall
  }

  Row {
    spacing: Style.space(10)

    Dropdown {
      width: Style.space(170)
      showLabel: false
      value: page.svc ? page.svc.sleepChoice : "off"
      options: [
        { value: "off", label: "Off" },
        { value: "15", label: "15 minutes" },
        { value: "30", label: "30 minutes" },
        { value: "45", label: "45 minutes" },
        { value: "60", label: "1 hour" },
        { value: "90", label: "90 minutes" },
        { value: "hour", label: "End of this hour" }
      ]
      foreground: page.p.foreground
      fontFamily: page.p.fontFamily
      onChanged: function(v) {
        if (!page.svc) return
        if (v === "off") page.svc.setSleep(0)
        else if (v === "hour") page.svc.setSleep(-1)
        else page.svc.setSleep(parseInt(v, 10))
      }
    }

    Text {
      anchors.verticalCenter: parent.verticalCenter
      visible: !!page.svc && page.svc.sleepAt > 0
      text: page.svc && page.svc.sleepAt > 0 ? "Stops in " + page.svc.sleepMinutesLeft + " min" : ""
      color: page.p.accent
      font.family: page.p.fontFamily
      font.pixelSize: Style.font.bodySmall
    }
  }

  // ---- Quiet hours ----

  PanelSectionHeader { text: "QUIET HOURS"; foreground: page.p.foreground; fontFamily: page.p.fontFamily }

  Toggle {
    width: parent.width
    label: "Quiet hours"
    description: page.quiet.enabled
      ? Model.quietText(page.quiet) + " every day"
      : "Pause or turn down the music at the same time every day"
    checked: page.quiet.enabled
    foreground: page.p.foreground
    fontFamily: page.p.fontFamily
    onClicked: page.svc.update({ quiet: Object.assign({}, page.quiet, { enabled: !page.quiet.enabled }) })
  }

  Row {
    visible: page.quiet.enabled
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
      value: String(page.quiet.start)
      options: page.hourOptions(0, 23, false)
      foreground: page.p.foreground
      fontFamily: page.p.fontFamily
      onChanged: function(v) { page.svc.update({ quiet: Object.assign({}, page.quiet, { start: parseInt(v, 10) }) }) }
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
      value: String(page.quiet.end)
      options: page.hourOptions(1, 24, true)
      foreground: page.p.foreground
      fontFamily: page.p.fontFamily
      onChanged: function(v) { page.svc.update({ quiet: Object.assign({}, page.quiet, { end: parseInt(v, 10) }) }) }
    }
  }

  ButtonGroup {
    visible: page.quiet.enabled
    spacing: Style.space(6)
    value: page.quiet.mode
    foreground: page.p.foreground
    fontFamily: page.p.fontFamily
    focusable: false
    options: [
      { value: "pause", label: "Pause" },
      { value: "lower", label: "Lower volume", tooltip: "Play at a quarter of your volume" }
    ]
    onChanged: function(v) { page.svc.update({ quiet: Object.assign({}, page.quiet, { mode: v }) }) }
  }

  Text {
    visible: page.quiet.enabled
    width: parent.width
    text: "The music comes back on its own when quiet hours end, so it doubles as a gentle wake-up. Pausing it yourself always wins."
    color: page.p.dim
    wrapMode: Text.WordWrap
    font.family: page.p.fontFamily
    font.pixelSize: Style.font.bodySmall
  }

  // ---- Song cache ----

  PanelSectionHeader { text: "SONG CACHE"; foreground: page.p.foreground; fontFamily: page.p.fontFamily }

  Toggle {
    width: parent.width
    label: "Keep recent songs on disk"
    description: "Reuses songs you've heard instead of downloading them again, and fetches the next hour's song ahead of time"
    checked: page.p.cfg.cache.enabled
    foreground: page.p.foreground
    fontFamily: page.p.fontFamily
    onClicked: page.svc.update({ cache: Object.assign({}, page.p.cfg.cache, { enabled: !page.p.cfg.cache.enabled }) })
  }

  Row {
    visible: page.p.cfg.cache.enabled
    spacing: Style.space(10)

    Dropdown {
      width: Style.space(110)
      showLabel: false
      value: String(page.p.cfg.cache.limitMB)
      options: Model.CACHE_LIMITS.map(function(mb) { return { value: String(mb), label: mb >= 1000 ? (mb / 1000) + " GB" : mb + " MB" } })
      foreground: page.p.foreground
      fontFamily: page.p.fontFamily
      onChanged: function(v) { page.svc.update({ cache: Object.assign({}, page.p.cfg.cache, { limitMB: parseInt(v, 10) }) }) }
    }

    Text {
      anchors.verticalCenter: parent.verticalCenter
      text: "Using " + page.megabytes(page.svc ? page.svc.cacheBytes : -1)
      color: page.p.dim
      font.family: page.p.fontFamily
      font.pixelSize: Style.font.bodySmall
    }
  }

  Button {
    bordered: true
    text: "Clear cache"
    tooltipText: "Delete every cached song (they download again as needed)"
    foreground: page.p.foreground
    fontFamily: page.p.fontFamily
    onClicked: page.svc.clearCache()
  }

  Text {
    width: parent.width
    text: "Stored in ~/.cache/ac-music. The least recently played songs are deleted first once it's full."
    color: page.p.dim
    wrapMode: Text.WordWrap
    font.family: page.p.fontFamily
    font.pixelSize: Style.font.bodySmall
  }
}
