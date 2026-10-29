import QtQuick
import qs.Commons
import qs.Ui
import "Model.js" as Model
import "Data.js" as Data

// Settings home: one row per page, each summarizing what's set inside.
Column {
  id: page

  property var p

  width: parent ? parent.width : 0
  spacing: Style.space(10)

  PageHeader { p: page.p; title: "Settings" }

  MenuRow {
    p: page.p
    title: "Hourly music"
    summary: Model.hourlySummary(page.p.cfg)
    onClicked: page.p.view = "hourly"
  }

  MenuRow {
    p: page.p
    title: "K.K. Slider"
    summary: Model.kkSummary(page.p.cfg, Data.kkSongs)
    onClicked: page.p.view = "kk"
  }

  MenuRow {
    p: page.p
    title: "Playback"
    summary: Model.playbackSummary(page.p.cfg)
    onClicked: page.p.view = "playback"
  }

  MenuRow {
    p: page.p
    title: "Weather & about"
    summary: {
      var svc = page.p.svc
      var place = svc && svc.weatherPlace ? svc.weatherPlace : "Weather location"
      return place + " · " + (svc && svc.version ? "v" + svc.version : "") + " · credits"
    }
    onClicked: page.p.view = "about"
  }
}
