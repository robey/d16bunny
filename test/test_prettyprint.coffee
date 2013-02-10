should = require 'should'
prettyPrinter = require('../src/d16bunny/prettyprint').prettyPrinter

describe "PrettyPrinter", ->
  it "copes with tabs", ->
    line = "\t\tSET A, 0x30\t\t\t\t;"
    prettyPrinter.dumpString(line).should.eql("\"\\u0009\\u0009SET A, 0x30\\u0009\\u0009\\u0009\\u0009;\"")

  it "can handle regex", ->
    regex = /^yes|no$/
    prettyPrinter.dump(regex).should.eql("\x1b[37m/^yes|no$/\x1b[0m")
