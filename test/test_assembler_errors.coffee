util = require 'util'
should = require 'should'
d16bunny = require '../src/d16bunny'
pp = d16bunny.pp

describe "Assembler.compile with errors", ->
  build = (code, options={}) ->
    logger = (filename, y, x, reason) =>
      if options.log? then options.log.push([ filename, y, x, reason ])
    a = new d16bunny.Assembler(logger)
    if options.debugging?
      a.debugger = console.log
      console.log "----------"
    a.compile(code, 0, "test")

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
    out.errors[0][0..2].should.eql([ "test", 1, 4 ])
    out.errors[0][3].should.match(/hello/)
    dump(out).should.eql([
      "0x0000: 0x0401"
      "0x0001: 0x7c20, 0x0000"
      "0x0003: 0x106b"
    ])

  it "gives up after 10 errors", ->
    code = ("wut" for i in [1..15])
    out = build(code)
    out.errors.length.should.equal(11)
    for i in [0..9] then out.errors[i][3].should.match(/wut/)
    out.errors[10][3].should.match(/giving up/)

  it "can find an error after a few blank lines", ->
    code = [ "set a, []", "", "", "what" ]
    out = build(code)
    out.errors[0][0..2].should.eql([ "test", 0, 8 ])
    out.errors[0][3].should.match(/expression/)
    out.errors[1][0..2].should.eql([ "test", 3, 0 ])
    out.errors[1][3].should.match(/what/)

  it "can find an error that fell out of a macro expansion", ->
    # intentionally use a missing symbol, which won't get caught till the resolve stage.
    code = [ "jmp nothing", "", "", "what" ]
    out = build(code)
    out.errors[1][0..2].should.eql([ "(builtins)", 0, 4 ])
    out.errors[1][3].should.match(/nothing/)
    out.errors[0][0..2].should.eql([ "test", 3, 0 ])
    out.errors[0][3].should.match(/what/)

  it "correctly idenitfies an error location in BRA", ->
    code = [ "bra [x]" ]
    out = build(code)
    out.errors[0][0..2].should.eql([ "test", 0, 4 ])
    out.errors[0][3].should.match(/BRA/)

  it "only throws one error for a missing reference", ->
    code = [
      "jmp exit"
      "set a, [xy]"
      ":exit ret"
    ]
    log = []
    out = build(code, log: log)
    out.errors.length.should.equal(1)
    log.length.should.equal(1)
