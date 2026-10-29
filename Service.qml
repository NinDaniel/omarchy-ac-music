import QtQuick
import Quickshell
import Quickshell.Io
import "Model.js" as Model
import "Data.js" as Data
import "bridge" as AcBridge

// One instance per shell session (bar widgets are per-monitor, so playback
// lives here). Owns the config file, the clock, live weather, and a single
// long-running mpv driven over its JSON IPC socket.
Item {
  id: root

  property var shell: null

  readonly property string home: Quickshell.env("HOME")
  readonly property string configPath: home + "/.config/omarchy/ac-music.json"
  readonly property string socketPath: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/danr-ac-music.sock"

  property var config: Model.defaultConfig()
  property bool configLoaded: false

  // ---- Clock ----
  property var now: new Date()
  readonly property int hour: now.getHours()
  readonly property string day: Model.dateKey(now)

  // ---- Weather ----
  property string liveWeather: ""
  property string weatherPlace: ""
  property var location: ({ name: "", latitude: null, longitude: null })
  property var resolvedCoords: null
  property string resolvedFor: "-"
  readonly property bool autoWeather: config.weather === "auto"
  readonly property string weather: autoWeather ? (liveWeather || "sunny") : config.weather

  // ---- What should be playing ----
  property int salt: 0
  readonly property bool playing: config.playing
  readonly property bool kkActive: Model.isKKTime(config, now)
  readonly property string game: Model.pickGame(config, day, hour, salt)
  readonly property string trackWeather: Model.trackWeather(game, weather)
  // Changing this string is what triggers a track change. Waiting for the
  // first weather answer (briefly) avoids playing sunny music for a second
  // and then swapping to rain.
  readonly property bool ready: configLoaded && (!autoWeather || liveWeather !== "" || weatherGrace.expired)
  readonly property string trackKey: !ready ? "" : (kkActive ? "kk|" + config.kk.version : game + "|" + trackWeather + "|" + hour)

  // ---- Now playing (for the UI) ----
  property string kkSong: ""
  property string kkVersionPlaying: ""
  property var recentKK: []
  property string lastError: ""
  // View the next panel opening should land on ("settings" from the CLI).
  property string requestedView: ""
  readonly property string title: kkActive ? "K.K. Slider" : Model.gameName(game)
  readonly property string subtitle: {
    if (kkActive) return kkSong ? Model.kkTitle(kkSong) + " · " + (kkVersionPlaying === "aircheck" ? "Aircheck" : "Live") : "K.K. Slider"
    return Model.hourLabel(hour) + " · " + Model.weatherName(weather)
  }

  // ---- mpv ----
  property bool mpvReady: false
  property var pending: []
  property real appliedVolume: -1
  property bool fading: false
  property string loadedKey: ""

  Component.onCompleted: AcBridge.Bridge.service = root
  Component.onDestruction: {
    if (AcBridge.Bridge.service === root) AcBridge.Bridge.service = null
    mpvProc.running = false
  }

  // ---- Config ------------------------------------------------------------

  function update(patch) {
    var next = Model.clone(config)
    for (var key in patch) next[key] = patch[key]
    config = Model.normalizeConfig(next)
    configFile.setText(JSON.stringify(config, null, 2) + "\n")
  }

  function setKK(patch) {
    var kk = Model.clone(config.kk)
    for (var key in patch) kk[key] = patch[key]
    update({ kk: kk })
  }

  function setPlaying(on) { update({ playing: !!on }) }
  function togglePlaying() { setPlaying(!config.playing) }
  function setGame(id) { salt = 0; update({ game: id }) }
  function setWeather(w) { update({ weather: w }) }
  function setVolume(v) { update({ volume: Math.round(Math.max(0, Math.min(1, v)) * 100) / 100 }) }
  function nudgeVolume(delta) { setVolume(config.volume + delta) }

  function setHourGame(hour, gameId, on) {
    var hours = Model.clone(config.hours)
    var list = hours[String(hour)].filter(function(id) { return id !== gameId })
    if (on) list.push(gameId)
    hours[String(hour)] = list
    update({ hours: hours })
  }

  // Tick or clear a whole set of hours for one or more games at once.
  function setHoursGames(hourList, gameIds, on) {
    var hours = Model.clone(config.hours)
    hourList.forEach(function(h) {
      var list = hours[String(h)].filter(function(id) { return gameIds.indexOf(id) < 0 })
      if (on) list = list.concat(gameIds)
      hours[String(h)] = list
    })
    update({ hours: hours })
  }

  // Random: roll a different game for this hour. K.K.: skip to the next song.
  function next() {
    if (kkActive) playNextKK()
    else if (config.game === "random") salt++
  }

  FileView {
    id: configFile
    path: root.configPath
    watchChanges: true
    atomicWrites: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      var parsed = null
      try { parsed = JSON.parse(text()) } catch (e) { parsed = null }
      root.config = Model.normalizeConfig(parsed)
      root.configLoaded = true
    }
    onLoadFailed: {
      root.config = Model.defaultConfig()
      root.configLoaded = true
      setText(JSON.stringify(root.config, null, 2) + "\n")
    }
  }

  // ---- Clock -------------------------------------------------------------

  Timer {
    interval: 1000
    running: true
    repeat: true
    onTriggered: {
      var d = new Date()
      if (d.getHours() !== root.now.getHours() || d.getDate() !== root.now.getDate()) {
        root.salt = 0
        root.now = d
      }
    }
  }

  // ---- Playback ----------------------------------------------------------

  onTrackKeyChanged: if (trackKey !== "") Qt.callLater(syncTrack)
  onPlayingChanged: syncPause()
  onConfigChanged: syncVolume()

  function send(args) {
    var line = JSON.stringify({ command: args }) + "\n"
    if (!mpvReady) { pending.push(line); return }
    ipc.write(line)
    ipc.flush()
  }

  function ensureMpv() {
    if (mpvProc.running) return
    mpvReady = false
    appliedVolume = -1
    loadedKey = ""
    mpvProc.running = true
    connectRetry.attempts = 0
    connectRetry.start()
  }

  function targetVolume() {
    return Math.round(config.volume * 100)
  }

  function syncVolume() {
    if (fading || !mpvProc.running) return
    var v = targetVolume()
    if (v === appliedVolume) return
    appliedVolume = v
    send(["set_property", "volume", v])
  }

  function syncPause() {
    if (!configLoaded) return
    if (!playing) {
      if (mpvProc.running) send(["set_property", "pause", true])
      return
    }
    ensureMpv()
    // The hour (or weather) may have moved on while paused: load the new
    // track straight away instead of resuming the stale one.
    if (trackKey !== "" && loadedKey !== trackKey) loadCurrent()
    else send(["set_property", "pause", false])
  }

  // Switch to whatever trackKey says should be playing, fading out the old
  // track first when it is audible.
  function syncTrack() {
    if (trackKey === "" || trackKey === loadedKey) return
    if (!playing) {
      // Load nothing while paused; resuming will pick up the right track.
      return
    }
    ensureMpv()
    if (config.fade && loadedKey !== "" && mpvReady) fadeOut.begin()
    else loadCurrent()
  }

  function loadCurrent() {
    lastError = ""
    loadedKey = trackKey
    if (kkActive) {
      playNextKK()
      return
    }
    var loop = Model.loopPoints(Data.loopTimes, game, trackWeather, hour)
    var opts = "loop-file=inf"
    if (loop && loop[1] > loop[0]) opts += ",ab-loop-a=" + loop[0] + ",ab-loop-b=" + loop[1]
    else opts += ",ab-loop-a=no,ab-loop-b=no"
    send(["loadfile", Model.hourlyUrl(game, trackWeather, hour), "replace", -1, opts])
    send(["set_property", "pause", !playing])
    restoreVolume()
    notifyTrack(Model.gameName(game), Model.hourLabel(hour) + " · " + Model.weatherName(trackWeather))
  }

  function playNextKK() {
    var songs = Data.kkSongs
    var fresh = songs.filter(function(s) { return recentKK.indexOf(s) < 0 })
    var song = fresh[Math.floor(Math.random() * fresh.length)]
    var version = config.kk.version === "both" ? (Math.random() < 0.5 ? "live" : "aircheck") : config.kk.version
    recentKK = recentKK.concat([song]).slice(-20)
    kkSong = song
    kkVersionPlaying = version
    lastError = ""
    send(["loadfile", Model.kkUrl(version, song), "replace", -1, "loop-file=no,ab-loop-a=no,ab-loop-b=no"])
    send(["set_property", "pause", !playing])
    restoreVolume()
    notifyTrack("K.K. Slider", Model.kkTitle(song))
  }

  function restoreVolume() {
    fading = false
    appliedVolume = -1
    syncVolume()
  }

  function notifyTrack(summary, body) {
    if (!config.notify || !playing) return
    Quickshell.execDetached(["notify-send", "-a", "AC Music", "-i", "audio-x-generic", summary, body])
  }

  function handleMpvLine(line) {
    var msg
    try { msg = JSON.parse(line) } catch (e) { return }
    if (msg.event !== "end-file") return
    if (msg.reason === "eof" && kkActive && loadedKey === trackKey) {
      playNextKK()
    } else if (msg.reason === "error") {
      lastError = "Couldn't reach the music server"
      retryTimer.restart()
    }
  }

  Timer {
    id: fadeOut
    interval: 80
    repeat: true
    property int step: 0
    readonly property int steps: 20
    function begin() {
      root.fading = true
      step = 0
      restart()
    }
    onTriggered: {
      step++
      var v = Math.round(root.targetVolume() * (1 - step / steps))
      root.send(["set_property", "volume", Math.max(0, v)])
      if (step >= steps) {
        stop()
        root.loadCurrent()
      }
    }
  }

  // A network error drops back to idle; try the current track again later.
  Timer {
    id: retryTimer
    interval: 30000
    onTriggered: if (root.playing) { root.loadedKey = ""; root.syncTrack() }
  }

  Process {
    id: mpvProc
    command: [
      "mpv",
      "--no-config",
      "--idle=yes",
      "--no-video",
      "--no-terminal",
      "--audio-display=no",
      "--cache=yes",
      "--demuxer-max-back-bytes=64MiB",
      "--audio-client-name=AC Music",
      "--input-ipc-server=" + root.socketPath
    ]
    onRunningChanged: {
      if (!running) {
        root.mpvReady = false
        ipc.connected = false
        // Crashed or killed while we still want music: start it back up.
        if (root.playing && root.configLoaded) restartMpv.start()
      }
    }
  }

  Timer {
    id: restartMpv
    interval: 3000
    onTriggered: if (root.playing) { root.ensureMpv(); root.syncPause() }
  }

  // mpv creates its socket shortly after starting; poll until we're in.
  Timer {
    id: connectRetry
    interval: 100
    repeat: true
    property int attempts: 0
    onTriggered: {
      if (ipc.connected) {
        stop()
        return
      }
      if (++attempts > 100) {
        stop()
        root.lastError = "Couldn't start mpv"
        return
      }
      ipc.connected = false
      ipc.connected = true
    }
  }

  Socket {
    id: ipc
    path: root.socketPath
    parser: SplitParser {
      onRead: function(line) { root.handleMpvLine(line) }
    }
    onConnectedChanged: {
      if (!connected) return
      connectRetry.stop()
      root.mpvReady = true
      var queued = root.pending
      root.pending = []
      queued.forEach(function(line) { ipc.write(line) })
      ipc.flush()
      root.syncVolume()
    }
  }

  // ---- Weather -----------------------------------------------------------

  // Give the first weather lookup a few seconds before falling back to sunny.
  Timer {
    id: weatherGrace
    property bool expired: false
    interval: 6000
    running: true
    onTriggered: expired = true
  }

  FileView {
    id: locationFile
    path: root.home + "/.local/state/omarchy/settings/weather.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.location = Model.parseOmarchyLocation(text())
    onLoadFailed: root.location = Model.parseOmarchyLocation("")
  }

  // locationFile always assigns on load (or load failure), which kicks off
  // the first lookup.
  onLocationChanged: refreshWeather()
  onAutoWeatherChanged: refreshWeather()

  Timer {
    interval: 20 * 60 * 1000
    running: root.autoWeather
    repeat: true
    onTriggered: root.refreshWeather()
  }

  function refreshWeather() {
    if (!autoWeather) return
    if (location.latitude !== null) {
      fetchForecast(location.latitude, location.longitude, location.name)
    } else if (resolvedCoords && resolvedFor === location.name) {
      fetchForecast(resolvedCoords.latitude, resolvedCoords.longitude, resolvedCoords.name)
    } else if (!geoProc.running) {
      // No coordinates: let wttr.in place us (by name, or by IP when empty),
      // the same way Omarchy's own weather widget does.
      geoProc.query = location.name
      geoProc.command = ["curl", "-fsS", "--max-time", "10", "https://wttr.in/" + encodeURIComponent(location.name) + "?format=j1"]
      geoProc.running = true
    }
  }

  function fetchForecast(lat, lon, place) {
    if (forecastProc.running) return
    forecastProc.place = place
    forecastProc.command = ["curl", "-fsS", "--max-time", "10",
      "https://api.open-meteo.com/v1/forecast?latitude=" + lat + "&longitude=" + lon + "&current=weather_code&timezone=auto"]
    forecastProc.running = true
  }

  Process {
    id: geoProc
    property string query: ""
    stdout: StdioCollector {
      onStreamFinished: {
        try {
          var area = JSON.parse(text).nearest_area[0]
          root.resolvedCoords = {
            latitude: parseFloat(area.latitude),
            longitude: parseFloat(area.longitude),
            name: geoProc.query || area.areaName[0].value
          }
          root.resolvedFor = geoProc.query
          root.fetchForecast(root.resolvedCoords.latitude, root.resolvedCoords.longitude, root.resolvedCoords.name)
        } catch (e) {}
      }
    }
  }

  Process {
    id: forecastProc
    property string place: ""
    stdout: StdioCollector {
      onStreamFinished: {
        try {
          var data = JSON.parse(text)
          root.liveWeather = Model.weatherFromWmo(data.current.weather_code)
          root.weatherPlace = forecastProc.place
        } catch (e) {}
      }
    }
  }

  // ---- CLI / keybinds: omarchy-shell danr.ac-music <method> ----------------

  IpcHandler {
    target: "danr.ac-music"

    function toggle(): string { root.togglePlaying(); return root.config.playing ? "playing" : "paused" }
    function play(): string { root.setPlaying(true); return "playing" }
    function pause(): string { root.setPlaying(false); return "paused" }
    function next(): string { root.next(); return "ok" }
    function requestView(view: string): string { root.requestedView = view; return "ok" }
    function status(): string {
      return (root.playing ? "Playing" : "Paused") + ": " + root.title + " - " + root.subtitle
    }
    function game(id: string): string {
      if (id !== "random" && Model.GAME_IDS.indexOf(id) < 0) return "unknown game: " + id + " (try " + Model.GAME_IDS.join(", ") + ", random)"
      root.setGame(id)
      return id
    }
    function weather(mode: string): string {
      var aliases = { rain: "raining", snow: "snowing", sun: "sunny" }
      var w = aliases[mode] || mode
      if (["auto"].concat(Model.WEATHERS).indexOf(w) < 0) return "unknown weather: " + mode + " (try auto, sunny, rain, snow)"
      root.setWeather(w)
      return w
    }
    function volume(percent: string): string {
      var s = String(percent)
      var n = parseFloat(s)
      if (isNaN(n)) return "usage: volume <0-100 | +5 | -5>"
      if (s[0] === "+" || s[0] === "-") root.nudgeVolume(n / 100)
      else root.setVolume(n / 100)
      return Math.round(root.config.volume * 100) + "%"
    }
    function kk(mode: string): string {
      if (mode === "on") root.setKK({ always: true })
      else if (mode === "off") root.setKK({ always: false })
      else root.setKK({ always: !root.config.kk.always })
      return root.config.kk.always ? "K.K. on" : "K.K. off"
    }
  }
}
