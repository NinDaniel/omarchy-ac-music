.pragma library
.import "Data.js" as Data

// Pure logic shared by Service.qml and the panel pages: config normalization,
// game picking, K.K. scheduling, weather mapping, and track URLs. No QML types
// in here so it stays easy to reason about (and to test with plain node).

var BASE_URL = "https://acmusicext.com/static"

var GAMES = [
  { id: "animal-crossing", short: "GC", name: "Animal Crossing", tooltip: "Animal Crossing (GameCube)" },
  { id: "wild-world", short: "WW", name: "Wild World", tooltip: "Wild World / City Folk" },
  { id: "new-leaf", short: "NL", name: "New Leaf", tooltip: "New Leaf" },
  { id: "new-horizons", short: "NH", name: "New Horizons", tooltip: "New Horizons" }
]

var GAME_IDS = GAMES.map(function(g) { return g.id })
var WEATHERS = ["sunny", "raining", "snowing"]

// K.K. can be picked by Random like a fifth game (opt-in per hour).
var KK_ID = "kk"
var KK_COLUMN = { id: KK_ID, short: "KK", name: "K.K. Slider", tooltip: "K.K. Slider: his songs instead of a game's hourly theme" }
var GRID_COLUMNS = GAMES.concat([KK_COLUMN])
var GRID_IDS = GAME_IDS.concat([KK_ID])

var KK_VERSIONS = ["live", "aircheck"]
var DAY_NAMES = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
var BETWEEN_MODES = ["off", "every", "2", "3", "hours"]

function gameInfo(id) {
  for (var i = 0; i < GRID_COLUMNS.length; i++) if (GRID_COLUMNS[i].id === id) return GRID_COLUMNS[i]
  return null
}

function gameName(id) {
  var g = gameInfo(id)
  return g ? g.name : "Random"
}

function weatherName(w) {
  if (w === "raining") return "Raining"
  if (w === "snowing") return "Snowing"
  return "Sunny"
}

// ---- Config -------------------------------------------------------------

// K.K. starts unticked in every hour; the four games start ticked.
function allHours() {
  var hours = {}
  for (var h = 0; h < 24; h++) hours[String(h)] = GAME_IDS.slice()
  return hours
}

// One 24-hour grid per weather: { sunny: {"0": [...], ...}, raining: ..., snowing: ... }
function allWeatherHours() {
  var grids = {}
  WEATHERS.forEach(function(w) { grids[w] = allHours() })
  return grids
}

function normalizeGrid(raw, fallback) {
  var grid = {}
  for (var h = 0; h < 24; h++) {
    var list = raw && Array.isArray(raw[String(h)]) ? raw[String(h)] : fallback[String(h)]
    grid[String(h)] = GRID_IDS.filter(function(id) { return list.indexOf(id) >= 0 })
  }
  return grid
}

// Accepts the per-weather shape, the single grid from v0.3 and earlier (which
// becomes the starting grid for every weather), or a mix of both: a weather's
// own grid wins, and any hours it lacks come from the old single grid.
function normalizeHours(raw) {
  var r = raw && typeof raw === "object" ? raw : {}
  var base = normalizeGrid(r, allHours())
  var grids = {}
  WEATHERS.forEach(function(w) {
    var own = r[w] && typeof r[w] === "object" ? r[w] : null
    grids[w] = own ? normalizeGrid(own, base) : cloneGrid(base)
  })
  return grids
}

function cloneGrid(grid) {
  var out = {}
  for (var k in grid) out[k] = grid[k].slice()
  return out
}

