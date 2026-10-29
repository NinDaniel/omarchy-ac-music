.pragma library

// Pure logic shared by Service.qml and Panel.qml: config normalization, game
// picking, weather mapping, and track URLs. No QML types in here so it stays
// easy to reason about (and to test with plain node).

var BASE_URL = "https://acmusicext.com/static"

var GAMES = [
  { id: "animal-crossing", short: "GC", name: "Animal Crossing", tooltip: "Animal Crossing (GameCube)" },
  { id: "wild-world", short: "WW", name: "Wild World", tooltip: "Wild World / City Folk" },
  { id: "new-leaf", short: "NL", name: "New Leaf", tooltip: "New Leaf" },
  { id: "new-horizons", short: "NH", name: "New Horizons", tooltip: "New Horizons" }
]

var GAME_IDS = GAMES.map(function(g) { return g.id })
var WEATHERS = ["sunny", "raining", "snowing"]
var KK_VERSIONS = ["live", "aircheck", "both"]

function gameInfo(id) {
  for (var i = 0; i < GAMES.length; i++) if (GAMES[i].id === id) return GAMES[i]
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
    grid[String(h)] = GAME_IDS.filter(function(id) { return list.indexOf(id) >= 0 })
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
    // `skip` lists K.K. songs the user unticked (new songs default to on).
    kk: { saturday: true, always: false, version: "live", skip: [] },
    fade: true,
    notify: false,
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

// Fill in anything missing or invalid so the rest of the code can trust it.
// Hand-edited files and configs from older versions both pass through here.
function normalizeConfig(raw) {
  var d = defaultConfig()
  var c = raw && typeof raw === "object" ? raw : {}
  var kk = c.kk && typeof c.kk === "object" ? c.kk : {}
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
    kk: {
      saturday: bool(kk.saturday, d.kk.saturday),
      always: bool(kk.always, d.kk.always),
      version: pick(kk.version, KK_VERSIONS, d.kk.version),
      skip: Array.isArray(kk.skip) ? kk.skip.filter(function(s) { return typeof s === "string" }) : []
    },
    fade: bool(c.fade, d.fade),
    notify: bool(c.notify, d.notify),
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

// Games allowed for an hour by the settings grid. An hour with nothing ticked
// falls back to every game rather than going silent.
function allowedGames(config, hour, weather) {
  var grid = config.hours[weather] || config.hours.sunny
  var list = grid[String(hour)] || []
  return list.length > 0 ? list : GAME_IDS.slice()
}

// How many hour/game boxes are unticked across all three weathers.
function skippedCount(config) {
  var n = 0
  WEATHERS.forEach(function(w) {
    for (var h = 0; h < 24; h++) n += GAME_IDS.length - config.hours[w][String(h)].length
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
    var daily = GAME_IDS[hash(day + "|" + salt) % GAME_IDS.length]
    if (allowed.indexOf(daily) >= 0) return daily
  }
  return allowed[hash(day + "|" + hour + "|" + salt) % allowed.length]
}

// The original GameCube game has no rain music; it plays its sunny theme.
function trackWeather(game, weather) {
  if (game === "animal-crossing" && weather === "raining") return "sunny"
  return weather
}

function isKKTime(config, date) {
  if (config.kk.always) return true
  return config.kk.saturday && date.getDay() === 6 && date.getHours() >= 20
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

// "NH - Drivin'" -> "Drivin'"
function kkTitle(song) {
  var i = song.indexOf(" - ")
  return i >= 0 ? song.substring(i + 3) : song
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

// ---- K.K. ---------------------------------------------------------------

var KK_GROUPS = [
  { prefix: "AC", name: "Animal Crossing" },
  { prefix: "CF", name: "City Folk" },
  { prefix: "NL", name: "New Leaf" },
  { prefix: "NH", name: "New Horizons" }
]

function kkGroup(song) {
  return song.substring(0, song.indexOf(" - "))
}

// Songs K.K. may play: everything not skipped, or everything if all are.
function kkAllowed(config, songs) {
  var allowed = songs.filter(function(s) { return config.kk.skip.indexOf(s) < 0 })
  return allowed.length > 0 ? allowed : songs.slice()
}

// Pick the next K.K. song, avoiding recent ones while there's enough choice.
function pickKKSong(allowed, recent) {
  var span = Math.min(20, allowed.length - 1)
  var avoid = span > 0 ? recent.slice(-span) : []
  var fresh = allowed.filter(function(s) { return avoid.indexOf(s) < 0 })
  return fresh[Math.floor(Math.random() * fresh.length)]
}

// ---- Settings menu summaries ---------------------------------------------

function randomModeText(config) {
  if (config.randomMode === "daily") return "one game per day"
  if (config.randomMode === "interval") return "new game every " + config.shuffleMinutes + " min"
  return "new game every hour"
}

function hourlySummary(config) {
  var skipped = skippedCount(config)
  var tail = skipped > 0 ? " · " + skipped + " skipped" : ""
  if (config.game !== "random") return gameName(config.game) + " picked · grid applies to Random" + tail
  return "Random · " + randomModeText(config) + tail
}

function kkSummary(config, songs) {
  var when = config.kk.always ? "All the time" : (config.kk.saturday ? "Saturday nights" : "Off")
  var version = config.kk.version === "both" ? "Live & aircheck" : (config.kk.version === "aircheck" ? "Aircheck" : "Live")
  var on = songs.filter(function(s) { return config.kk.skip.indexOf(s) < 0 }).length
  return when + " · " + version + " · " + on + " of " + songs.length + " songs"
}

function playbackSummary(config) {
  var other = { pause: "Pause", lower: "Lower", ignore: "Keep playing" }[config.otherMedia]
  var login = { play: "Play", wait: "Wait", resume: "Remember" }[config.atLogin]
  return "Fade " + (config.fade ? "on" : "off") + " · " + other + " for other media · " + login + " at login"
}
