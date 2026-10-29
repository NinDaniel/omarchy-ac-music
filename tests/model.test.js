const test = require("node:test")
const assert = require("node:assert/strict")
const { Data, Model } = require("./load")

const ALL = Model.GAME_IDS
const day = (y, m, d, h, min = 0) => new Date(y, m - 1, d, h, min)
// 2026-10-31 is a Saturday.
const SAT = (h, min) => day(2026, 10, 31, h, min)
const SUN = (h, min) => day(2026, 11, 1, h, min)
const FRI = (h, min) => day(2026, 10, 30, h, min)
const THU = (h, min) => day(2026, 10, 29, h, min)

function flatGrid(overrides = {}) {
  const grid = {}
  for (let h = 0; h < 24; h++) grid[h] = ALL.slice()
  return Object.assign(grid, overrides)
}

// ---- Config normalization and migration ----------------------------------

test("defaults: four games ticked, K.K. unticked, live versions only", () => {
  const c = Model.normalizeConfig({})
  for (const w of Model.WEATHERS) for (let h = 0; h < 24; h++) assert.deepEqual(c.hours[w][h], ALL)
  assert.equal(Model.kkHourCount(c), 0)
  const n = Model.kkCounts(c, Data.kkSongs)
  assert.deepEqual([n.live, n.aircheck, n.any], [95, 0, 95])
  assert.deepEqual(c.kk.concerts, { enabled: true, days: [6], start: 20, end: 24 })
  assert.deepEqual(c.kk.between, { mode: "off", hours: [] })
  assert.equal(c.quiet.enabled, false)
  assert.deepEqual(c.cache, { enabled: true, limitMB: 300 })
})

test("garbage input falls back to defaults instead of throwing", () => {
  for (const raw of [null, undefined, 42, "x", [], { hours: "x", kk: 5, quiet: [], cache: "y" }]) {
    const c = Model.normalizeConfig(raw)
    assert.equal(c.game, "new-horizons")
    assert.equal(Object.keys(c.hours).length, 3)
  }
  const c = Model.normalizeConfig({ volume: 7, game: "zelda", weather: "hail", shuffleMinutes: 500, cache: { limitMB: 123 } })
  assert.equal(c.volume, 1)
  assert.equal(c.game, "new-horizons")
  assert.equal(c.weather, "auto")
  assert.equal(c.shuffleMinutes, 60)
  assert.equal(c.cache.limitMB, 300)
})

test("normalizing is stable (normalize(normalize(x)) == normalize(x))", () => {
  const c = Model.normalizeConfig({ game: "random", kk: { version: "both", skip: ["AC - K.K. Aria"] } })
  assert.deepEqual(Model.normalizeConfig(JSON.parse(JSON.stringify(c))), c)
})

test("migrates the v0.3 single grid into all three weathers", () => {
  const c = Model.normalizeConfig({ hours: flatGrid({ 11: ["animal-crossing", "wild-world", "new-horizons"] }) })
  for (const w of Model.WEATHERS) assert.deepEqual(c.hours[w][11], ["animal-crossing", "wild-world", "new-horizons"])
})

test("a weather's own grid wins over a leftover single grid", () => {
  const c = Model.normalizeConfig({ hours: Object.assign(flatGrid({ 5: ["wild-world"] }), { raining: { 12: ["new-leaf"] } }) })
  assert.deepEqual(c.hours.raining[12], ["new-leaf"])
  assert.deepEqual(c.hours.raining[5], ["wild-world"], "missing hours come from the old grid")
  assert.deepEqual(c.hours.sunny[5], ["wild-world"])
})

test("migrates the old Saturday switch into a concert schedule", () => {
  assert.deepEqual(Model.normalizeConfig({ kk: { saturday: true } }).kk.concerts, { enabled: true, days: [6], start: 20, end: 24 })
  assert.equal(Model.normalizeConfig({ kk: { saturday: false } }).kk.concerts.enabled, false)
})