function defaultConfig() {
  return {
    version: 1,
    playing: true,
    volume: 0.5,
    game: "new-horizons",
    weather: "auto",
    // "hourly", "daily", or "interval" (a new game every shuffleMinutes).
    randomMode: "hourly",
    shuffleMinutes: 15,
    hours: allWeatherHours(),
    kk: {
      // Concert window: on these days (0 = Sunday), from `start` until `end`
      // (hours; 24 = midnight). An end at or before the start runs past
      // midnight into the next morning.
      concerts: { enabled: true, days: [6], start: 20, end: 24 },
      always: false,
      // "version/song" keys the user unticked. Out of the box every song's
      // live version is ticked and its aircheck isn't, as in the games.
      off: migrateKKOff({}),
      // One K.K. song as the hour changes: "off", "every", "2", "3", or
      // "hours" (only the hours listed in `hours`).
      between: { mode: "off", hours: [] }
    },
    fade: true,
    notify: false,
    // Even out loudness between songs, using measurements of cached songs.
    levelVolume: true,
    // Each day from `start` to `end` (hours, same rules as concerts), either
    // pause the music or turn it down; it comes back when they end.
    quiet: { enabled: false, start: 23, end: 7, mode: "pause" },
    // Recently played songs kept in ~/.cache/ac-music, oldest dropped first.
    cache: { enabled: true, limitMB: 300 },
    // What happens at login: "play", "wait" (stay paused), or "resume".
    atLogin: "play",
    // When another media player plays: "pause", "lower", or "ignore".
    otherMedia: "pause"
  }
}

function pick(value, allowed, fallback) {
  return allowed.indexOf(value) >= 0 ? value : fallback
}

function bool(value, fallback) {
  return typeof value === "boolean" ? value : fallback
}

function intIn(value, lo, hi, fallback) {
  var n = Math.round(Number(value))
  return isNaN(n) || n < lo || n > hi ? fallback : n
}

function hourList(raw) {
  if (!Array.isArray(raw)) return []
  var out = []
  raw.forEach(function(h) {
    var n = intIn(h, 0, 23, -1)
    if (n >= 0 && out.indexOf(n) < 0) out.push(n)
  })
  return out.sort(function(a, b) { return a - b })
}

function kkKey(version, song) {
  return version + "/" + song
}

// v0.4 and earlier had one version setting plus a list of skipped songs;
// turn those into per-version unticks.
function migrateKKOff(kk) {
  var off = []
  var skip = Array.isArray(kk.skip) ? kk.skip : []
  Data.kkSongs.forEach(function(song) {
    if (skip.indexOf(song) >= 0) {
      off.push(kkKey("live", song), kkKey("aircheck", song))
      return
    }
    if (kk.version === "aircheck") off.push(kkKey("live", song))
    else if (kk.version !== "both") off.push(kkKey("aircheck", song))
  })
  return off
}

function normalizeKK(raw) {
  var d = defaultConfig().kk
  var kk = raw && typeof raw === "object" ? raw : {}

  var concerts
  if (kk.concerts && typeof kk.concerts === "object") {
    var c = kk.concerts
    var days = Array.isArray(c.days) ? c.days.map(Number).filter(function(n) { return n >= 0 && n <= 6 }) : d.concerts.days
    concerts = {
      enabled: bool(c.enabled, d.concerts.enabled),
      days: days.filter(function(n, i) { return days.indexOf(n) === i }).sort(),
      start: intIn(c.start, 0, 23, d.concerts.start),
      end: intIn(c.end, 1, 24, d.concerts.end)
    }
  } else {
    // v0.4 and earlier: a single "Saturday night concerts" switch.
    concerts = { enabled: bool(kk.saturday, true), days: [6], start: 20, end: 24 }
  }

  var between = kk.between && typeof kk.between === "object" ? kk.between : {}

  return {
    concerts: concerts,
    always: bool(kk.always, d.always),
    off: Array.isArray(kk.off) ? kk.off.filter(function(s) { return typeof s === "string" }) : migrateKKOff(kk),
    between: {
      mode: pick(between.mode, BETWEEN_MODES, d.between.mode),
      hours: hourList(between.hours)
    }
  }
}

var CACHE_LIMITS = [100, 300, 500, 1000]

function normalizeQuiet(raw) {
  var d = defaultConfig().quiet
  var q = raw && typeof raw === "object" ? raw : {}
  return {
    enabled: bool(q.enabled, d.enabled),
    start: intIn(q.start, 0, 23, d.start),
    end: intIn(q.end, 1, 24, d.end),
    mode: pick(q.mode, ["pause", "lower"], d.mode)
  }
}

