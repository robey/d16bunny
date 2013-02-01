should = require 'should'
d16bunny = require '../src/d16bunny'

pp = require('../src/d16bunny/prettyprint').prettyPrinter

logger = (lineno, pos, message) ->

trimHtml = (html) ->
  # try to reign in the html for testing
  html = html.replace(/<span class="syntax-([\w\-]+)">/g, "{$1:")
  html = html.replace(/<\/span>/g, "}")
  html

describe "Parser", ->
  it "unquotes chars", ->
    line = new d16bunny.Line("x")
    line.parseChar().should.equal("x")
    line.pos.should.equal(1)
    line = new d16bunny.Line("\\n")
    line.parseChar().should.equal("\n")
    line.pos.should.equal(2)
    line = new d16bunny.Line("\\x41")
    line.parseChar().should.equal("A")
    line.pos.should.equal(4)

  it "parses string literals", ->
    line = new d16bunny.Line("\"hello sailor\\x21\"")
    line.parseString().should.eql("hello sailor!")
    trimHtml(line.toHtml()).should.eql("{string:&quot;hello sailor}{string-escape:\\x21}{string:&quot;}")

  describe "parseExpression", ->
    html = ""

    parseExpression = (s) ->
      p = new d16bunny.Parser(logger)
      line = new d16bunny.Line(s)
      e = p.parseExpression(line)
      html = trimHtml(line.toHtml())
      e

    it "parses simple binary expressions", ->
      e = parseExpression(" 2 + 5 * x + smile")
      e.toString().should.equal("((2 + (5 * X)) + smile)")
      html.should.eql(" {number:2} {operator:+} {number:5} {operator:*} {register:x} {operator:+} {identifier:smile}")

    it "parses hex and binary constants", ->
      e = parseExpression("0x100 * -0b0010")
      e.toString().should.equal("(256 * (-2))")
      html.should.eql("{number:0x100} {operator:*} {operator:-}{number:0b0010}")

    it "understands shifting and precedence", ->
      e = parseExpression("8 + 9 << 3 + 4")
      e.toString().should.equal("((8 + 9) << (3 + 4))")
      html.should.eql("{number:8} {operator:+} {number:9} {operator:&lt;&lt;} {number:3} {operator:+} {number:4}")

    it "parses character literals", ->
      e = parseExpression("'p' - '\\x40'")
      e.toString().should.equal("(112 - 64)")
      html.should.eql("{string:&#39;p&#39;} {operator:-} {string:&#39;}{string-escape:\\x40}{string:&#39;}")

    it "parses unix-style registers", ->
      e = parseExpression("(0x2300 + %j)")
      e.toString().should.equal("(8960 + J)")
      html.should.eql("{operator:(}{number:0x2300} {operator:+} {register:%j}{operator:)}")

    it "evaluates simple expressions", ->
      e = parseExpression("9")
      e.evaluate().should.equal(9)
      html.should.eql("{number:9}")

    it "evaluates labels", ->
      e = parseExpression("2 + hello * 3")
      e.evaluate(hello: 10).should.equal(32)
      html.should.eql("{number:2} {operator:+} {identifier:hello} {operator:*} {number:3}")

    it "evaluates complex expressions", ->
      e = parseExpression("((offset & 0b1111) << 4) * -ghost")
      e.evaluate(ghost: 2, offset: 255).should.equal(-480)
      html.should.eql("{operator:((}{identifier:offset} {operator:&amp;} {number:0b1111}{operator:)} " +
        "{operator:&lt;&lt;} {number:4}{operator:)} {operator:*} {operator:-}{identifier:ghost}")

    it "throws an exception for unknown labels", ->
      e = parseExpression("cats + dogs")
      (-> e.evaluate(cats: 5)).should.throw(/resolve/)
      html.should.eql("{identifier:cats} {operator:+} {identifier:dogs}")

  describe "parseOperand", ->
    parseOperand = (s, symtab={}) ->
      p = new d16bunny.Parser(logger)
      line = new d16bunny.Line(s)
      x = p.parseOperand(line)
      x.resolve(symtab)
      x.toString()

    it "parses registers", ->
      parseOperand("j").should.eql("<7>")
      parseOperand("J").should.eql("<7>")
      parseOperand("X").should.eql("<3>")
      parseOperand("ex").should.eql("<29>")

    it "parses register pointers", ->
      parseOperand("[j]").should.eql("<15>")
      parseOperand("[J]").should.eql("<15>")
      (-> parseOperand("[ex]")).should.throw(/can't dereference/)

    it "parses special stack operations", ->
      parseOperand("peek").should.eql("<25>")

    it "parses immediates", ->
      parseOperand("0x800").should.eql("<31, 2048>")

    it "parses immediate pointers", ->
      parseOperand("[0x800]").should.eql("<30, 2048>")

    it "parses pointer operations", ->
      parseOperand("[0x20 + x]").should.eql("<19, 32>")
      parseOperand("[15+24+i]").should.eql("<22, 39>")
      parseOperand("[a+9]").should.eql("<16, 9>")
      parseOperand("[a-2]").should.eql("<16, 65534>")

    it "parses pick", ->
      parseOperand("pick leftover - 23", { leftover: 25 }).should.eql("<26, 2>")
