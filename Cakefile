
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

run = (command) -> exec("/bin/sh", "-c", command)

task "test", "run unit tests", ->
  run "./node_modules/mocha/bin/mocha",
    "-R", "Progress", "--compilers", "coffee:coffee-script", "--colors"

task "build", "build javascript", ->
  sync ->
    run "mkdir -p jsbuild"
    exec "coffee", "-o", "jsbuild", "-c", "lib"
