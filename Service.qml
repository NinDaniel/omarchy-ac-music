import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
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
  // Lives in the runtime dir, which is wiped at logout: missing means this is
  // a fresh login rather than a shell restart.
  readonly property string sessionMarkerPath: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/danr-ac-music.session"

  property var config: Model.defaultConfig()
  property bool configLoaded: false
  property int sessionState: 0  // 0 unknown, 1 fresh login, 2 shell restart
  property bool loginApplied: false

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
  property int slot: 0
  readonly property bool playing: config.playing
  // Other media players (MPRIS) can hold us: paused or quieter until they stop.
  property bool otherMediaHold: false
  property string otherMediaName: ""
  readonly property bool heldPaused: otherMediaHold && config.otherMedia === "pause"
  readonly property bool heldQuiet: otherMediaHold && config.otherMedia === "lower"
  // Actually making sound: the user wants music and nothing is holding it.
  readonly property bool audible: playing && !heldPaused
  // K.K. by schedule (always or a concert), or picked from the hourly grid.
  readonly property bool kkScheduled: Model.isKKTime(config, now)
  readonly property bool kkActive: kkScheduled || game === Model.KK_ID
  // Hour that opens with one K.K. song before its own music (between-hours).
  property int betweenHour: -1
  readonly property bool betweenActive: betweenHour === hour && !kkActive
  readonly property string game: Model.pickGame(config, day, hour, salt, slot, weather)
  readonly property string trackWeather: Model.trackWeather(game, weather)
  // Changing this string is what triggers a track change. Waiting for the
  // first weather answer (briefly) avoids playing sunny music for a second
  // and then swapping to rain.
  readonly property bool ready: configLoaded && loginApplied && (!autoWeather || liveWeather !== "" || weatherGrace.expired)
  readonly property string trackKey: {
    if (!ready) return ""
    if (betweenActive) return "between|" + hour
    if (kkActive) return "kk"
    return game + "|" + trackWeather + "|" + hour
  }

  // ---- Now playing (for the UI) ----
  property string kkSong: ""
  property string kkVersionPlaying: ""
  property var recentKK: []
  property string lastError: ""
  // K.K. song being previewed from Settings (plays over whatever was on).
  property string previewSong: ""
  property string previewVersion: ""
  // K.K. song whose cover the panel shows (empty when no K.K. is playing).
  readonly property string artSong: previewSong || (kkActive || betweenActive ? kkSong : "")
  property string version: ""
  // View the next panel opening should land on ("settings" from the CLI).
  property string requestedView: ""
  readonly property string title: previewSong ? "K.K. Slider preview" : (kkActive || betweenActive ? "K.K. Slider" : Model.gameName(game))
  readonly property string subtitle: {
    if (previewSong) return Model.kkTitle(previewSong) + " · " + Model.versionName(previewVersion)
    var song = kkSong ? Model.kkTitle(kkSong) + " · " + Model.versionName(kkVersionPlaying) : ""
    if (betweenActive) return (song || "K.K. Slider") + " · then " + Model.hourLabel(hour)
    if (kkActive) return song || "K.K. Slider"
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

  // Tick or clear a set of hours for one or more games in one weather's grid.
  function setHoursGames(weatherId, hourList, gameIds, on) {
    var hours = Model.clone(config.hours)
    var grid = hours[weatherId]
    hourList.forEach(function(h) {
      var list = grid[String(h)].filter(function(id) { return gameIds.indexOf(id) < 0 })
      if (on) list = list.concat(gameIds)
      grid[String(h)] = list
    })
    update({ hours: hours })
  }

  // Copy what's in effect for one weather (GameCube on Rain follows Sunny)
  // to all three grids.
  function copyGridToAll(weatherId) {
    var source = {}
    for (var h = 0; h < 24; h++)
      source[String(h)] = Model.GRID_IDS.filter(function(id) { return Model.ticked(config, weatherId, h, id) })
    var hours = {}
    Model.WEATHERS.forEach(function(w) { hours[w] = Model.clone(source) })
    update({ hours: hours })
  }

  // Tick (on) or untick K.K. song versions, given as "version/song" keys.
  function setKKSongs(keys, on) {
    var off = config.kk.off.filter(function(k) { return keys.indexOf(k) < 0 })
    if (!on) off = off.concat(keys)
    setKK({ off: off })
  }

  function setConcerts(patch) {
    var concerts = Model.clone(config.kk.concerts)
    for (var key in patch) concerts[key] = patch[key]
    setKK({ concerts: concerts })
  }

  function setBetween(patch) {
    var between = Model.clone(config.kk.between)
    for (var key in patch) between[key] = patch[key]
    setKK({ between: between })
  }

  // Between-hours song: skip it. Random: roll a different game for this
  // hour. K.K.: skip to the next song.
  function next() {
    if (betweenActive) endBetween()
    else if (kkActive) playNextKK()
    else if (config.game === "random") salt++
  }

  function endBetween() {
    loadedKey = ""
    betweenHour = -1
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

  // ---- Version (shown on the About page) ---------------------------------

  FileView {
    path: {
      var url = String(Qt.resolvedUrl("manifest.json"))
      return decodeURIComponent(url.indexOf("file://") === 0 ? url.substring(7) : url)
    }
    printErrors: false
    onLoaded: {
      try { root.version = JSON.parse(text()).version || "" } catch (e) {}
    }
  }

  // ---- Login behavior ----------------------------------------------------

  FileView {
    id: sessionMarker
    path: root.sessionMarkerPath
    printErrors: false
    onLoaded: root.sessionState = 2
    onLoadFailed: {
      root.sessionState = 1
      setText("1\n")
    }
  }

  onConfigLoadedChanged: applyLogin()
  onSessionStateChanged: applyLogin()

  function applyLogin() {
    if (loginApplied || !configLoaded || sessionState === 0) return
    if (sessionState === 1 && config.atLogin !== "resume") {
      var wanted = config.atLogin === "play"
      if (config.playing !== wanted) update({ playing: wanted })
    }
    loginApplied = true
  }

  // ---- Other media -------------------------------------------------------

  readonly property var mprisPlayers: Mpris.players ? Mpris.players.values : []
  onMprisPlayersChanged: checkOtherMedia()

  Instantiator {
    model: root.mprisPlayers
    delegate: Connections {
      required property var modelData
      target: modelData
      function onIsPlayingChanged() { root.checkOtherMedia() }
    }
  }

  function playingOtherPlayer() {
    for (var i = 0; i < mprisPlayers.length; i++) {
      var p = mprisPlayers[i]
      if (p && p.isPlaying) return p
    }
    return null
  }

  // Step aside quickly when something starts; come back only after it has
  // been quiet for a few seconds, so gaps between songs don't bounce us.
  function checkOtherMedia() {
    var p = config.otherMedia === "ignore" ? null : playingOtherPlayer()
    if (p) {
      otherMediaName = p.identity || p.desktopEntry || "another player"
      releaseTimer.stop()
      if (!otherMediaHold) holdTimer.restart()
    } else {
      holdTimer.stop()
      if (otherMediaHold) releaseTimer.restart()
    }
  }

  function syncOtherMediaMode() {
    if (config.otherMedia !== "ignore") {
      checkOtherMedia()
      return
    }
    holdTimer.stop()
    releaseTimer.stop()
    otherMediaHold = false
  }

  Timer {
    id: holdTimer
    interval: 400
    onTriggered: root.otherMediaHold = true
  }

  Timer {
    id: releaseTimer
    interval: 3000
    onTriggered: root.otherMediaHold = false
  }

  // ---- Clock -------------------------------------------------------------

  Timer {
    interval: 1000
    running: true
    repeat: true
    onTriggered: {
      var d = new Date()
      if (d.getHours() !== root.now.getHours() || d.getDate() !== root.now.getDate()) {
        var hourChanged = d.getHours() !== root.now.getHours()
        root.salt = 0
        // Only a real hour change while music is playing opens with K.K.
        if (hourChanged && root.audible && root.ready && Model.wantsBetween(root.config, d.getHours()))
          root.betweenHour = d.getHours()
        root.now = d
      }
      root.syncSlot(d)
    }
  }

  function syncSlot(date) {
    var s = Model.shuffleSlot(config, date)
    if (s !== slot) slot = s
  }

  // ---- Playback ----------------------------------------------------------

  onTrackKeyChanged: if (trackKey !== "") Qt.callLater(syncTrack)
  onAudibleChanged: syncPause()
  onConfigChanged: {
    syncSlot(new Date())
    syncVolume()
    syncOtherMediaMode()
  }
  onHeldQuietChanged: syncVolume()

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
    return Math.round(config.volume * (heldQuiet ? 0.25 : 1) * 100)
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
    if (!audible) {
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
    if (!audible) {
      // Load nothing while paused; resuming will pick up the right track.
      return
    }
    ensureMpv()
    if (config.fade && loadedKey !== "" && mpvReady) fadeOut.begin()
    else loadCurrent()
  }

  function loadCurrent() {
    previewSong = ""
    lastError = ""
    loadedKey = trackKey
    if (betweenActive) {
      startKK(Model.pickKK(config, Data.kkSongs, recentKK))
      notifyTrack("K.K. Slider", Model.kkTitle(kkSong) + ", then " + Model.hourLabel(hour))
      return
    }
    if (kkActive) {
      playNextKK()
      return
    }
    var loop = Model.loopPoints(Data.loopTimes, game, trackWeather, hour)
    var opts = "loop-file=inf"
    if (loop && loop[1] > loop[0]) opts += ",ab-loop-a=" + loop[0] + ",ab-loop-b=" + loop[1]
    else opts += ",ab-loop-a=no,ab-loop-b=no"
    send(["loadfile", Model.hourlyUrl(game, trackWeather, hour), "replace", -1, opts])
    send(["set_property", "pause", !audible])
    restoreVolume()
    notifyTrack(Model.gameName(game), Model.hourLabel(hour) + " · " + Model.weatherName(trackWeather))
  }

  // Load one K.K. song ({ song, version }); it plays once, no looping.
  function startKK(choice) {
    previewSong = ""
    recentKK = recentKK.concat([choice.song]).slice(-20)
    kkSong = choice.song
    kkVersionPlaying = choice.version
    lastError = ""
    send(["loadfile", Model.kkUrl(choice.version, choice.song), "replace", -1, "loop-file=no,ab-loop-a=no,ab-loop-b=no"])
    send(["set_property", "pause", !audible])
    restoreVolume()
  }

  function playNextKK() {
    startKK(Model.pickKK(config, Data.kkSongs, recentKK))
    notifyTrack("K.K. Slider", Model.kkTitle(kkSong))
  }

  function restoreVolume() {
    fading = false
    appliedVolume = -1
    syncVolume()
  }

  function notifyTrack(summary, body) {
    if (!config.notify || !audible) return
    Quickshell.execDetached(["notify-send", "-a", "AC Music", "-i", "audio-x-generic", summary, body])
  }

  // Play one K.K. song right now, from the song picker. When it ends (or is
  // stopped) the scheduled music picks back up.
  function playPreview(song, version) {
    if (previewSong === song && previewVersion === version) {
      stopPreview()
      return
    }
    ensureMpv()
    fadeOut.stop()
    previewSong = song
    previewVersion = version
    loadedKey = "preview"
    send(["loadfile", Model.kkUrl(version, song), "replace", -1, "loop-file=no,ab-loop-a=no,ab-loop-b=no"])
    send(["set_property", "pause", false])
    restoreVolume()
  }

  function stopPreview() {
    if (!previewSong) return
    previewSong = ""
    loadedKey = ""
    if (audible) syncTrack()
    else send(["stop"])
  }

  function handleMpvLine(line) {
    var msg
    try { msg = JSON.parse(line) } catch (e) { return }
    if (msg.event !== "end-file") return
    if (msg.reason === "eof" && loadedKey === "preview") {
      stopPreview()
    } else if (msg.reason === "eof" && loadedKey.indexOf("between|") === 0) {
      endBetween()
    } else if (msg.reason === "eof" && kkActive && loadedKey === trackKey) {
      playNextKK()
    } else if (msg.reason === "error" && loadedKey === "preview") {
      stopPreview()
      lastError = "Couldn't play that preview"
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
      // No mpris script either, so our own mpv never shows up as "other media".
      "--load-scripts=no",
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
      var state = !root.playing ? "Paused" : (root.heldPaused ? "On hold for " + root.otherMediaName : (root.heldQuiet ? "Quieter for " + root.otherMediaName : "Playing"))
      return state + ": " + root.title + " - " + root.subtitle
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
