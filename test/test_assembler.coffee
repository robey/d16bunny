should = require 'should'
d16bunny = require '../src/d16bunny'

logger = (lineno, pos, message) ->

describe "Assemble.parseLine", ->

  it "parses data", ->
    a = new d16bunny.Assembler(logger)
    line = a.parseLine("dat 3, 9, '@', \"cat\", p\"cat\"")
    line.op.should.equal("dat")
    line.data.length.should.equal(8)
    line.data.should.eql([ 3, 9, 0x40, 0x63, 0x61, 0x74, 0x6361, 0x7400 ])

  it "parses rom strings", ->
    a = new d16bunny.Assembler(logger)
    line = a.parseLine("dat r\"cat\"")
    line.op.should.equal("dat")
    line.data.length.should.equal(2)
    line.data.should.eql([ 0x6361, 0xf400 ])

describe "Assembler.compileLine", ->
  it "compiles a simple set", ->
    a = new d16bunny.Assembler(logger)
    info = a.compileLine("set a, 0", 0x200)
    info.should.eql(data: [ 0x8401 ], org: 0x200)

  it "compiles a simple set with a label", ->
    a = new d16bunny.Assembler(logger)
    info = a.compileLine(":start set i, 1", 0x200)
    info.should.eql(data: [ 0x88c1 ], org: 0x200)
    a.symtab.start.should.eql(0x200)

  it "compiles a one-operand", ->
    a = new d16bunny.Assembler(logger)
    info = a.compileLine("hwi 3", 0x200)
    info.should.eql(data: [ 0x9240 ], org: 0x200)

  it "compiles a special (jsr)", ->
    a = new d16bunny.Assembler(logger)
    a.symtab.cout = 0x999
    info = a.compileLine("jsr cout", 0x200)
    info.should.eql(data: [ 0x7c20, 0x999 ], org: 0x200)

  it "compiles a jmp", ->
    a = new d16bunny.Assembler(logger)
    a.symtab.cout = 0x999
    info = a.compileLine("jmp cout", 0x200)
    info.should.eql(data: [ 0x7f81, 0x999 ], org: 0x200)

  it "refuses a non-immediate branch", ->
    a = new d16bunny.Assembler(logger)
    a.symtab.cout = 0x999
    (-> a.compileLine("bra [cout]", 0x200)).should.throw(/BRA/)

  it "compiles a forward reference", ->
    a = new d16bunny.Assembler(logger)
    info = a.compileLine("jmp cout", 0x200)
    info.data[0].should.eql(0x7f81)
    info.data[1].toString().should.eql("cout", org: 0x200)

  it "compiles an org change", ->
    a = new d16bunny.Assembler(logger)
    info = a.compileLine(":stack org 0xf800", 0x200)
    info.should.eql(data: [], org: 0xf800)
    a.symtab.stack.should.eql(0xf800)

  it "executes a macro", ->
    a = new d16bunny.Assembler(logger)
    a.macros["swap"] = [ 2 ]
    a.macros["swap(2)"] =
      name: "swap(2)"
      params: [ "r1", "r2" ]
      lines: [
        "set push, r1"
        "set r1, r2"
        "set r2, pop"
      ]
    info = a.compileLine("swap y, z", 0x200)
    info.data.should.eql([ 0x1301, 0x1481, 0x60a1 ], org: 0x200)

  it "handles trailing comments", ->
    a = new d16bunny.Assembler(logger)
    info = a.compileLine("SUB A, [0x1000]            ; 7803 1000", 0x200)
    info.data.should.eql([ 0x7803, 0x1000 ])

  it "handles a single data object", ->
    a = new d16bunny.Assembler(logger)
    info = a.compileLine(":data DAT \"hello\"   ; hello", 0x200)
    info.data.should.eql([ 0x0068, 0x0065, 0x006c, 0x006c, 0x006f ])

  it "disallows a constant that's too large", ->
    a = new d16bunny.Assembler(logger)
    (-> a.compileLine("set a, 70000", 0x200)).should.throw(/70000/)

  it "disallows an unknown opcode", ->
    a = new d16bunny.Assembler(logger)
    (-> a.compileLine("qxq 9", 0x200)).should.throw(/qxq/)

  it "compiles a definition with EQU", ->
    a = new d16bunny.Assembler(logger)
    x = a.compileLine(":happy equ 23", 0)
    a.symtab.should.eql(happy: 23, ".": 0, "$": 0)

  it "turns HLT into SUB PC, 1", ->
    a = new d16bunny.Assembler(logger)
    info = a.compileLine("hlt", 0)
    info.data.should.eql([ 0x8b83 ])

  it "compiles a meaningless but valid line", ->
    a = new d16bunny.Assembler(logger)
    info = a.compileLine("set 1, a", 0)
    info.data.should.eql([ 0x03e1, 0x0001 ])


describe "Assembler.resolveLine", ->
  it "resolves a short relative branch", ->
    a = new d16bunny.Assembler(logger)
    info = a.compileLine("bra next", 0x200)
    info.branchFrom?.should.equal(0x201)
    a.symtab.next = 0x208
    a.resolveLine(info)
    info.data.should.eql([ 0xa382 ])