function normalizeCache(raw) {
  var d = defaultConfig().cache
  var c = raw && typeof raw === "object" ? raw : {}
  return {
    enabled: bool(c.enabled, d.enabled),
    limitMB: pick(Math.round(Number(c.limitMB)), CACHE_LIMITS, d.limitMB)
  }
}

// Fill in anything missing or invalid so the rest of the code can trust it.
// Hand-edited files and configs from older versions both pass through here.
function normalizeConfig(raw) {
  var d = defaultConfig()
  var c = raw && typeof raw === "object" ? raw : {}
  var volume = Number(c.volume)
  var minutes = Math.round(Number(c.shuffleMinutes))

  return {
    version: 1,
    playing: bool(c.playing, d.playing),
    volume: isNaN(volume) ? d.volume : Math.max(0, Math.min(1, volume)),
    game: pick(c.game, GAME_IDS.concat(["random"]), d.game),
    weather: pick(c.weather, ["auto"].concat(WEATHERS), d.weather),
    randomMode: pick(c.randomMode, ["hourly", "daily", "interval"], d.randomMode),
    shuffleMinutes: isNaN(minutes) ? d.shuffleMinutes : Math.max(1, Math.min(60, minutes)),
    hours: normalizeHours(c.hours),
    kk: normalizeKK(c.kk),
    fade: bool(c.fade, d.fade),
    notify: bool(c.notify, d.notify),
    levelVolume: bool(c.levelVolume, d.levelVolume),
    quiet: normalizeQuiet(c.quiet),
    cache: normalizeCache(c.cache),
    atLogin: pick(c.atLogin, ["play", "wait", "resume"], d.atLogin),
    otherMedia: pick(c.otherMedia, ["pause", "lower", "ignore"], d.otherMedia)
  }
}

function clone(obj) {
  return JSON.parse(JSON.stringify(obj))
}

// ---- Picking ------------------------------------------------------------

// Stable string hash so a given day/hour always lands on the same game:
// restarting the shell mid-hour doesn't change what's playing.
function hash(str) {
  var h = 5381
  for (var i = 0; i < str.length; i++) h = ((h * 33) ^ str.charCodeAt(i)) >>> 0
  return h
}

function dateKey(date) {
  return date.getFullYear() + "-" + (date.getMonth() + 1) + "-" + date.getDate()
}

// Whether a grid box is ticked. The GameCube game has no rain music (it plays
// its sunny theme), so its rain column follows the sunny grid.
function ticked(config, weather, hour, id) {
  var w = weather === "raining" && id === "animal-crossing" ? "sunny" : weather
  return config.hours[w][String(hour)].indexOf(id) >= 0
}

// Games (and possibly K.K.) allowed for an hour by the grids. An hour with
// nothing ticked falls back to the four games rather than going silent.
function allowedGames(config, hour, weather) {
  var w = config.hours[weather] ? weather : "sunny"
  var list = GRID_IDS.filter(function(id) { return ticked(config, w, hour, id) })
  return list.length > 0 ? list : GAME_IDS.slice()
}

// How many of the four games' boxes are unticked across all three weathers
// (K.K. starts unticked, so it isn't counted; GC's rain column mirrors sunny).
function skippedCount(config) {
  var n = 0
  WEATHERS.forEach(function(w) {
    for (var h = 0; h < 24; h++) {
      GAME_IDS.forEach(function(id) {
        if (w === "raining" && id === "animal-crossing") return
        if (!ticked(config, w, h, id)) n++
      })
    }
  })
  return n
}

// How many hour boxes have K.K. ticked across all three weathers.
function kkHourCount(config) {
  var n = 0
  WEATHERS.forEach(function(w) {
    for (var h = 0; h < 24; h++) if (ticked(config, w, h, KK_ID)) n++
  })
  return n
}