test("migrates the old version setting and skip list into per-version ticks", () => {
  const counts = raw => {
    const n = Model.kkCounts(Model.normalizeConfig({ kk: raw }), Data.kkSongs)
    return [n.live, n.aircheck, n.any]
  }
  assert.deepEqual(counts({ version: "live" }), [95, 0, 95])
  assert.deepEqual(counts({ version: "aircheck" }), [0, 95, 95])
  assert.deepEqual(counts({ version: "both" }), [95, 95, 95])
  const c = Model.normalizeConfig({ kk: { version: "both", skip: ["AC - K.K. Aria"] } })
  assert.deepEqual(Model.kkVersionsFor(c, "AC - K.K. Aria"), [])
})

// ---- Picking games --------------------------------------------------------

test("a picked game always plays, whatever the grid says", () => {
  const c = Model.normalizeConfig({ game: "new-leaf", hours: flatGrid({ 11: ["wild-world"] }) })
  assert.equal(Model.pickGame(c, "d", 11, 0, 0, "sunny"), "new-leaf")
})

test("Random only picks ticked games, per weather", () => {
  const c = Model.normalizeConfig({ game: "random" })
  c.hours.sunny[11] = ["wild-world", "new-horizons"]
  c.hours.raining[11] = ["new-leaf"]
  const picks = w => new Set([...Array(100)].map((_, s) => Model.pickGame(c, "d", 11, s, 0, w)))
  assert.deepEqual([...picks("sunny")].sort(), ["new-horizons", "wild-world"])
  assert.deepEqual([...picks("raining")], ["new-leaf"])
})

test("an hour with nothing ticked falls back to the four games", () => {
  const c = Model.normalizeConfig({ game: "random" })
  c.hours.sunny[3] = []
  assert.deepEqual(Model.allowedGames(c, 3, "sunny"), ALL)
})

test("picks are stable for the same day and hour, and Shuffle (salt) changes them", () => {
  const c = Model.normalizeConfig({ game: "random" })
  const a = Model.pickGame(c, "2026-10-29", 11, 0, 0, "sunny")
  assert.equal(Model.pickGame(c, "2026-10-29", 11, 0, 0, "sunny"), a)
  const salted = new Set([...Array(20)].map((_, s) => Model.pickGame(c, "2026-10-29", 11, s, 0, "sunny")))
  assert.ok(salted.size > 1)
})

test("Once a day keeps one game all day unless that hour unticks it", () => {
  const c = Model.normalizeConfig({ game: "random", randomMode: "daily" })
  const games = new Set([...Array(24)].map((_, h) => Model.pickGame(c, "2026-10-29", h, 0, 0, "sunny")))
  assert.equal(games.size, 1)
  const [daily] = games
  c.hours.sunny[9] = ALL.filter(g => g !== daily)
  assert.notEqual(Model.pickGame(c, "2026-10-29", 9, 0, 0, "sunny"), daily)
  assert.equal(Model.pickGame(c, "2026-10-29", 10, 0, 0, "sunny"), daily)
})

test("Every few minutes: slots follow the clock and never repeat back to back", () => {
  const c = Model.normalizeConfig({ game: "random", randomMode: "interval", shuffleMinutes: 15 })
  assert.deepEqual([0, 14, 15, 29, 30, 59].map(m => Model.shuffleSlot(c, THU(11, m))), [0, 0, 1, 1, 2, 3])
  const seq = [0, 1, 2, 3].map(slot => Model.pickGame(c, "d", 11, 0, slot, "sunny"))
  assert.equal(new Set(seq).size, 4, "all four games before any repeat")
  const seven = Object.assign({}, c, { shuffleMinutes: 7 })
  assert.equal(Model.shuffleSlot(seven, THU(11, 59)), 8)
  assert.equal(Model.shuffleSlot(Object.assign({}, c, { game: "new-leaf" }), THU(11, 40)), 0)
})

test("GameCube's rain column follows the sunny grid; snow is independent", () => {
  const c = Model.normalizeConfig({ game: "random" })
  c.hours.sunny[11] = ["wild-world", "new-leaf"]
  c.hours.raining[11] = ["animal-crossing", "new-leaf"]
  assert.deepEqual(Model.allowedGames(c, 11, "raining"), ["new-leaf"])
  assert.ok(Model.allowedGames(c, 11, "snowing").includes("animal-crossing"))
  assert.equal(Model.trackWeather("animal-crossing", "raining"), "sunny")
  assert.equal(Model.trackWeather("animal-crossing", "snowing"), "snowing")
})

