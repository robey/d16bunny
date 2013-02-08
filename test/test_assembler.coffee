should = require 'should'
d16bunny = require '../src/d16bunny'

pp = require('../src/d16bunny/prettyprint').prettyPrinter

logger = (lineno, pos, message) ->

describe "Assembler.compileLine", ->
  compileLine = (text, address, symbols={}) ->
    a = new d16bunny.Assembler(logger)
    a.symtab = symbols
    parser = new d16bunny.Parser()
    a.addBuiltinMacros(parser)
    if symbols.debugging
      a.debugger = console.log
      parser.debugger = console.log
      console.log "-----"
    dline = a.compileLine(parser.parseLine(text), address)
    if symbols.resolve
      a.resolveLine(dline)
    [ dline, a.symtab ]

  it "compiles a simple set", ->
    [ dline, symtab ] = compileLine("set a, 0", 0x200)    
    dline.toString().should.eql("0x0200: 0x7c01, 0x0000")

  it "compiles a simple set with a label", ->
    [ dline, symtab ] = compileLine(":start set i, 1", 0x200)
    dline.toString().should.eql("0x0200: 0x7cc1, 0x0001")
    symtab["start"].should.eql(0x200)

  it "compiles a one-operand", ->
    [ dline, symtab ] = compileLine("hwi 3", 0x200)
    dline.toString().should.eql("0x0200: 0x7e40, 0x0003")

  it "compiles a special (jsr)", ->
    [ dline, symtab ] = compileLine("jsr cout", 0x200, cout: 0x999)
    dline.toString().should.eql("0x0200: 0x7c20, 0x0999")

  describe "builtin macros", ->
    it "compiles jmp", ->
      [ dline, symtab ] = compileLine("jmp cout", 0x200, cout: 0x999)
      dline.flatten()
      dline.toString().should.eql("0x0200: 0x7f81, 0x0999")

    it "compiles hlt", ->
      [ dline, symtab ] = compileLine("hlt", 0x200)
      dline.flatten()
      dline.toString().should.eql("0x0200: 0x7f83, 0x0001")

    it "compiles ret", ->
      [ dline, symtab ] = compileLine("ret", 0x200)
      dline.flatten()
      dline.toString().should.eql("0x0200: 0x6381")

    it "compiles bra forward", ->
      [ dline, symtab ] = compileLine("bra exit", 0x200, exit: 0x204, resolve: true)
      dline.flatten()
      dline.toString().should.eql("0x0200: 0x7f82, 0x0002")

  it "refuses a non-immediate branch", ->
    (-> compileLine("bra [cout]", 0x200)).should.throw(/BRA/)

  it "compiles a forward reference", ->
    [ dline, symtab ] = compileLine("set pc, cout", 0x200)
    dline.toString().should.eql("0x0200: 0x7f81, cout")

  it "compiles an org change", ->
    [ dline, symtab ] = compileLine(":stack org 0xf800", 0x200)
    dline.toString().should.eql("0xf800: ")
    symtab["stack"].should.eql(0xf800)

  it "executes a macro", ->
    a = new d16bunny.Assembler(logger)
    parser = new d16bunny.Parser()
    parser.macros["swap"] = [ 2 ]
    m = new d16bunny.Macro("swap", "swap(2)", [ "r1", "r2" ])
    parser.macros["swap(2)"] = m
    for x in [
      "set push, r1"
      "set r1, r2"
      "set r2, pop"
    ] then m.textLines.push(x)
    dline = a.compileLine(parser.parseLine("swap y, z"), 0x200)
    dline.flatten()
    dline.toString().should.eql("0x0200: 0x1301, 0x1481, 0x60a1")

  it "handles a single data object", ->
    [ dline, symtab ] = compileLine(":data DAT \"hello\"   ; hello", 0x200)
    dline.toString().should.eql("0x0200: 0x0068, 0x0065, 0x006c, 0x006c, 0x006f")

  it "disallows a constant that's too large", ->
    (-> compileLine("set a, 70000", 0x200)).should.throw(/70000/)

  it "compiles a definition", ->
    a = new d16bunny.Assembler(logger)
    dlines = for pline in a.parse([ ":happy equ 23" ]) then a.compileLine(pline, 0)
    dlines[0].toString().should.eql("0x0000: ")
    a.constants["happy"].should.eql(23)

  it "compiles a meaningless but valid line", ->
    [ dline, symtab ] = compileLine("set 1, a", 0)
    dline.toString().should.eql("0x0000: 0x03e1, 0x0001")

