util = require 'util'
should = require 'should'
d16bunny = require '../src/d16bunny'

logger = (lineno, pos, message) ->

describe "Assembler.compile with errors", ->
  logs = []

  build = (code) ->
    logs = []
    logger = (lineno, pos, message) -> logs.push([ lineno, pos, message ])
    a = new d16bunny.Assembler(logger)
    a.compile(code, 0, 10)

  it "recovers", ->
    code = [ "set a, b", "jsr hello", "bor x, y" ]
    rv = build(code)
    rv.errorCount.should.equal(1)
    logs[0][0..1].should.eql([ 1, 4 ])
    logs[0][2].should.match(/hello/)
    lines = rv.lines
    lines.length.should.equal(3)
    lines[0].should.eql(org: 0, data: [ 0x0401 ])
    lines[1].should.eql(org: 1, data: [ 0x7c20, 0 ])
    lines[2].should.eql(org: 3, data: [ 0x106b ])

  it "gives up after 10 errors", ->
    code = ("wut" for i in [1..15])
    rv = build(code)
    rv.errorCount.should.equal(10)
    logs.length.should.equal(11)
    for i in [0..9] then logs[i][2].should.match(/wut/)
    logs[10][2].should.match(/giving up/)

  it "can find an error after a few blank lines", ->
    code = [ "jmp nothing", "", "", "what" ]
    rv = build(code)
    logs[1][0..1].should.eql([ 0, 4 ])
    logs[1][2].should.match(/nothing/)
    logs[0][0..1].should.eql([ 3, 0 ])
    a = new d16bunny.Assembler(logger)
    out = a.compile(code)