// Which shuffle slot of the hour a time falls in (always 0 unless Random is
// switching games every few minutes).
function shuffleSlot(config, date) {
  if (config.game !== "random" || config.randomMode !== "interval") return 0
  return Math.floor(date.getMinutes() / config.shuffleMinutes)
}

// Deterministic shuffle of `list`, seeded by a string.
function shuffled(list, seed) {
  var out = list.slice()
  var h = hash(seed)
  for (var i = out.length - 1; i > 0; i--) {
    h = hash(seed + "|" + h)
    var j = h % (i + 1)
    var tmp = out[i]; out[i] = out[j]; out[j] = tmp
  }
  return out
}

function pickGame(config, day, hour, salt, slot, weather) {
  if (config.game !== "random") return config.game
  var allowed = allowedGames(config, hour, weather || "sunny")
  if (config.randomMode === "interval") {
    // Walk a per-hour shuffled order: every switch lands on a different game
    // and all allowed games come up before any repeats.
    var order = shuffled(allowed, day + "|" + hour + "|" + salt)
    return order[(slot || 0) % order.length]
  }
  if (config.randomMode === "daily") {
    var daily = GRID_IDS[hash(day + "|" + salt) % GRID_IDS.length]
    if (allowed.indexOf(daily) >= 0) return daily
  }
  return allowed[hash(day + "|" + hour + "|" + salt) % allowed.length]
}

// The original GameCube game has no rain music; it plays its sunny theme.
function trackWeather(game, weather) {
  if (game === "animal-crossing" && weather === "raining") return "sunny"
  return weather
}

// ---- K.K. schedule ------------------------------------------------------

// Whether `date` falls in a window that starts at `start` on one of `days`
// and ends at `end` (24 = midnight). An end at or before the start runs past
// midnight: the evening part on a listed day, or the early-morning part on
// the day after one.
function inWindow(days, start, end, date) {
  var day = date.getDay()
  var hour = date.getHours()
  if (end > start) return days.indexOf(day) >= 0 && hour >= start && hour < end
  var yesterday = (day + 6) % 7
  return (days.indexOf(day) >= 0 && hour >= start) || (days.indexOf(yesterday) >= 0 && hour < end)
}

var EVERY_DAY = [0, 1, 2, 3, 4, 5, 6]

function inConcert(concerts, date) {
  if (!concerts.enabled || concerts.days.length === 0) return false
  return inWindow(concerts.days, concerts.start, concerts.end, date)
}

function inQuiet(quiet, date) {
  return quiet.enabled && inWindow(EVERY_DAY, quiet.start, quiet.end, date)
}

// K.K. by schedule (always, or a concert). K.K. picked from the grid is
// handled by pickGame returning KK_ID.
function isKKTime(config, date) {
  return config.kk.always || inConcert(config.kk.concerts, date)
}

// Whether to play one K.K. song as this hour begins.
function wantsBetween(config, hour) {
  var mode = config.kk.between.mode
  if (mode === "every") return true
  if (mode === "2") return hour % 2 === 0
  if (mode === "3") return hour % 3 === 0
  if (mode === "hours") return config.kk.between.hours.indexOf(hour) >= 0
  return false
}

function endLabel(window) {
  if (window.end === 24) return "midnight"
  return hourLabel(window.end % 24) + (window.end <= window.start ? " (next day)" : "")
}

function quietText(quiet) {
  if (!quiet.enabled) return "Off"
  return (quiet.mode === "lower" ? "Quieter" : "Paused") + " from " + hourLabel(quiet.start) + " to " + endLabel(quiet)
}

function daysText(days) {
  var sorted = days.slice().sort()
  if (sorted.length === 7) return "Every day"
  if (sorted.join() === "1,2,3,4,5") return "Weekdays"
  if (sorted.join() === "0,6") return "Weekends"
  return sorted.map(function(d) { return DAY_NAMES[d] }).join(", ")
}

function concertText(concerts) {
  if (!concerts.enabled || concerts.days.length === 0) return "No concerts"
  return daysText(concerts.days) + ", " + hourLabel(concerts.start) + " to " + endLabel(concerts)
}

