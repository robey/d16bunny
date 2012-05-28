should = require 'should'
util = require 'util'
d16bunny = require '../lib/d16bunny'

describe "Parser", ->
  logger = (pos, message, fatal) ->

  it "unquotes chars", ->
    p = new d16bunny.Assembler(logger)
    p.unquoteChar("x", 0, 1)[0].should.equal("x")
    p.unquoteChar("\\n", 0, 2)[0].should.equal("\n")
    p.unquoteChar("\\x41", 0, 4)[0].should.equal("A")

  it "parses simple binary expressions", ->
    p = new d16bunny.Assembler(logger)
    p.setText " 2 + 5 * x + smile"
    e = p.parseExpression(0)
    e.toString().should.equal("((2 + (5 * X)) + smile)")

  it "parses hex and binary constants", ->
    p = new d16bunny.Assembler(logger)
    p.setText "0x100 * -0b0010"
    e = p.parseExpression(0)
    e.toString().should.equal("(256 * (-2))")

  it "understands shifting and precedence", ->
    p = new d16bunny.Assembler(logger)
    p.setText "8 + 9 << 3 + 4"
    e = p.parseExpression(0)
    e.toString().should.equal("((8 + 9) << (3 + 4))")

  it "parses character literals", ->
    p = new d16bunny.Assembler(logger)
    p.setText "'p' - '\x40'"
    e = p.parseExpression(0)
    e.toString().should.equal("(112 - 64)")

  it "parses unix-style registers", ->
    p = new d16bunny.Assembler(logger)
    p.setText "(0x2300 + %j)"
    e = p.parseExpression(0)
    e.toString().should.equal("(8960 + J)")

  it "evaluates simple expressions", ->
    p = new d16bunny.Assembler(logger)
    p.setText "9"
    e = p.parseExpression(0)
    e.evaluate().should.equal(9)

  it "evaluates labels", ->
    p = new d16bunny.Assembler(logger)
    p.setText "2 + hello * 3"
    e = p.parseExpression(0)
    e.evaluate(hello: 10).should.equal(32)

  it "evaluates complex expressions", ->
    p = new d16bunny.Assembler(logger)
    p.setText "((offset & 0b1111) << 4) * -ghost"
    e = p.parseExpression(0)
    e.evaluate(ghost: 2, offset: 255).should.equal(-480)

  it "throws an exception for unknown labels", ->
    p = new d16bunny.Assembler(logger)
    p.setText "cats + dogs"
    e = p.parseExpression(0)
    (-> e.evaluate(cats: 5)).should.throw(/resolve/)

  it "parses string literals", ->
    a = new d16bunny.Assembler(logger)
    a.setText("\"hello sailor\\x21\"")
    x = a.parseString()
    x.should.equal("hello sailor!")

describe "Assembler.parseOperand", ->
  logger = (pos, message, fatal) ->

  it "parses registers", ->
    a = new d16bunny.Assembler(logger)
    a.setText("j")
    info = a.parseOperand(destination = false)
    info.code.should.equal(7)
    info.expr?.should.equal(false)

  it "parses register pointers", ->
    a = new d16bunny.Assembler(logger)
    a.setText("[j]")
    info = a.parseOperand(destination = false)
    info.code.should.equal(15)
    info.expr?.should.equal(false)

  it "parses special stack operations", ->
    a = new d16bunny.Assembler(logger)
    a.setText("peek")
    info = a.parseOperand(destination = false)
    info.code.should.equal(0x19)
    info.expr?.should.equal(false)

  it "parses immediates", ->
    a = new d16bunny.Assembler(logger)
    a.setText("0x800")
    info = a.parseOperand(destination = false)
    info.code.should.equal(0x1f)
    info.expr.evaluate().should.equal(0x800)

  it "parses immediate pointers", ->
    a = new d16bunny.Assembler(logger)
    a.setText("[0x800]")
    info = a.parseOperand(destination = false)
    info.code.should.equal(0x1e)
    info.expr.evaluate().should.equal(0x800)

  it "parses pointer operations", ->
    a = new d16bunny.Assembler(logger)
    a.setText("[0x20 + x]")
    info = a.parseOperand(destination = false)
    info.code.should.equal(0x13)
    info.expr.evaluate().should.equal(32)
    a.setText("[15+24+i]")
    info = a.parseOperand(destination = false)
    info.code.should.equal(0x16)
    info.expr.evaluate().should.equal(39)

  it "parses pick", ->
    a = new d16bunny.Assembler(logger)
    a.setText("pick leftover - 23")
    info = a.parseOperand(destination = false)
    info.code.should.equal(0x1a)
    info.expr.evaluate(leftover: 25).should.equal(2)