test("K.K. can be picked from the grid, including as an interval slot", () => {
  const c = Model.normalizeConfig({ game: "random", randomMode: "interval", shuffleMinutes: 15 })
  c.hours.raining[12] = ["new-leaf", "kk"]
  c.hours.sunny[12] = ["new-leaf"]
  const seq = [0, 1, 2, 3].map(slot => Model.pickGame(c, "d", 12, 0, slot, "raining"))
  assert.ok(seq.includes("kk"))
  assert.ok(seq.every((g, i) => i === 0 || g !== seq[i - 1]))
  assert.equal(Model.kkHourCount(c), 1)
})

// ---- K.K. schedule ---------------------------------------------------------

test("default concerts: Saturday 8 PM until midnight", () => {
  const c = Model.normalizeConfig({})
  assert.ok(Model.isKKTime(c, SAT(20)) && Model.isKKTime(c, SAT(23, 59)))
  assert.ok(!Model.isKKTime(c, SAT(19, 59)) && !Model.isKKTime(c, SUN(0)) && !Model.isKKTime(c, FRI(21)))
})

test("concerts can run past midnight into the next morning", () => {
  const c = Model.normalizeConfig({ kk: { concerts: { enabled: true, days: [5, 6], start: 22, end: 2 } } })
  assert.ok(Model.isKKTime(c, FRI(22)) && Model.isKKTime(c, SAT(1)) && Model.isKKTime(c, SUN(1)))
  assert.ok(!Model.isKKTime(c, SUN(2)) && !Model.isKKTime(c, FRI(1)) && !Model.isKKTime(c, SAT(21)))
  assert.equal(Model.concertText(c.kk.concerts), "Fri, Sat, 10 PM to 2 AM (next day)")
})

test("a same-day window ends exactly at its end hour", () => {
  const c = Model.normalizeConfig({ kk: { concerts: { enabled: true, days: [1, 2, 3, 4, 5], start: 12, end: 13 } } })
  assert.ok(Model.isKKTime(c, THU(12)) && Model.isKKTime(c, THU(12, 59)))
  assert.ok(!Model.isKKTime(c, THU(13)) && !Model.isKKTime(c, THU(11, 59)) && !Model.isKKTime(c, SAT(12)))
  const q = Model.normalizeConfig({ quiet: { enabled: true, start: 13, end: 15 } }).quiet
  assert.ok(Model.inQuiet(q, THU(14, 59)) && !Model.inQuiet(q, THU(15)))
  assert.equal(Model.concertText(c.kk.concerts), "Weekdays, 12 PM to 1 PM")
})

test("K.K. all the time overrides the schedule; disabled concerts never play", () => {
  assert.ok(Model.isKKTime(Model.normalizeConfig({ kk: { always: true } }), THU(9)))
  assert.ok(!Model.isKKTime(Model.normalizeConfig({ kk: { concerts: { enabled: false, days: [6], start: 20, end: 24 } } }), SAT(21)))
})

test("between-hours modes", () => {
  const cfg = (mode, hours) => Model.normalizeConfig({ kk: { between: { mode, hours } } })
  assert.ok(!Model.wantsBetween(cfg("off"), 9))
  assert.ok(Model.wantsBetween(cfg("every"), 9))
  assert.ok(Model.wantsBetween(cfg("2"), 8) && !Model.wantsBetween(cfg("2"), 9))
  assert.ok(Model.wantsBetween(cfg("3"), 9) && !Model.wantsBetween(cfg("3"), 10))
  assert.ok(Model.wantsBetween(cfg("hours", [9, 17]), 17) && !Model.wantsBetween(cfg("hours", [9, 17]), 10))
  assert.deepEqual(cfg("hours", [17, 9, 9, 30, "x"]).kk.between.hours, [9, 17])
})

test("K.K. picks respect per-version ticks and avoid recent songs", () => {
  const keep = "NH - Drivin'"
  const off = Data.kkSongs.flatMap(s => (s === keep ? ["live/" + s] : ["live/" + s, "aircheck/" + s]))
  const c = Model.normalizeConfig({ kk: { off } })
  assert.deepEqual(Model.pickKK(c, Data.kkSongs, []), { song: keep, version: "aircheck" })
  const allowed = ["A", "B", "C"]
  let recent = []
  for (let i = 0; i < 9; i++) {
    const s = Model.pickKKSong(allowed, recent)
    assert.ok(!recent.slice(-2).includes(s))
    recent.push(s)
  }
  assert.equal(Model.pickKKSong(["only"], ["only"]), "only")
})

