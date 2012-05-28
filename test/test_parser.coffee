should = require 'should'
d16bunny = require '../lib/d16bunny'

describe "Assembler", ->
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

  it "parses comment lines", ->
    x = new d16bunny.Assembler(logger).parseLine("; comment.")
    x.label?.should.equal(false)
    x.op?.should.equal(false)
    x.args.length.should.equal(0)

  it "parses a single op", ->
    x = new d16bunny.Assembler(logger).parseLine("  nop")
    x.label?.should.equal(false)
    x.op.should.equal("nop")
    x.args.length.should.equal(0)

  it "parses a labeled line", ->
    x = new d16bunny.Assembler(logger).parseLine(":start")
    x.label.should.equal("start")
    x.op?.should.equal(false)
    x.args.length.should.equal(0)

  it "parses a line with operands", ->
    x = new d16bunny.Assembler(logger).parseLine(":last set [a], ','")
    x.label.should.equal("last")
    x.op.should.equal("set")
    x.args.should.eql([ "[a]", "','" ])
    x.argpos.should.eql([ 10, 15 ])

  it "parses a constant definition", ->
    x = new d16bunny.Assembler(logger).parseLine("screen = 0x8000")
    x.label?.should.equal(false)
    x.op.should.equal("screen")
    x.args.should.eql([ "=", "0x8000" ])
    x.argpos.should.eql([ 7, 9 ])

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

  it "parses a definition", ->
    a = new d16bunny.Assembler(logger)
    x = a.parseLine("#define happy 23")
    a.symtab.should.eql(happy: 23)


