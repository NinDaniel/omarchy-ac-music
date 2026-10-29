import QtQuick
import qs.Commons
import qs.Ui
import "Model.js" as Model
import "Data.js" as Data

Column {
  id: page

  property var p

  width: parent ? parent.width : 0
  spacing: Style.space(12)

  PageHeader { p: page.p; title: "K.K. Slider" }

  PanelSectionHeader { text: "WHEN K.K. PLAYS"; foreground: page.p.foreground; fontFamily: page.p.fontFamily }

  Toggle {
    width: parent.width
    label: "Saturday night concerts"
    description: "K.K. takes over on Saturdays from 8 PM until midnight"
    checked: page.p.cfg.kk.saturday
    foreground: page.p.foreground
    fontFamily: page.p.fontFamily
    onClicked: page.p.svc.setKK({ saturday: !page.p.cfg.kk.saturday })
  }

  Toggle {
    width: parent.width
    label: "K.K. all the time"
    description: "Play K.K. Slider songs instead of the hourly music"
    checked: page.p.cfg.kk.always
    foreground: page.p.foreground
    fontFamily: page.p.fontFamily
    onClicked: page.p.svc.setKK({ always: !page.p.cfg.kk.always })
  }

  PanelSectionHeader { text: "VERSION"; foreground: page.p.foreground; fontFamily: page.p.fontFamily }

  ButtonGroup {
    spacing: Style.space(6)
    value: page.p.cfg.kk.version
    foreground: page.p.foreground
    fontFamily: page.p.fontFamily
    focusable: false
    options: [
      { value: "live", label: "Live", tooltip: "K.K. performing with his guitar" },
      { value: "aircheck", label: "Aircheck", tooltip: "The full-band radio versions" },
      { value: "both", label: "Both", tooltip: "Either version, picked at random for each song" }
    ]
    onChanged: function(v) { page.p.svc.setKK({ version: v }) }
  }

  PanelSectionHeader { text: "SONGS"; foreground: page.p.foreground; fontFamily: page.p.fontFamily }

  MenuRow {
    p: page.p
    title: "Choose songs"
    summary: {
      var cfg = page.p.cfg
      var on = Data.kkSongs.filter(function(s) { return cfg.kk.skip.indexOf(s) < 0 }).length
      return on + " of " + Data.kkSongs.length + " songs ticked · search, untick, and preview"
    }
    onClicked: page.p.view = "kksongs"
  }
}
