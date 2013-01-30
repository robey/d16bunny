should = require 'should'
d16bunny = require '../src/d16bunny'

logger = (lineno, pos, message) ->

describe "Parser", ->
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
