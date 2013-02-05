should = require 'should'
d16bunny = require '../src/d16bunny'

pp = require('../src/d16bunny/prettyprint').prettyPrinter

trimHtml = (html) ->
  # try to reign in the html for testing
  html = html.replace(/<span class="syntax-([\w\-]+)">/g, "{$1:")
  html = html.replace(/<\/span>/g, "}")
  html

parseLine = (s) ->
  parser = new d16bunny.Parser()
  pline = parser.parseLine(s)
  html = trimHtml(pline.toHtml())
  for op in pline.operands then if op instanceof d16bunny.Operand then op.resolve()
  [ pline, html, parser.constants ]

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
      p = new d16bunny.Parser()
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
      e.dependency().should.equal("cats")
      e.dependency(cats: 5).should.equal("dogs")
      e.dependency(cats: 5, dogs: 10)?.should.equal(false)
      html.should.eql("{identifier:cats} {operator:+} {identifier:dogs}")

    it "evaluates <, <=, >, >=", ->
      e = parseExpression("errors > 9")
      e.evaluate(errors: 10).should.equal(1)
      e.evaluate(errors: 3).should.equal(0)
      e = parseExpression("errors < 9")
      e.evaluate(errors: 10).should.equal(0)
      e.evaluate(errors: 3).should.equal(1)
      e = parseExpression("errors >= 9")
      e.evaluate(errors: 10).should.equal(1)
      e.evaluate(errors: 9).should.equal(1)
      e.evaluate(errors: 3).should.equal(0)
      e = parseExpression("errors <= 9")
      e.evaluate(errors: 10).should.equal(0)
      e.evaluate(errors: 9).should.equal(1)
      e.evaluate(errors: 3).should.equal(1)

    it "evaluates ==, !=", ->
      e = parseExpression("errors | 1 == 9")
      e.evaluate(errors: 8).should.equal(1)
      e.evaluate(errors: 6).should.equal(0)
      e = parseExpression("errors | 1 != 9")
      e.evaluate(errors: 8).should.equal(0)
      e.evaluate(errors: 6).should.equal(1)

  describe "parseOperand", ->
    html = ""

    parseOperand = (s, symtab={}, destination=false) ->
      p = new d16bunny.Parser()
      line = new d16bunny.Line(s)
      x = p.parseOperand(line, destination)
      x.resolve(symtab)
      html = trimHtml(line.toHtml())
      x.toString()

    it "parses registers", ->
      parseOperand("j").should.eql("<7>")
      html.should.eql("{register:j}")
      parseOperand("J").should.eql("<7>")
      html.should.eql("{register:J}")
      parseOperand("X").should.eql("<3>")
      html.should.eql("{register:X}")
      parseOperand("ex").should.eql("<29>")
      html.should.eql("{register:ex}")

    it "parses register pointers", ->
      parseOperand("[j]").should.eql("<15>")
      html.should.eql("{operator:[}{register:j}{operator:]}")
      parseOperand("[J]").should.eql("<15>")
      html.should.eql("{operator:[}{register:J}{operator:]}")
      (-> parseOperand("[ex]")).should.throw(/can't dereference/)

    it "parses special stack operations", ->
      parseOperand("peek").should.eql("<25>")
      html.should.eql("{register:peek}")

    it "parses immediates", ->
      parseOperand("0x800").should.eql("<31, 2048>")
      html.should.eql("{number:0x800}")

    it "parses immediate chars", ->
      parseOperand("'A'").should.eql("<31, 65>")
      html.should.eql("{string:&#39;A&#39;}")

    it "parses immediate pointers", ->
      parseOperand("[0x800]").should.eql("<30, 2048>")
      html.should.eql("{operator:[}{number:0x800}{operator:]}")

    it "parses pointer operations", ->
      parseOperand("[0x20 + x]").should.eql("<19, 32>")
      html.should.eql("{operator:[}{number:0x20} {operator:+} {register:x}{operator:]}")
      parseOperand("[15+24+i]").should.eql("<22, 39>")
      html.should.eql("{operator:[}{number:15}{operator:+}{number:24}{operator:+}{register:i}{operator:]}")
      parseOperand("[a+9]").should.eql("<16, 9>")
      html.should.eql("{operator:[}{register:a}{operator:+}{number:9}{operator:]}")
      parseOperand("[a-2]").should.eql("<16, 65534>")
      html.should.eql("{operator:[}{register:a}{operator:-}{number:2}{operator:]}")

    it "parses pick", ->
      parseOperand("pick leftover - 23", { leftover: 25 }).should.eql("<26, 2>")
      html.should.eql("{register:pick} {identifier:leftover} {operator:-} {number:23}")

    it "parses push/pop", ->
      parseOperand("push", {}, true).should.eql("<24>")
      html.should.eql("{register:push}")
      parseOperand("pop", {}, false).should.eql("<24>")
      html.should.eql("{register:pop}")
      (-> parseOperand("push", {}, false)).should.throw(/can't use PUSH/)
      (-> parseOperand("pop", {}, true)).should.throw(/can't use POP/)

  describe "parseLine", ->
    it "parses comment lines", ->
      [ pline, html ] = parseLine("; comment.")
      pline.toString().should.eql("")
      html.should.eql("{comment:; comment.}")

    it "parses a single op", ->
      [ pline, html ] = parseLine("  nop")
      pline.toString().should.eql("NOP")
      html.should.eql("  {instruction:nop}")

    it "parses a labeled line", ->
      [ pline, html ] = parseLine(":start")
      pline.toString().should.eql(":start ")
      html.should.eql("{label::start}")
      [ pline, html ] = parseLine(":start  nop")
      pline.toString().should.eql(":start NOP")
      html.should.eql("{label::start}  {instruction:nop}")

    it "parses a line with operands", ->
      [ pline, html ] = parseLine(":last set [a], ','")
      pline.toString().should.eql(":last SET <8>, <31, 44>")
      html.should.eql("{label::last} {instruction:set} {operator:[}{register:a}{operator:],} {string:&#39;,&#39;}")

    it "parses a definition with =", ->
      [ pline, html, constants ] = parseLine("screen = 0x8000")
      constants["screen"].evaluate().should.eql(0x8000)
      pline.toString().should.eql("")
      html.should.eql("{identifier:screen} {operator:=} {number:0x8000}")

    it "parses a definition with #define", ->
      [ pline, html, constants ] = parseLine("#define happy 23")
      constants["happy"].evaluate().should.eql(23)
      pline.toString().should.eql("")
      html.should.eql("{directive:#define} {identifier:happy} {number:23}")

    it "parses a definition with .equ", ->
      [ pline, html, constants ] = parseLine(".equ happy 23")
      constants["happy"].evaluate().should.eql(23)
      pline.toString().should.eql("")
      html.should.eql("{directive:.equ} {identifier:happy} {number:23}")

    it "parses a definition with equ", ->
      [ pline, html, constants ] = parseLine(":happy equ 23")
      constants["happy"].evaluate().should.eql(23)
      pline.toString().should.eql("")
      html.should.eql("{label::happy} {directive:equ} {number:23}")

    it "parses data", ->
      [ pline, html ] = parseLine("dat 3, 9, '@', \"cat\", p\"cat\"")
      pline.toString().should.eql("DAT")
      pline.data.map((x) => x.evaluate()).should.eql([ 3, 9, 0x40, 0x63, 0x61, 0x74, 0x6361, 0x7400 ])
      html.should.eql("{instruction:dat} {number:3}{operator:,} {number:9}{operator:,} " +
        "{string:&#39;@&#39;}{operator:,} {string:&quot;cat&quot;}{operator:,} {string:p&quot;cat&quot;}")

    it "parses rom strings", ->
      [ pline, html ] = parseLine("dat r\"cat\"")
      pline.toString().should.eql("DAT")
      pline.data.map((x) => x.evaluate()).should.eql([ 0x6361, 0xf400 ])
      html.should.eql("{instruction:dat} {string:r&quot;cat&quot;}")

    it "parses org changes", ->
      [ pline, html ] = parseLine(".org 0x1000")
      pline.toString().should.eql(".org")
      pline.data.should.eql([ 4096 ])
      html.should.eql("{directive:.org} {number:0x1000}")
      [ pline, html ] = parseLine("  org 3")
      pline.toString().should.eql(".org")
      pline.data.should.eql([ 3 ])
      html.should.eql("  {directive:org} {number:3}")

  describe "parseLine macros", ->
    it "parses a macro definition", ->
      parser = new d16bunny.Parser()
      pline = parser.parseLine("#macro swap(left, right) {")
      pline.toString().should.eql(".macro swap")
      html = trimHtml(pline.toHtml())
      html.should.eql("{directive:#macro} {identifier:swap}{directive:(}{identifier:left}{directive:,} " +
        "{identifier:right}{directive:)} {directive:{}")
      # check that it's there
      parser.macros["swap(2)"].name.should.eql("swap(2)")
      parser.macros["swap(2)"].parameters.should.eql([ "left", "right" ])
      # add lines
      line1 = parser.parseLine("  set push, left")
      line1.toString().should.eql("")
      line2 = parser.parseLine("  set left, right")
      line2.toString().should.eql("")
      line3 = parser.parseLine("  set right, pop")
      line3.toString().should.eql("")
      line4 = parser.parseLine("}")
      line4.toString().should.eql("")
      parser.macros["swap(2)"].textLines.should.eql([
        "  set push, left",
        "  set left, right",
        "  set right, pop"
      ])

    it "parses a macro call", ->
      parser = new d16bunny.Parser()
      for x in [
        "#macro swap(left, right) {"
        "  set push, left"
        "  set left, right"
        "  set right, pop"
        "}"
      ] then parser.parseLine(x)
      line = parser.parseLine("  swap(x, y)")
      line.toString().should.eql("{ SET <24>, <3>; SET <3>, <4>; SET <4>, <24> }")
      html = trimHtml(line.toHtml())
      html.should.eql("  {identifier:swap}{operator:(}{string:x}{operator:,} {string:y}{operator:)}")

    it "parses a nested macro call", ->
      parser = new d16bunny.Parser()
      for x in [
        "#macro save(r) {"
        "  set push, r"
        "}"
      ] then parser.parseLine(x)
      for x in [
        "#macro restore(r) {"
        "  set r, pop"
        "}"
      ] then parser.parseLine(x)
      for x in [
        "#macro swap(left, right) {"
        "  save(left)"
        "  set left, right"
        "  restore(right)"
        "}"
      ] then parser.parseLine(x)
      line = parser.parseLine("  swap(x, y)")
      line.toString().should.eql("{ SET <24>, <3>; SET <3>, <4>; SET <4>, <24> }")
      html = trimHtml(line.toHtml())
      html.should.eql("  {identifier:swap}{operator:(}{string:x}{operator:,} {string:y}{operator:)}")

    it "parses a macro form of BRA", ->
      parser = new d16bunny.Parser()
      for x in [
        "#macro bra(addr) {"
        "  add pc, addr - next"
        ":next"
        "}"
      ] then parser.parseLine(x)
      line = parser.parseLine("  bra 0x1000")
      label = line.expanded[1].label
      (label.match(/bra\.(.*?)\.next/)?).should.equal(true)
      line.toString().should.eql("{ ADD <28>, <31, (4096 - #{label})>; :#{label}  }")

  describe "parseLine if", ->
    it "parses a simple if block", ->
      parser = new d16bunny.Parser()
      pline = parser.parseLine(".define version 10")
      pline.toString().should.eql("")
      pline = parser.parseLine(".if version > 8")
      pline.toString().should.eql(".if")
      pline = parser.parseLine("  set a, 30")
      pline.toString().should.eql("SET <0>, <31, 30>")
      pline = parser.parseLine(".else")
      pline.toString().should.eql(".else")
      pline = parser.parseLine("  set b, 30")
      pline.toString().should.eql("")
      pline = parser.parseLine(".endif")
      pline.toString().should.eql(".endif")

    it "parses a nested if", ->
      parser = new d16bunny.Parser()
      pline = parser.parseLine(".define version 10")
      pline.toString().should.eql("")
      pline = parser.parseLine(".if version > 8")
      pline.toString().should.eql(".if")
      pline = parser.parseLine(".if version <= 10")
      pline.toString().should.eql(".if")
      pline = parser.parseLine("  set a, 30")
      pline.toString().should.eql("SET <0>, <31, 30>")
      pline = parser.parseLine(".endif")
      pline.toString().should.eql(".endif")
      pline = parser.parseLine(".endif")
      pline.toString().should.eql(".endif")
