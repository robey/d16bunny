util = require 'util'
should = require 'should'
d16bunny = require '../src/d16bunny'
pp = d16bunny.pp

describe "Assembler.compile with errors", ->
  build = (code, options={}) ->
    a = new d16bunny.Assembler()
    if options.debugging?
      a.debugger = console.log
      console.log "----------"
    a.compile(code)

  dump = (out) ->
    if not (out instanceof Array) then out = out.lines
    out.map (dline) -> dline.toString()

  it "recovers", ->
    code = [
      "set a, b"
      "jsr hello"
      "bor x, y"
    ]
    out = build(code)
    out.errors.length.should.equal(1)
    out.errors[0][0..1].should.eql([ 1, 4 ])
    out.errors[0][2].should.match(/hello/)
    dump(out).should.eql([
      "0x0000: 0x0401"
      "0x0001: 0x7c20, 0x0000"
      "0x0003: 0x106b"
    ])

  it "gives up after 10 errors", ->
    code = ("wut" for i in [1..15])
    out = build(code)
    out.errors.length.should.equal(11)
    for i in [0..9] then out.errors[i][2].should.match(/wut/)
    out.errors[10][2].should.match(/giving up/)

  it "can find an error after a few blank lines", ->
    code = [ "jmp nothing", "", "", "what" ]
    out = build(code, debugging: true)
    out.errors[1][0..1].should.eql([ 0, 4 ])
    out.errors[1][2].should.match(/nothing/)
    out.errors[0][0..1].should.eql([ 3, 0 ])
    out.errors[0][2].should.match(/what/)
