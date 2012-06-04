
child_process = require 'child_process'
fibers = require 'fibers'
glob = require 'glob'
mocha = require 'mocha'
sync = require 'sync'
util = require 'util'

exec = (args...) ->
  command = args.shift()
  process = child_process.spawn command, args
  process.stderr.on "data", (data) -> util.print(data.toString())
  process.stdout.on "data", (data) -> util.print(data.toString())
  fiber = fibers.current
  process.on 'exit', (code) -> fiber.run(code)
  fibers.yield()

run = (command) ->
  console.log "\u001b[35m+ " + command + "\u001b[0m"
  exec("/bin/sh", "-c", command)

# run a task inside a sync-capable fiber
synctask = (name, description, f) ->
  task name, description, -> (sync -> f())

assemblerFiles = [
  "assembler",
  "dcpu",
  "errors",
  "expression",
  "output",
  "prettyprint"
]

## -----

synctask "test", "run unit tests", ->
  run "./node_modules/mocha/bin/mocha -R Progress --compilers coffee:coffee-script --colors"

synctask "build", "build javascript", ->
  run "mkdir -p lib"
  run "coffee -o lib -c src"

synctask "clean", "erase build products", ->
  run "rm -rf js lib"

synctask "distclean", "erase everything that wasn't in git", ->
  run "rm -rf node_modules"

synctask "web", "build assember into javascript for browsers", ->
  run "mkdir -p js"
  files = ("src/d16bunny/" + x + ".coffee" for x in assemblerFiles)
  run "coffee -o js -j d16asm-x -c " + files.join(" ")
  run 'echo "var exports = {};" > js/d16asm.js'
  # remove the "require" statements.
  run 'grep -v " = require" js/d16asm-x.js >> js/d16asm.js'
  run 'echo "var d16bunny = exports; delete exports;" >> js/d16asm.js'
  run "rm -f js/d16asm-x.js"

