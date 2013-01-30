should = require 'should'
d16bunny = require '../src/d16bunny'

logger = (lineno, pos, message) ->

describe "Assembler.compile", ->
  build = (code, debugging) ->
    a = new d16bunny.Assembler(logger)
    if debugging?
      a.debugger = console.log
      console.log "----------"
    rv = a.compile(code)
    rv.errorCount.should.equal(0)
    rv.pack()

  it "compiles a small program", ->
    code = [ "text = 0x8000", "; comment", "  set [text], 0xf052", "  bor x, y" ];
    a = new d16bunny.Assembler(logger)
    rv = a.compile(code)
    rv.errorCount.should.equal(0)
    lines = rv.lines
    a.symtab.text.should.equal(0x8000)
    lines.length.should.equal(4)
    lines[0].should.eql(org: 0, data: [])
    lines[1].should.eql(org: 0, data: [])
    lines[2].should.eql(org: 0, data: [ 0x7fc1, 0xf052, 0x8000 ])
    lines[3].should.eql(org: 3, data: [ 0x106b ])

  it "compiles a forward reference", ->
    code = [ "org 0x1000", "jmp hello", ":hello bor x, y" ];
    a = new d16bunny.Assembler(logger)
    rv = a.compile(code)
    rv.errorCount.should.equal(0)
    lines = rv.lines
    lines.length.should.equal(3)
    lines[0].should.eql(org: 0x1000, data: [])
    lines[1].should.eql(org: 0x1000, data: [ 0x7f81, 0x1002 ])
    lines[2].should.eql(org: 0x1002, data: [ 0x106b ])

  it "packs into blocks", ->
    code = [
      "org 0x100", "bor x, y", "bor x, z", "bor x, i", "org 0x400",
      "bor x, j", "org 0x300", "bor x, a"
    ]
    blocks = build(code)
    blocks.should.eql([
      { org: 0x100, data: [ 0x106b, 0x146b, 0x186b ] }
      { org: 0x300, data: [ 0x006b ] }
      { org: 0x400, data: [ 0x1c6b ] }
    ])

  it "can find line numbers from code", ->
    code = [
      "org 0x100", "bor x, y", "set [0x1000], [0x1001]",
      "org 0x200", "; comment", "dat 0, 0, 0, 0, 0", "; comment",
      "org 0x208", "bor x, y"
    ]
    a = new d16bunny.Assembler(logger)
    out = a.compile(code)
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
    code = [
      "org 0x100", "bor x, y", "set [0x1000], [0x1001]",
      "org 0x200", "; comment", "dat 0, 0, 0, 0, 0", "; comment",
      "org 0x208", "bor x, y"
    ]
    a = new d16bunny.Assembler(logger)
    out = a.compile(code)
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
    code = [
      "org 0x100", "bor x, y", "set [0x1000], [0x1001]",
      "org 0x200", "; comment", "dat 0, 0, 0, 0, 0", "; comment",
      "org 0x208", "bor x, y"
    ]
    a = new d16bunny.Assembler(logger)
    out = a.compile(code)
    out.lineToMem(0)?.should.equal(false)
    out.lineToMem(1).should.equal(0x100)
    out.lineToMem(2).should.equal(0x101)
    out.lineToMem(3)?.should.equal(false)
    out.lineToMem(4)?.should.equal(false)
    out.lineToMem(5).should.equal(0x200)
    out.lineToMem(6)?.should.equal(false)
    out.lineToMem(7)?.should.equal(false)
    out.lineToMem(8).should.equal(0x208)

  it "can resolve recursive labels", ->
    code = [
      "yellow = 14"
      "bgcolor = yellow"
      "set a, yellow"
    ]
    build(code).should.eql([
      { org: 0, data: [ 0xbc01 ] }
    ])

  it "can do negative offsets", ->
    code = [
      "set x, [j-1]"
      "set y, [j-2]"
    ]
    build(code).should.eql([
      { org: 0, data: [ 0x5c61, 0xffff, 0x5c81, 0xfffe ] }
    ])

  it "allows directives to start with .", ->
    code = [
      "  set a, -1"
      ".org 0x100"
      ".equ yellow 2"
      "  set a, yellow"
    ]
    build(code).should.eql([
      { org: 0, data: [ 0x8001 ] }
      { org: 0x100, data: [ 0x8c01 ] }
    ])

  it "allows $ as current location", ->
    code = [
      "#org 0x200"
      "  set a, $ + 3"
    ]
    build(code).should.eql([
      { org: 0x200, data: [ 0x7c01, 0x203 ] }
    ])

  it "tracks $ correctly through macros", ->
    code = [
      ".macro jsrr(addr) {"
      "  set push, pc"
      "  add peek, 3"
      "  add pc, addr - $"
      "}"
      ".org 0x1000"
      "jsrr(0x2000)"
    ]
    build(code).should.eql([
      { org: 0x1000, data: [ 0x7301, 0x9322, 0x7f82, 0xffe ] }
    ])

describe "Assembler.continueCompile", ->
  it "compiles a small program in two pieces", ->
    code1 = [ "text = 0x8000", "; comment", "set a, 0" ]
    code2 = [ "  set [text], 0xf052", "  bor x, y" ];
    a = new d16bunny.Assembler(logger)
    rv = a.compile(code1)
    rv.errorCount.should.equal(0)
    rv = a.continueCompile(code2)
    rv.errorCount.should.equal(0)
    lines = rv.lines
    a.symtab.text.should.equal(0x8000)
    lines.length.should.equal(5)
    lines[0].should.eql(org: 0, data: [])
    lines[1].should.eql(org: 0, data: [])
    lines[2].should.eql(org: 0, data: [ 0x8401 ])
    lines[3].should.eql(org: 1, data: [ 0x7fc1, 0xf052, 0x8000 ])
    lines[4].should.eql(org: 4, data: [ 0x106b ])