// ---- K.K. songs ---------------------------------------------------------

var KK_GROUPS = [
  { prefix: "AC", name: "Animal Crossing" },
  { prefix: "CF", name: "City Folk" },
  { prefix: "NL", name: "New Leaf" },
  { prefix: "NH", name: "New Horizons" }
]

function kkGroup(song) {
  return song.substring(0, song.indexOf(" - "))
}

function kkOn(config, version, song) {
  return config.kk.off.indexOf(kkKey(version, song)) < 0
}

// Versions of a song K.K. may play.
function kkVersionsFor(config, song) {
  return KK_VERSIONS.filter(function(v) { return kkOn(config, v, song) })
}

// Songs with at least one version ticked, or every song if none are.
function kkAllowed(config, songs) {
  var allowed = songs.filter(function(s) { return kkVersionsFor(config, s).length > 0 })
  return allowed.length > 0 ? allowed : songs.slice()
}

// Pick the next K.K. song, avoiding recent ones while there's enough choice.
function pickKKSong(allowed, recent) {
  var span = Math.min(20, allowed.length - 1)
  var avoid = span > 0 ? recent.slice(-span) : []
  var fresh = allowed.filter(function(s) { return avoid.indexOf(s) < 0 })
  return fresh[Math.floor(Math.random() * fresh.length)]
}

// Next song plus which of its ticked versions to play.
function pickKK(config, songs, recent) {
  var song = pickKKSong(kkAllowed(config, songs), recent)
  var versions = kkVersionsFor(config, song)
  if (versions.length === 0) versions = KK_VERSIONS.slice()
  return { song: song, version: versions[Math.floor(Math.random() * versions.length)] }
}

function kkCounts(config, songs) {
  var live = 0, aircheck = 0, any = 0
  songs.forEach(function(s) {
    var l = kkOn(config, "live", s), a = kkOn(config, "aircheck", s)
    if (l) live++
    if (a) aircheck++
    if (l || a) any++
  })
  return { live: live, aircheck: aircheck, any: any, total: songs.length }
}

// ---- Tracks -------------------------------------------------------------

function formatHour(hour) {
  if (hour === 0) return "12am"
  if (hour === 12) return "12pm"
  return hour < 12 ? hour + "am" : (hour - 12) + "pm"
}

function hourLabel(hour) {
  return formatHour(hour).toUpperCase().replace(/(AM|PM)$/, " $1")
}

function hourlyUrl(game, weather, hour) {
  return BASE_URL + "/" + game + "/" + weather + "/" + formatHour(hour) + ".ogg"
}

function kkUrl(version, song) {
  return BASE_URL + "/kk/" + version + "/" + encodeURIComponent(song) + ".ogg"
}

// Where a server file lives in the song cache, relative to the cache folder
// (the URL's path after /static/, decoded: "new-leaf/raining/11am.ogg").
function cacheRelPath(url) {
  var prefix = BASE_URL + "/"
  return url.indexOf(prefix) === 0 ? decodeURIComponent(url.substring(prefix.length)) : ""
}

// ---- Volume levelling ----------------------------------------------------

// Loudness every song is brought to. The hourly themes already sit near it;
// it mostly lifts the quiet airchecks and tames the odd loud one.
var LEVEL_TARGET = -18
var LEVEL_MAX_DB = 12

// Gain (dB) for a song measured at `loudness` LUFS with `peak` dBTP. Boosts
// stop before the peak passes -1 dBTP, so levelling never clips.
function levelGain(loudness, peak) {
  if (typeof loudness !== "number" || isNaN(loudness)) return 0
  var gain = LEVEL_TARGET - loudness
  if (gain > 0 && typeof peak === "number" && !isNaN(peak)) gain = Math.min(gain, Math.max(0, -1 - peak))
  gain = Math.max(-LEVEL_MAX_DB, Math.min(LEVEL_MAX_DB, gain))
  return Math.round(gain * 10) / 10
}

