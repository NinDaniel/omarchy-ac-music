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
  // Quiet hours: paused or turned down during the set window each day.
  readonly property bool quietNow: Model.inQuiet(config.quiet, now)
  readonly property bool quietPaused: quietNow && config.quiet.mode === "pause"
  readonly property bool quietLowered: quietNow && config.quiet.mode === "lower"
  // Actually making sound: the user wants music and nothing is holding it.
  readonly property bool audible: playing && !heldPaused && !quietPaused
  // Sleep timer: when to fade out and pause (ms since epoch; 0 = off).
  property real sleepAt: 0
  property int sleepMinutesLeft: 0
  // Option picked in Settings: "off", "hour", or a number of minutes.
  property string sleepChoice: "off"
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
  readonly property bool ready: configLoaded && loginApplied && mprisChecked && (!autoWeather || liveWeather !== "" || weatherGrace.expired)
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

  // ---- Song cache (~/.cache/ac-music) ----
  readonly property string cacheDir: (Quickshell.env("XDG_CACHE_HOME") || home + "/.cache") + "/ac-music"
  readonly property string fetchScript: {
    var url = String(Qt.resolvedUrl("bin/cache-fetch"))
    return decodeURIComponent(url.indexOf("file://") === 0 ? url.substring(7) : url)
  }
  // Relative paths of songs already on disk.
  property var cached: ({})
  property real cacheBytes: -1
  property var downloadQueue: []
  property string prefetchedFor: ""

  // ---- mpv ----
  // mpv-mpris (part of Omarchy's base install) makes mpv a system media
  // player, so media keys and Omarchy's media controls work.
  property string mprisScript: ""
  property bool mprisChecked: false
  // Last pause state we asked mpv for; a change we didn't ask for came from
  // the media keys or the media widget.
  property bool expectedPause: false
  property bool mpvReady: false
  property var pending: []
  property real appliedVolume: -1
  property bool fading: false
  property string loadedKey: ""

  Component.onCompleted: {
    AcBridge.Bridge.service = root
    rescanCache()
  }
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

  // mpv-mpris names the player after mpv's audio client name ("AC Music"),
  // e.g. org.mpris.MediaPlayer2.mpv.AC_Music.instance-XXXX.
  function isOwnPlayer(p) {
    return String(p.dbusName).indexOf("org.mpris.MediaPlayer2.mpv.AC_Music") === 0
  }

  function playingOtherPlayer() {
    for (var i = 0; i < mprisPlayers.length; i++) {
      var p = mprisPlayers[i]
      if (p && p.isPlaying && !isOwnPlayer(p)) return p
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
      if (root.sleepAt > 0) {
        if (d.getTime() >= root.sleepAt) {
          root.sleepAt = 0
          root.sleepMinutesLeft = 0
          root.sleepChoice = "off"
          sleepFade.begin()
        } else {
          root.sleepMinutesLeft = Math.ceil((root.sleepAt - d.getTime()) / 60000)
        }
      }
      if (root.audible && root.config.cache.enabled && d.getMinutes() >= 50) root.prefetchNextHour(d)
    }
  }

  // ---- Sleep timer -------------------------------------------------------

  // minutes > 0: stop after that long; -1: at the end of this hour; 0: cancel.
  function setSleep(minutes) {
    sleepFade.stop()
    if (fading) restoreVolume()
    var d = new Date()
    sleepChoice = minutes === 0 ? "off" : (minutes < 0 ? "hour" : String(minutes))
    if (minutes === 0) {
      sleepAt = 0
    } else if (minutes < 0) {
      // Finish the fade just before the hour so the next hour never starts.
      var end = new Date(d)
      end.setMinutes(59, 50, 0)
      sleepAt = end.getTime()
    } else {
      sleepAt = d.getTime() + minutes * 60000
    }
    sleepMinutesLeft = sleepAt > 0 ? Math.max(1, Math.ceil((sleepAt - d.getTime()) / 60000)) : 0
  }

  // Slow fade (about 8 seconds), then pause.
  Timer {
    id: sleepFade
    interval: 200
    repeat: true
    property int step: 0
    readonly property int steps: 40
    function begin() {
      if (!root.audible) {
        root.setPlaying(false)
        return
      }
      root.fading = true
      step = 0
      restart()
    }
    onTriggered: {
      step++
      root.send(["set_property", "volume", Math.max(0, Math.round(root.targetVolume() * (1 - step / steps)))])
      if (step >= steps) {
        stop()
        root.setPlaying(false)
        root.restoreVolume()
      }
    }
  }

  // ---- Song cache --------------------------------------------------------

  // Local copy of a server file when we have it; otherwise the URL, and the
  // file is fetched in the background for next time.
  function sourceFor(url) {
    if (!config.cache.enabled) return url
    var rel = Model.cacheRelPath(url)
    if (!rel) return url
    if (cached[rel]) {
      var path = cacheDir + "/" + rel
      // Mark it recently played so trimming keeps it.
      Quickshell.execDetached(["touch", "-c", path])
      return path
    }
    queueDownload(url)
    return url
  }

  function queueDownload(url) {
    var rel = Model.cacheRelPath(url)
    if (!config.cache.enabled || !rel || cached[rel]) return
    if (downloadQueue.indexOf(url) >= 0 || (downloadProc.running && downloadProc.url === url)) return
    downloadQueue = downloadQueue.concat([url])
    pumpDownloads()
  }

  function pumpDownloads() {
    if (downloadProc.running || downloadQueue.length === 0) return
    var url = downloadQueue[0]
    downloadQueue = downloadQueue.slice(1)
    downloadProc.url = url
    downloadProc.command = ["bash", fetchScript, url, cacheDir, Model.cacheRelPath(url), String(config.cache.limitMB * 1048576)]
    downloadProc.running = true
  }

  // In the last ten minutes of an hour, fetch the next hour's song so the
  // hour change starts instantly.
  function prefetchNextHour(d) {
    var next = new Date(d.getTime() + 15 * 60000)
    var key = Model.dateKey(next) + "|" + next.getHours()
    if (prefetchedFor === key) return
    prefetchedFor = key
    if (Model.isKKTime(config, next)) return
    var g = Model.pickGame(config, Model.dateKey(next), next.getHours(), 0, 0, weather)
    if (g === Model.KK_ID) return
    queueDownload(Model.hourlyUrl(g, Model.trackWeather(g, weather), next.getHours()))
  }

  function rescanCache() {
    if (cacheIndexProc.running) return
    cacheIndexProc.command = ["find", cacheDir, "-type", "f", "-name", "*.ogg", "-printf", "%P\\n"]
    cacheIndexProc.running = true
  }

  function refreshCacheSize() {
    if (cacheSizeProc.running) return
    cacheSizeProc.command = ["du", "-sb", cacheDir]
    cacheSizeProc.running = true
  }

  function clearCache() {
    downloadQueue = []
    Quickshell.execDetached(["rm", "-rf", cacheDir])
    cached = {}
    cacheBytes = 0
  }

  Process {
    id: downloadProc
    property string url: ""
    onExited: function(exitCode) {
      root.rescanCache()
      root.pumpDownloads()
    }
  }

  Process {
    id: cacheIndexProc
    stdout: StdioCollector {
      onStreamFinished: {
        var map = {}
        text.split("\n").forEach(function(line) { if (line) map[line] = true })
        root.cached = map
        root.refreshCacheSize()
      }
    }
  }

  Process {
    id: cacheSizeProc
    stdout: StdioCollector {
      onStreamFinished: {
        var bytes = parseInt(String(text).split("\t")[0], 10)
        root.cacheBytes = isNaN(bytes) ? 0 : bytes
      }
    }
  }

  // Look for mpv-mpris once; mpv starts after this (see `ready`).
  Process {
    id: mprisCheck
    running: true
    command: ["sh", "-c", "for f in /usr/lib/mpv-mpris/mpris.so /etc/mpv/scripts/mpris.so; do [ -f \"$f\" ] && { echo \"$f\"; exit 0; }; done; exit 0"]
    stdout: StdioCollector {
      onStreamFinished: {
        root.mprisScript = String(text).trim()
        root.mprisChecked = true
      }
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
  onQuietLoweredChanged: syncVolume()

  function send(args) {
    if (args[0] === "set_property" && args[1] === "pause") expectedPause = !!args[2]
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
    return Math.round(config.volume * (heldQuiet || quietLowered ? 0.25 : 1) * 100)
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
    var title = Model.gameName(game) + " · " + Model.hourLabel(hour) + " · " + Model.weatherName(trackWeather)
    opts += ",force-media-title=" + Model.mpvQuote(title)
    send(["loadfile", sourceFor(Model.hourlyUrl(game, trackWeather, hour)), "replace", -1, opts])
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
    send(["loadfile", sourceFor(Model.kkUrl(choice.version, choice.song)), "replace", -1, kkOptions(choice.song, choice.version)])
    send(["set_property", "pause", !audible])
    restoreVolume()
  }

  function kkOptions(song, version) {
    var title = Model.kkTitle(song) + " · K.K. Slider (" + Model.versionName(version) + ")"
    return "loop-file=no,ab-loop-a=no,ab-loop-b=no,force-media-title=" + Model.mpvQuote(title)
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
    send(["loadfile", sourceFor(Model.kkUrl(version, song)), "replace", -1, kkOptions(song, version)])
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
    if (msg.event === "property-change" && msg.name === "pause") {
      handleExternalPause(!!msg.data)
      return
    }
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

  // Media keys or the media widget paused/resumed mpv directly: follow along
  // so the panel and the saved play state stay in sync.
  function handleExternalPause(paused) {
    if (paused === expectedPause) return
    expectedPause = paused
    if (paused) {
      if (playing) setPlaying(false)
      return
    }
    if (!playing) setPlaying(true)
    // Pressing play while another player had us on hold means "play anyway".
    if (otherMediaHold) {
      holdTimer.stop()
      releaseTimer.stop()
      otherMediaHold = false
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
      // No auto-loaded scripts; mpv-mpris is loaded explicitly below.
      "--load-scripts=no",
      "--idle=yes",
      "--no-video",
      "--no-terminal",
      "--audio-display=no",
      "--cache=yes",
      "--demuxer-max-back-bytes=64MiB",
      "--audio-client-name=AC Music",
      "--input-ipc-server=" + root.socketPath
    ].concat(root.mprisScript ? ["--script=" + root.mprisScript] : [])
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
      ipc.write(JSON.stringify({ command: ["observe_property", 1, "pause"] }) + "\n")
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
    function sleep(arg: string): string {
      if (arg === "off" || arg === "0") root.setSleep(0)
      else if (arg === "hour") root.setSleep(-1)
      else {
        var m = parseInt(arg, 10)
        if (isNaN(m) || m <= 0) return "usage: sleep <minutes | hour | off>"
        root.setSleep(m)
      }
      return root.sleepAt > 0 ? "stopping in " + root.sleepMinutesLeft + " min" : "sleep timer off"
    }
    function clearCache(): string { root.clearCache(); return "cache cleared" }
    function requestView(view: string): string { root.requestedView = view; return "ok" }
    function status(): string {
      var state = !root.playing ? "Paused"
        : root.quietPaused ? "Quiet hours"
        : root.heldPaused ? "On hold for " + root.otherMediaName
        : root.heldQuiet ? "Quieter for " + root.otherMediaName
        : root.quietLowered ? "Playing (quiet hours)" : "Playing"
      var sleep = root.sleepAt > 0 ? " (stops in " + root.sleepMinutesLeft + " min)" : ""
      return state + ": " + root.title + " - " + root.subtitle + sleep
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
