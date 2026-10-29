import QtQuick
import qs.Commons
import qs.Ui

Column {
  id: page

  property var p

  width: parent ? parent.width : 0
  spacing: Style.space(12)

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
}
