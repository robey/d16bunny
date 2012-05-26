should = require 'should'
parser = require '../lib/d16bunny/parser'

describe "Parser", ->
  logger = (pos, message, fatal) ->

  it "unquotes chars", ->
    p = new parser.Parser(logger)
    p.unquoteChar("x", 0, 1)[0].should.equal("x")
    p.unquoteChar("\\n", 0, 2)[0].should.equal("\n")
    p.unquoteChar("\\x41", 0, 4)[0].should.equal("A")

  it "parses simple binary expressions", ->
    p = new parser.Parser(logger)
    p.setText " 2 + 5 * x + smile"
    e = p.parseExpression(0)
    e.toString().should.equal("((2 + (5 * X)) + smile)")

  it "parses hex and binary constants", ->
    p = new parser.Parser(logger)
    p.setText "0x100 * -0b0010"
    e = p.parseExpression(0)
    e.toString().should.equal("(256 * (-2))")

  it "understands shifting and precedence", ->
    p = new parser.Parser(logger)
    p.setText "8 + 9 << 3 + 4"
    e = p.parseExpression(0)
    e.toString().should.equal("((8 + 9) << (3 + 4))")

  it "parses character literals", ->
    p = new parser.Parser(logger)
    p.setText "'p' - '\x40'"
    e = p.parseExpression(0)
    e.toString().should.equal("(112 - 64)")

  it "parses unix-style registers", ->
    p = new parser.Parser(logger)
    p.setText "(0x2300 + %j)"
    e = p.parseExpression(0)
    e.toString().should.equal("(8960 + J)")
