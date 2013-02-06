should = require 'should'
d16bunny = require '../src/d16bunny'

logger = (lineno, pos, message) ->

describe "Assembler.compile", ->
  build = (code, options={}) ->
    a = new d16bunny.Assembler(logger)
    if options.debugging?
      a.debugger = console.log
      console.log "----------"
    out = a.compile(code)
    out.errors.length.should.equal(0)
    out

  dump = (out) ->
    if not (out instanceof Array) then out = out.lines
    out.map (dline) -> dline.toString()

  it "compiles a small program", ->
    code = [
      "text = 0x8000"
      "; comment"
      "  set [text], 0xf052"
      "  bor x, y"
    ]
    out = build(code)
    lines = out.lines
    out.symtab.text.should.equal(0x8000)
    dump(out).should.eql([
      "0x0000: "
      "0x0000: "
      "0x0000: 0x7fc1, 0xf052, 0x8000"
      "0x0003: 0x106b"
    ])

  it "compiles a forward reference", ->
    code = [
      "org 0x1000"
      "jmp hello"
      ":hello bor x, y"
    ]
    out = build(code)
    dump(out).should.eql([
      "0x1000: "
      "0x1000: 0x7f81, 0x1002"
      "0x1002: 0x106b"
    ])

  it "packs into blocks", ->
    code = [
      "org 0x100"
      "bor x, y"
      "bor x, z"
      "bor x, i"
      "org 0x400",
      "bor x, j"
      "org 0x300"
      "bor x, a"
    ]
    blocks = build(code).pack()
    dump(blocks).should.eql([
      "0x0100: 0x106b, 0x146b, 0x186b"
      "0x0300: 0x006b"
      "0x0400: 0x1c6b"
    ])

  Code1 = [
    "org 0x100"
    "bor x, y"
    "set [0x1000], [0x1001]",
    "org 0x200"
    "; comment"
    "dat 0, 0, 0, 0, 0"
    "; comment",
    "org 0x208"
    "bor x, y"
  ]

  it "can find line numbers from code", ->
    out = build(Code1)
    out.memToLine(0x100).should.equal(1)
    out.memToLine(0x101).should.equal(2)
    out.memToLine(0x103).should.equal(2)
    out.memToLine(0x104)?.should.equal(false)
    out.memToLine(0x200).should.equal(5)
    out.memToLine(0x202).should.equal(5)
    out.memToLine(0x204).should.equal(5)
    out.memToLine(0x205)?.should.equal(false)
    out.memToLine(0x208).should.equal(8)

  it "can find closest line numbers from code", ->
    out = build(Code1)
    out.memToClosestLine(0xff).should.equal(1)
    out.memToClosestLine(0x100).should.equal(1)
    out.memToClosestLine(0x101).should.equal(2)
    out.memToClosestLine(0x102).should.equal(2)
    out.memToClosestLine(0x103).should.equal(2)
    out.memToClosestLine(0x104).should.equal(2)
    out.memToClosestLine(0x105).should.equal(2)
    out.memToClosestLine(0x103).should.equal(2)
    out.memToClosestLine(0x180).should.equal(2)
    out.memToClosestLine(0x182).should.equal(5)
    out.memToClosestLine(0x1ff).should.equal(5)
    out.memToClosestLine(0x200).should.equal(5)
    out.memToClosestLine(0x202).should.equal(5)
    out.memToClosestLine(0x204).should.equal(5)
    out.memToClosestLine(0x205).should.equal(5)
    out.memToClosestLine(0x206).should.equal(8)
    out.memToClosestLine(0x207).should.equal(8)
    out.memToClosestLine(0x208).should.equal(8)
    out.memToClosestLine(0x209).should.equal(8)

  it "can find code from line numbers", ->
    out = build(Code1)
    out.lineToMem(0)?.should.equal(false)
    out.lineToMem(1).should.equal(0x100)
    out.lineToMem(2).should.equal(0x101)
    out.lineToMem(3)?.should.equal(false)
    out.lineToMem(4)?.should.equal(false)
    out.lineToMem(5).should.equal(0x200)
    out.lineToMem(6)?.should.equal(false)
    out.lineToMem(7)?.should.equal(false)
    out.lineToMem(8).should.equal(0x208)

#   it "can resolve recursive labels", ->
#     code = [
#       "yellow = 14"
#       "bgcolor = yellow"
#       "set a, yellow"
#     ]
#     build(code).should.eql([
#       { org: 0, data: [ 0xbc01 ] }
#     ])

#   it "can do negative offsets", ->
#     code = [
#       "set x, [j-1]"
#       "set y, [j-2]"
#     ]
#     build(code).should.eql([
#       { org: 0, data: [ 0x5c61, 0xffff, 0x5c81, 0xfffe ] }
#     ])

#   it "allows directives to start with .", ->
#     code = [
#       "  set a, -1"
#       ".org 0x100"
#       ".equ yellow 2"
#       "  set a, yellow"
#     ]
#     build(code).should.eql([
#       { org: 0, data: [ 0x8001 ] }
#       { org: 0x100, data: [ 0x8c01 ] }
#     ])

#   it "allows $ as current location", ->
#     code = [
#       "#org 0x200"
#       "  set a, $ + 3"
#     ]
#     build(code).should.eql([
#       { org: 0x200, data: [ 0x7c01, 0x203 ] }
#     ])

#   it "tracks $ correctly through macros", ->
#     code = [
#       ".macro jsrr(addr) {"
#       "  set push, pc"
#       "  add peek, 3"
#       "  add pc, addr - $"
#       "}"
#       ".org 0x1000"
#       "jsrr(0x2000)"
#     ]
#     build(code).should.eql([
#       { org: 0x1000, data: [ 0x7301, 0x9322, 0x7f82, 0xffe ] }
#     ])

#   it "handles local labels", ->
#     code = [
#       ".org 0x1000"
#       ":start"
#       "  set a, 0"
#       ":.1"
#       "  ife x, 1"
#       "    bra .1"
#       ":end"
#       "  jmp .1"
#       "  set y, 0"
#       ":.1"
#       "  ret"
#     ]
#     build(code).should.eql([
#       { org: 0x1000, data: [ 0x8401, 0x8872, 0x8f83, 0x7f81, 0x1006, 0x8481, 0x6381 ] }
#     ])

# describe "Assembler.continueCompile", ->
#   it "compiles a small program in two pieces", ->
#     code1 = [ "text = 0x8000", "; comment", "set a, 0" ]
#     code2 = [ "  set [text], 0xf052", "  bor x, y" ];
#     a = new d16bunny.Assembler(logger)
#     rv = a.compile(code1)
#     rv.errorCount.should.equal(0)
#     rv = a.continueCompile(code2)
#     rv.errorCount.should.equal(0)
#     lines = rv.lines
#     a.symtab.text.should.equal(0x8000)
#     lines.length.should.equal(5)
#     lines[0].should.eql(org: 0, data: [])
#     lines[1].should.eql(org: 0, data: [])
#     lines[2].should.eql(org: 0, data: [ 0x8401 ])
#     lines[3].should.eql(org: 1, data: [ 0x7fc1, 0xf052, 0x8000 ])
#     lines[4].should.eql(org: 4, data: [ 0x106b ])
