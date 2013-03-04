should = require 'should'
d16bunny = require '../src/d16bunny'
pp = d16bunny.pp

describe "AssemblerOutput", ->
  build = (code, options={}) ->
    a = new d16bunny.Assembler()
    if options.debugging?
      a.debugger = console.log
      console.log "----------"
    if options.includer? then a.includer = options.includer
    out = a.compile(code)
    out.errors.length.should.equal(0)
    out

  dump = (out) ->
    if not (out instanceof Array) then out = out.lines
    out.map (dline) -> dline.toString()

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

  it "can generate simplified disassembly", ->
    code = [
      "jmp start ; huh?"
      ".org 0x200"
      ":start ret"
    ]
    build(code).disassemble().should.eql([
      ""
      "ORG 0x0000"
      ""
      "SET PC, start ; huh?"
      ""
      "ORG 0x0200"
      ""
      ":start"
      " SET PC, POP"
    ])

  it "can disassemble expanded macros", ->
    code = [
      ".macro wut(r)"
      "  set x, r"
      "  dat r"
      ".endmacro"
      "wut 3"
      "wut 4"
    ]
    build(code).disassemble().should.eql([
      ""
      "ORG 0x0000"
      ""
      "SET X, 3"
      "DAT 0x0003"
      "SET X, 4"
      "DAT 0x0004"
    ])