// One line of `song-cache index`: "rel<TAB>loudness<TAB>peak" (last two may be empty).
function parseCacheLine(line) {
  var parts = String(line).split("\t")
  if (!parts[0]) return null
  var loudness = parseFloat(parts[1])
  var peak = parseFloat(parts[2])
  return {
    rel: parts[0],
    loudness: isNaN(loudness) ? null : loudness,
    peak: isNaN(peak) ? null : peak
  }
}

// mpv's escaping for a value inside a key=value option list: %<bytes>%value.
function mpvQuote(text) {
  var bytes = unescape(encodeURIComponent(text)).length
  return "%" + bytes + "%" + text
}

// Album cover for a K.K. song (128x128 PNG).
function kkArtUrl(song) {
  return song ? BASE_URL + "/kk/art/" + encodeURIComponent(song) + ".png" : ""
}

// "NH - Drivin'" -> "Drivin'"
function kkTitle(song) {
  var i = song.indexOf(" - ")
  return i >= 0 ? song.substring(i + 3) : song
}

function versionName(version) {
  return version === "aircheck" ? "Aircheck" : "Live"
}

function loopPoints(loopTimes, game, weather, hour) {
  var g = loopTimes[game] || {}
  var w = g[weather] || {}
  return w[String(hour)] || null
}

// ---- Weather ------------------------------------------------------------

// WMO weather interpretation codes (Open-Meteo `weather_code`).
function weatherFromWmo(code) {
  var c = Number(code)
  if ([71, 73, 75, 77, 85, 86].indexOf(c) >= 0) return "snowing"
  if ((c >= 51 && c <= 67) || (c >= 80 && c <= 82) || c >= 95) return "raining"
  return "sunny"
}

// Location from Omarchy's weather widget state file, if it has coordinates.
function parseOmarchyLocation(text) {
  try {
    var data = JSON.parse(text || "{}")
    var lat = parseFloat(String(data.latitude))
    var lon = parseFloat(String(data.longitude))
    if (isNaN(lat) || isNaN(lon)) return { name: String(data.name || ""), latitude: null, longitude: null }
    return { name: String(data.name || ""), latitude: lat, longitude: lon }
  } catch (e) {
    return { name: "", latitude: null, longitude: null }
  }
}

// ---- Settings menu summaries ---------------------------------------------

function randomModeText(config) {
  if (config.randomMode === "daily") return "one game per day"
  if (config.randomMode === "interval") return "new game every " + config.shuffleMinutes + " min"
  return "new game every hour"
}

function hourlySummary(config) {
  var skipped = skippedCount(config)
  var kkHours = kkHourCount(config)
  var tail = (skipped > 0 ? " · " + skipped + " skipped" : "") + (kkHours > 0 ? " · K.K. in " + kkHours + " hours" : "")
  if (config.game !== "random") return gameName(config.game) + " picked · grid applies to Random" + tail
  return "Random · " + randomModeText(config) + tail
}

function betweenText(between) {
  if (between.mode === "every") return "between every hour"
  if (between.mode === "2" || between.mode === "3") return "between every " + between.mode + " hours"
  if (between.mode === "hours") return "between " + between.hours.length + " hour" + (between.hours.length === 1 ? "" : "s")
  return ""
}

function kkSummary(config, songs) {
  var parts = [config.kk.always ? "All the time" : concertText(config.kk.concerts)]
  var between = betweenText(config.kk.between)
  if (between) parts.push(between)
  var n = kkCounts(config, songs)
  parts.push(n.any + " of " + n.total + " songs")
  return parts.join(" · ")
}

function playbackSummary(config) {
  var other = { pause: "Pause", lower: "Lower", ignore: "Keep playing" }[config.otherMedia]
  var login = { play: "Play", wait: "Wait", resume: "Remember" }[config.atLogin]
  var parts = ["Fade " + (config.fade ? "on" : "off"), other + " for other media", login + " at login"]
  if (config.quiet.enabled) parts.push("quiet " + hourLabel(config.quiet.start) + " to " + endLabel(config.quiet))
  return parts.join(" · ")
}
