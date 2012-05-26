
util = require 'util'
glob = require("glob")
exec = require("child_process")
mocha = require 'mocha'

task "test", "run unit tests", ->
  mocha = exec.spawn "./node_modules/mocha/bin/mocha",
    [ "-R", "Progress", "--compilers", "coffee:coffee-script", "--colors" ]
  mocha.stderr.on("data", (data) -> util.print(data.toString()))
  mocha.stdout.on("data", (data) -> util.print(data.toString()))
