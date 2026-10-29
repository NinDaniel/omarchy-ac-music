// Loads the plugin's QML JavaScript libraries (Data.js, Model.js) into plain
// Node so they can be tested without Quickshell. Their QML-only header lines
// (`.pragma library`, `.import "Data.js" as Data`) are stripped, and Model.js
// gets Data passed in the way the `.import` would provide it.

const fs = require("fs")
const path = require("path")

const root = path.join(__dirname, "..")

function load(file, imports = {}) {
  const source = fs.readFileSync(path.join(root, file), "utf8")
    .replace(/^\.pragma library$/m, "")
    .replace(/^\.import .*$/gm, "")
  const names = [...source.matchAll(/^(?:var|function) (\w+)/gm)].map(m => m[1])
  const exports = {}
  const args = Object.keys(imports)
  new Function("exports", ...args, `${source}\nObject.assign(exports, { ${names.join(", ")} })`)(
    exports, ...args.map(a => imports[a]))
  return exports
}

const Data = load("Data.js")
const Model = load("Model.js", { Data })

module.exports = { Data, Model, root }
