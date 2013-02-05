should = require 'should'
d16bunny = require '../src/d16bunny'

pp = require('../src/d16bunny/prettyprint').prettyPrinter

logger = (lineno, pos, message) ->

describe "Assembler.compileLine", ->
  compileLine = (text, address, symbols={}, debugging=false) ->
    a = new d16bunny.Assembler(logger)
    a.symtab = symbols
    parser = new d16bunny.Parser()
    a.addBuiltinMacros(parser)
    if symbols.debugging
      a.debugger = console.log
      parser.debugger = console.log
      console.log "-----"
    dline = a.compileLine(parser.parseLine(text), address)
    [ dline, a.symtab ]

  it "compiles a simple set", ->
    [ info, symtab ] = compileLine("set a, 0", 0x200)
    info.toString().should.eql("0x0200: 0x8401")

  it "compiles a simple set with a label", ->
    [ info, symtab ] = compileLine(":start set i, 1", 0x200)
    info.toString().should.eql("0x0200: 0x88c1")
    symtab["start"].should.eql(0x200)

  it "compiles a one-operand", ->
    [ info, symtab ] = compileLine("hwi 3", 0x200)
    info.toString().should.eql("0x0200: 0x9240")

  it "compiles a special (jsr)", ->
    [ info, symtab ] = compileLine("jsr cout", 0x200, cout: 0x999)
    info.toString().should.eql("0x0200: 0x7c20, 0x0999")

  describe "builtin macros", ->
    it "compiles jmp", ->
      [ info, symtab ] = compileLine("jmp cout", 0x200, cout: 0x999)
      info.flatten()
      info.toString().should.eql("0x0200: 0x7f81, 0x0999")

    it "compiles hlt", ->
      [ info, symtab ] = compileLine("hlt", 0x200)
      info.flatten()
      info.toString().should.eql("0x0200: 0x8b83")

    it "compiles ret", ->
      [ info, symtab ] = compileLine("ret", 0x200)
      info.flatten()
      info.toString().should.eql("0x0200: 0x6381")

    it "compiles bra", ->
      [ info, symtab ] = compileLine("bra exit", 0x200, exit: 0x204)
      info.resolve(symtab)
      info.flatten()
      info.toString().should.eql("0x0200: 0x7f82, 0x0002")

  it "optimizes sub x, 65530 to add x, 6", ->
    [ info, symtab ] = compileLine("sub x, 65530", 0x200)
    info.toString().should.eql("0x0200: 0x9c62")

#   it "refuses a non-immediate branch", ->
#     a = new d16bunny.Assembler(logger)
#     a.symtab.cout = 0x999
#     (-> a.compileLine("bra [cout]", 0x200)).should.throw(/BRA/)

#   it "compiles a forward reference", ->
#     a = new d16bunny.Assembler(logger)
#     info = a.compileLine("jmp cout", 0x200)
#     info.data[0].should.eql(0x7f81)
#     info.data[1].toString().should.eql("cout", org: 0x200)

#   it "compiles an org change", ->
#     a = new d16bunny.Assembler(logger)
#     info = a.compileLine(":stack org 0xf800", 0x200)
#     info.should.eql(data: [], org: 0xf800)
#     a.symtab.stack.should.eql(0xf800)

#   it "executes a macro", ->
#     a = new d16bunny.Assembler(logger)
#     a.macros["swap"] = [ 2 ]
#     a.macros["swap(2)"] =
#       name: "swap(2)"
#       params: [ "r1", "r2" ]
#       lines: [
#         "set push, r1"
#         "set r1, r2"
#         "set r2, pop"
#       ]
#     info = a.compileLine("swap y, z", 0x200)
#     info.data.should.eql([ 0x1301, 0x1481, 0x60a1 ], org: 0x200)

#   it "handles trailing comments", ->
#     a = new d16bunny.Assembler(logger)
#     info = a.compileLine("SUB A, [0x1000]            ; 7803 1000", 0x200)
#     info.data.should.eql([ 0x7803, 0x1000 ])

#   it "handles a single data object", ->
#     a = new d16bunny.Assembler(logger)
#     info = a.compileLine(":data DAT \"hello\"   ; hello", 0x200)
#     info.data.should.eql([ 0x0068, 0x0065, 0x006c, 0x006c, 0x006f ])

#   it "disallows a constant that's too large", ->
#     a = new d16bunny.Assembler(logger)
#     (-> a.compileLine("set a, 70000", 0x200)).should.throw(/70000/)

#   it "disallows an unknown opcode", ->
#     a = new d16bunny.Assembler(logger)
#     (-> a.compileLine("qxq 9", 0x200)).should.throw(/qxq/)

#   it "compiles a definition with EQU", ->
#     a = new d16bunny.Assembler(logger)
#     x = a.compileLine(":happy equ 23", 0)
#     a.symtab.should.eql(happy: 23, ".": 0, "$": 0)

#   it "turns HLT into SUB PC, 1", ->
#     a = new d16bunny.Assembler(logger)
#     info = a.compileLine("hlt", 0)
#     info.data.should.eql([ 0x8b83 ])

#   it "compiles a meaningless but valid line", ->
#     a = new d16bunny.Assembler(logger)
#     info = a.compileLine("set 1, a", 0)
#     info.data.should.eql([ 0x03e1, 0x0001 ])


# describe "Assembler.resolveLine", ->
#   it "resolves a short relative branch", ->
#     a = new d16bunny.Assembler(logger)
#     info = a.compileLine("bra next", 0x200)
#     info.branchFrom?.should.equal(0x201)
#     a.symtab.next = 0x208
#     a.resolveLine(info)
#     info.data.should.eql([ 0xa382 ])
