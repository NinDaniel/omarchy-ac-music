import QtQuick
import qs.Commons
import qs.Ui

Column {
  id: page

  property var p

  readonly property string linkStyle: "<style>a { color: " + p.accent + "; text-decoration: none; }</style>"

  width: parent ? parent.width : 0
  spacing: Style.space(12)

  PageHeader { p: page.p; title: "Weather & about" }

  PanelSectionHeader { text: "WEATHER LOCATION"; foreground: page.p.foreground; fontFamily: page.p.fontFamily }

  Text {
    width: parent.width
    text: {
      var svc = page.p.svc
      if (!svc) return ""
      var place = svc.weatherPlace || "your location"
      if (svc.location.latitude !== null)
        return "Using " + place + " from Omarchy's weather widget."
      return "Using " + place + ", detected automatically. To change it, set a location in Omarchy's weather widget and this follows along."
    }
    color: page.p.dim
    wrapMode: Text.WordWrap
    font.family: page.p.fontFamily
    font.pixelSize: Style.font.bodySmall
  }

  PanelSectionHeader { text: "WEATHER SOURCE"; foreground: page.p.foreground; fontFamily: page.p.fontFamily }

  ButtonGroup {
    spacing: Style.space(6)
    value: page.p.cfg.weatherSource
    foreground: page.p.foreground
    fontFamily: page.p.fontFamily
    focusable: false
    options: [
      { value: "forecast", label: "Forecast", tooltip: "Open-Meteo's weather forecast only" },
      { value: "airport", label: "Forecast + airports", tooltip: "Also check what nearby airports report falling right now" }
    ]
    onChanged: function(v) { page.p.svc.update({ weatherSource: v }) }
  }

  Text {
    width: parent.width
    text: {
      var svc = page.p.svc
      var cfg = page.p.cfg
      var caption
      if (cfg.weatherSource !== "airport") {
        caption = "Follows Open-Meteo's forecast. Light rain and drizzle can slip past it; for more accurate rain, add airport reports."
      } else {
        caption = "Rain or snow reported by an airport within 50 km plays the rain or snow music even when the forecast misses it. Sends your rough location to aviationweather.gov."
        if (svc && svc.metars) {
          caption += svc.airportSky
            ? " Nearest report: " + svc.airportSky.station + "."
            : " No airport has reported within 50 km lately, so it's using the forecast alone."
        }
      }
      if (cfg.weather !== "auto") caption += " This only applies when Weather is on Auto."
      return caption
    }
    color: page.p.dim
    wrapMode: Text.WordWrap
    font.family: page.p.fontFamily
    font.pixelSize: Style.font.bodySmall
  }

  PanelSectionHeader { text: "CLOUDY SKIES COUNT AS"; foreground: page.p.foreground; fontFamily: page.p.fontFamily }

  ButtonGroup {
    spacing: Style.space(6)
    value: page.p.cfg.cloudy
    foreground: page.p.foreground
    fontFamily: page.p.fontFamily
    focusable: false
    options: [
      { value: "sunny", label: "Sunny", tooltip: "Only actual rain or snow changes the music" },
      { value: "showers", label: "Rain if showery", tooltip: "Rain music when an overcast sky has showers around" },
      { value: "always", label: "Always rain", tooltip: "Rain music whenever it's overcast or foggy" }
    ]
    onChanged: function(v) { page.p.svc.update({ cloudy: v }) }
  }

  Text {
    width: parent.width
    text: {
      var cfg = page.p.cfg
      var caption = cfg.cloudy === "sunny" ? "Overcast and foggy skies play the sunny music."
        : (cfg.cloudy === "showers"
          ? "An overcast sky counts as rain if it rained in the last two hours or is about to, so on-and-off showers don't keep switching the music."
          : "Every overcast or foggy sky counts as rain.")
      if (cfg.cloudy !== "sunny") caption += " It counts as snow instead when it's freezing."
      if (cfg.weather !== "auto") caption += " This only applies when Weather is on Auto."
      return caption
    }
    color: page.p.dim
    wrapMode: Text.WordWrap
    font.family: page.p.fontFamily
    font.pixelSize: Style.font.bodySmall
  }

  PanelSectionHeader { text: "ABOUT"; foreground: page.p.foreground; fontFamily: page.p.fontFamily }

  Text {
    width: parent.width
    text: "AC Hourly Music" + (page.p.svc && page.p.svc.version ? " v" + page.p.svc.version : "")
    color: page.p.foreground
    font.family: page.p.fontFamily
    font.pixelSize: Style.font.subtitle
    font.bold: true
  }

  Text {
    width: parent.width
    textFormat: Text.RichText
    text: page.linkStyle
      + "Music streams from the <a href=\"https://github.com/animal-crossing-music-extension/ac-music-extension\">Animal Crossing Music extension</a>, "
      + "the browser extension that inspired this plugin. Loop points and the K.K. song list come from it too. "
      + "Weather by <a href=\"https://open-meteo.com\">Open-Meteo</a>.<br><br>"
      + "Source, docs, and issues: <a href=\"https://github.com/NinDaniel/omarchy-ac-music\">github.com/NinDaniel/omarchy-ac-music</a><br><br>"
      + "Animal Crossing is a trademark of Nintendo. This is an unofficial fan project."
    color: page.p.dim
    wrapMode: Text.WordWrap
    font.family: page.p.fontFamily
    font.pixelSize: Style.font.bodySmall
    onLinkActivated: function(link) { Qt.openUrlExternally(link) }

    HoverHandler { cursorShape: parent.hoveredLink ? Qt.PointingHandCursor : Qt.ArrowCursor }
  }
}