describe "Assemble.parseLine", ->
  logger = (pos, message, fatal) ->

  it "parses comment lines", ->
    x = new d16bunny.Assembler(logger).parseLine("; comment.")
    x.should.eql({})

  it "parses a single op", ->
    x = new d16bunny.Assembler(logger).parseLine("  nop")
    x.label?.should.equal(false)
    x.op.should.equal("nop")

  it "parses a labeled line", ->
    x = new d16bunny.Assembler(logger).parseLine(":start")
    x.label.should.equal("start")
    x.op?.should.equal(false)

  it "parses a line with operands", ->
    line = new d16bunny.Assembler(logger).parseLine(":last set [a], ','")
    line.label.should.equal("last")
    line.op.should.equal("set")
    line.operands.length.should.equal(2)
    line.operands[0].code.should.equal(0x08)
    line.operands[1].code.should.equal(0x1f)
    line.operands[1].expr.toString().should.equal("44")

  it "parses a definition with =", ->
    a = new d16bunny.Assembler(logger)
    x = a.parseLine("screen = 0x8000")
    x.label?.should.equal(false)
    x.op?.should.equal(false)
    a.symtab.should.eql(screen: 0x8000)

  it "parses a definition with #define", ->
    a = new d16bunny.Assembler(logger)
    x = a.parseLine("#define happy 23")
    a.symtab.should.eql(happy: 23)

  it "parses a macro definition", ->
    a = new d16bunny.Assembler(logger)
    x = a.parseLine("#macro swap(left, right) {")
    x.op?.should.equal(false)
    a.macros["swap(2)"].name.should.eql("swap(2)")
    a.macros["swap(2)"].params.should.eql([ "left", "right" ])
    x = a.parseLine("  set push, left")
    x.op?.should.equal(false)
    x = a.parseLine("  set left, right")
    x.op?.should.equal(false)
    x = a.parseLine("  set right, pop")
    x.op?.should.equal(false)
    x = a.parseLine("}")
    x.op?.should.equal(false)
    a.inMacro.should.equal(false)
    a.macros["swap(2)"].lines.should.eql([
      "  set push, left",
      "  set left, right",
      "  set right, pop"
    ])

  it "parses data", ->
    a = new d16bunny.Assembler(logger)
    line = a.parseLine("dat 3, 9, '@', \"cat\", p\"cat\"")
    line.op.should.equal("dat")
    line.data.length.should.equal(8)
    line.data.should.eql([ 3, 9, 0x40, 0x63, 0x61, 0x74, 0x6361, 0x7400 ])

describe "Parser.compileLine", ->
  logger = (pos, message, fatal) ->

  it "compiles a simple set", ->
    a = new d16bunny.Assembler(logger)
    info = a.compileLine("set a, 0", 0x200)
    info.should.eql(data: [ 0x8401 ])

  it "compiles a simple set with a label", ->
    a = new d16bunny.Assembler(logger)
    info = a.compileLine(":start set i, 1", 0x200)
    info.should.eql(data: [ 0x88c1 ])
    a.symtab.should.eql(start: 0x200)

  it "compiles a special (jsr)", ->
    a = new d16bunny.Assembler(logger)
    a.symtab.cout = 0x999
    info = a.compileLine("jsr cout", 0x200)
    info.should.eql(data: [ 0x7c20, 0x999 ])

  it "compiles a jmp", ->
    a = new d16bunny.Assembler(logger)
    a.symtab.cout = 0x999
    info = a.compileLine("jmp cout", 0x200)
    info.should.eql(data: [ 0x7f81, 0x999 ])