test("nothing ticked means K.K. plays from every song", () => {
  const off = Data.kkSongs.flatMap(s => ["live/" + s, "aircheck/" + s])
  assert.equal(Model.kkAllowed(Model.normalizeConfig({ kk: { off } }), Data.kkSongs).length, 95)
})

// ---- Quiet hours, weather, URLs ------------------------------------------

test("quiet hours wrap past midnight every day", () => {
  const q = Model.normalizeConfig({ quiet: { enabled: true, start: 23, end: 7, mode: "lower" } }).quiet
  assert.ok(Model.inQuiet(q, THU(23)) && Model.inQuiet(q, FRI(6, 59)))
  assert.ok(!Model.inQuiet(q, FRI(7)) && !Model.inQuiet(q, THU(22)))
  assert.ok(!Model.inQuiet(Object.assign({}, q, { enabled: false }), THU(23)))
  assert.equal(Model.quietText(q), "Quieter from 11 PM to 7 AM (next day)")
})

test("weather codes map to sunny, raining, or snowing", () => {
  assert.deepEqual([0, 3, 45, 51, 61, 67, 71, 77, 81, 86, 95].map(Model.weatherFromWmo),
    ["sunny", "sunny", "sunny", "raining", "raining", "raining", "snowing", "snowing", "raining", "snowing", "raining"])
})

test("track, cover, and cache paths", () => {
  assert.equal(Model.hourlyUrl("new-leaf", "raining", 0), "https://acmusicext.com/static/new-leaf/raining/12am.ogg")
  assert.equal(Model.hourlyUrl("new-leaf", "sunny", 13), "https://acmusicext.com/static/new-leaf/sunny/1pm.ogg")
  assert.equal(Model.kkUrl("live", "NH - Drivin'"), "https://acmusicext.com/static/kk/live/NH%20-%20Drivin'.ogg")
  assert.equal(Model.kkArtUrl("AC - K.K. Bossa"), "https://acmusicext.com/static/kk/art/AC%20-%20K.K.%20Bossa.png")
  assert.equal(Model.cacheRelPath(Model.kkUrl("live", "NH - Drivin'")), "kk/live/NH - Drivin'.ogg")
  assert.equal(Model.cacheRelPath("https://example.com/x.ogg"), "")
  assert.deepEqual([0, 11, 12, 23].map(Model.hourLabel), ["12 AM", "11 AM", "12 PM", "11 PM"])
})

test("mpv option quoting counts UTF-8 bytes", () => {
  assert.equal(Model.mpvQuote("abc"), "%3%abc")
  assert.equal(Model.mpvQuote("a · b"), "%6%a · b")
})

// ---- Volume levelling ----------------------------------------------------

test("levelling lifts quiet songs, tames loud ones, and never clips", () => {
  assert.equal(Model.levelGain(-26.4, -13.0), 8.4, "quiet aircheck gets lifted to the target")
  assert.equal(Model.levelGain(-28.7, -13.0), 10.7)
  assert.equal(Model.levelGain(-12.8, 0.3), -5.2, "loud song comes down")
  assert.equal(Model.levelGain(-22, -2), 1, "a boost stops at -1 dBTP peak")
  assert.equal(Model.levelGain(-20, 0.5), 0, "no headroom, no boost (but no cut either)")
  assert.equal(Model.levelGain(-40, -30), 12, "capped at +12 dB")
  assert.equal(Model.levelGain(null, null), 0, "unmeasured songs play as they are")
  assert.equal(Model.normalizeConfig({}).levelVolume, true)
})

test("cache index lines parse with and without measurements", () => {
  assert.deepEqual(Model.parseCacheLine("kk/live/NH - Drivin'.ogg\t-19.4\t-0.9"), { rel: "kk/live/NH - Drivin'.ogg", loudness: -19.4, peak: -0.9 })
  assert.deepEqual(Model.parseCacheLine("new-leaf/sunny/1am.ogg\t"), { rel: "new-leaf/sunny/1am.ogg", loudness: null, peak: null })
  assert.equal(Model.parseCacheLine(""), null)
})
