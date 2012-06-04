
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

assemblerFiles = [
  "assembler",
  "dcpu",
  "errors",
  "expression",
  "output",
  "prettyprint"
]

## -----

task "test", "run unit tests", ->
  sync ->
    run "./node_modules/mocha/bin/mocha -R Progress --compilers coffee:coffee-script --colors"

task "build", "build javascript", ->
  sync ->
    run "mkdir -p lib"
    run "coffee -o lib -c src"

task "clean", "erase build products", ->
  sync ->
    run "rm -rf lib"

task "web", "build assember into javascript for browsers", ->
  sync ->
    run "mkdir -p js"
    files = ("src/d16bunny/" + x + ".coffee" for x in assemblerFiles)
    run "coffee -o js -j d16asm-x -c " + files.join(" ")
    run 'echo "var exports = {};" > js/d16asm.js'
    # remove the "require" statements.
    run 'grep -v " = require" js/d16asm-x.js >> js/d16asm.js'
    run 'echo "var d16bunny = exports; delete exports;" >> js/d16asm.js'
    #run "rm -f js/d16asm-x.js"

