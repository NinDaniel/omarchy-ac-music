const test = require("node:test")
const assert = require("node:assert/strict")
const fs = require("fs")
const path = require("path")
const { Data, Model, root } = require("./load")

test("K.K. song list: 95 unique songs, each in a known group", () => {
  assert.equal(Data.kkSongs.length, 95)
  assert.equal(new Set(Data.kkSongs).size, 95)
  const prefixes = Model.KK_GROUPS.map(g => g.prefix)
  for (const song of Data.kkSongs) {
    assert.ok(prefixes.includes(Model.kkGroup(song)), song)
    assert.ok(Model.kkTitle(song).length > 0, song)
  }
})

test("K.K. song names with apostrophes are included", () => {
  for (const song of ["AC - K.K. Cruisin'", "AC - Rockin' K.K.", "AC - Surfin' K.K.", "NH - Drivin'"])
    assert.ok(Data.kkSongs.includes(song), song)
  const groups = {}
  for (const song of Data.kkSongs) groups[Model.kkGroup(song)] = (groups[Model.kkGroup(song)] || 0) + 1
  assert.deepEqual(groups, { AC: 55, CF: 20, NL: 16, NH: 4 })
})

test("loop points: every game, valid hours, start before end", () => {
  for (const game of Model.GAME_IDS) {
    const weathers = Data.loopTimes[game]
    assert.ok(weathers, game)
    for (const [weather, hours] of Object.entries(weathers)) {
      assert.ok(Model.WEATHERS.includes(weather), `${game}/${weather}`)
      for (const [hour, [start, end]] of Object.entries(hours)) {
        assert.ok(Number(hour) >= 0 && Number(hour) <= 23, `${game}/${weather}/${hour}`)
        assert.ok(start >= 0 && end > start, `${game}/${weather}/${hour}`)
      }
    }
  }
  assert.equal(Data.loopTimes["animal-crossing"].raining, undefined, "GameCube has no rain music")
})

test("manifest: valid, versioned, entry points exist", () => {
  const manifest = JSON.parse(fs.readFileSync(path.join(root, "manifest.json"), "utf8"))
  assert.equal(manifest.schemaVersion, 1)
  assert.equal(manifest.id, "io.github.nindaniel.ac-music")
  assert.match(manifest.version, /^\d+\.\d+\.\d+$/)
  for (const entry of Object.values(manifest.entryPoints)) assert.ok(fs.existsSync(path.join(root, entry)), entry)
})

test("no symlinks in the plugin folder (Omarchy refuses them)", () => {
  const walk = dir => fs.readdirSync(dir, { withFileTypes: true }).flatMap(e => {
    if (e.name === ".git" || e.name === "node_modules") return []
    const p = path.join(dir, e.name)
    assert.ok(!e.isSymbolicLink(), `symlink: ${p}`)
    return e.isDirectory() ? walk(p) : []
  })
  walk(root)
})
