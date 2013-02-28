should = require "should"
d16bunny = require "../src/d16bunny"

pp = d16bunny.pp

trimHtml = (html) ->
  # try to reign in the html for testing
  html = html.replace(/<span class="syntax-([\w\-]+)">/g, "{$1:")
  html = html.replace(/<\/span>/g, "}")
  html

parseLine = (s) ->
  parser = new d16bunny.Parser()
  pline = parser.parseLine(s)
  html = pline.toDebug()
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
    line.toDebug().should.eql("{string:\"hello sailor}{string-escape:\\x21}{string:\"}")

  describe "parseExpression", ->
    parseExpression = (s) ->
      p = new d16bunny.Parser()
      line = new d16bunny.Line(s)
      [ p.parseExpression(line), line ]

    it "parses simple binary expressions", ->
      [ e, line ] = parseExpression(" 2 + 5 * x + smile")
      e.toString().should.equal("((2 + (5 * X)) + smile)")
      line.toDebug().should.eql(" {number:2} {operator:+} {number:5} {operator:*} {register:x} {operator:+} {identifier:smile}")

    it "parses hex and binary constants", ->
      [ e, line ] = parseExpression("0x100 * -0b0010")
      e.toString().should.equal("(256 * (-2))")
      line.toDebug().should.eql("{number:0x100} {operator:*} {operator:-}{number:0b0010}")

    it "understands shifting and precedence", ->
      [ e, line ] = parseExpression("8 + 9 << 3 + 4")
      e.toString().should.equal("((8 + 9) << (3 + 4))")
      line.toDebug().should.eql("{number:8} {operator:+} {number:9} {operator:<<} {number:3} {operator:+} {number:4}")

    it "parses character literals", ->
      [ e, line ] = parseExpression("'p' - '\\x40'")
      e.toString().should.equal("(112 - 64)")
      line.toDebug().should.eql("{string:'p'} {operator:-} {string:'}{string-escape:\\x40}{string:'}")

    it "parses unix-style registers", ->
      [ e, line ] = parseExpression("(0x2300 + %j)")
      e.toString().should.equal("(8960 + J)")
      line.toDebug().should.eql("{operator:(}{number:0x2300} {operator:+} {register:%j}{operator:)}")

    it "evaluates simple expressions", ->
      [ e, line ] = parseExpression("9")
      e.evaluate().should.equal(9)
      line.toDebug().should.eql("{number:9}")

    it "evaluates labels", ->
      [ e, line ] = parseExpression("2 + hello * 3")
      e.evaluate(hello: 10).should.equal(32)
      line.toDebug().should.eql("{number:2} {operator:+} {identifier:hello} {operator:*} {number:3}")

    it "evaluates complex expressions", ->
      [ e, line ] = parseExpression("((offset & 0b1111) << 4) * -ghost")
      e.evaluate(ghost: 2, offset: 255).should.equal(-480)
      line.toDebug().should.eql("{operator:((}{identifier:offset} {operator:&} {number:0b1111}{operator:)} " +
        "{operator:<<} {number:4}{operator:)} {operator:*} {operator:-}{identifier:ghost}")

    it "throws an exception for unknown labels", ->
      [ e, line ] = parseExpression("cats + dogs")
      (-> e.evaluate(cats: 5)).should.throw(/resolve/)
      e.resolvable().should.equal(false)
      e.resolvable(cats: 5).should.equal(false)
      e.resolvable(cats: 5, dogs: 10).should.equal(true)
      line.toDebug().should.eql("{identifier:cats} {operator:+} {identifier:dogs}")

    it "evaluates <, <=, >, >=", ->
      [ e, line ] = parseExpression("errors > 9")
      e.evaluate(errors: 10).should.equal(1)
      e.evaluate(errors: 3).should.equal(0)
      [ e, line ] = parseExpression("errors < 9")
      e.evaluate(errors: 10).should.equal(0)
      e.evaluate(errors: 3).should.equal(1)
      [ e, line ] = parseExpression("errors >= 9")
      e.evaluate(errors: 10).should.equal(1)
      e.evaluate(errors: 9).should.equal(1)
      e.evaluate(errors: 3).should.equal(0)
      [ e, line ] = parseExpression("errors <= 9")
      e.evaluate(errors: 10).should.equal(0)
      e.evaluate(errors: 9).should.equal(1)
      e.evaluate(errors: 3).should.equal(1)

    it "evaluates ==, !=", ->
      [ e, line ] = parseExpression("errors | 1 == 9")
      e.evaluate(errors: 8).should.equal(1)
      e.evaluate(errors: 6).should.equal(0)
      [ e, line ] = parseExpression("errors | 1 != 9")
      e.evaluate(errors: 8).should.equal(0)
      e.evaluate(errors: 6).should.equal(1)

  describe "parseOperand", ->
    html = ""

    parseOperand = (s, symtab={}, destination=false) ->
      p = new d16bunny.Parser()
      line = new d16bunny.Line(s)
      x = p.parseOperand(line, destination)
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
      parseOperand("[a+9]").should.eql("<16, 9>")
      html.should.eql("{operator:[}{register:a}{operator:+}{number:9}{operator:]}")
      parseOperand("[a-2]").should.eql("<16, 65534>")
      html.should.eql("{operator:[}{register:a}{operator:-}{number:2}{operator:]}")

    it "parses complex pointer operations", ->
      parseOperand("[15+24+i]").should.eql("<22, 39>")
      html.should.eql("{operator:[}{number:15}{operator:+}{number:24}{operator:+}{register:i}{operator:]}")
      parseOperand("[i+15+24]").should.eql("<22, 39>")
      html.should.eql("{operator:[}{register:i}{operator:+}{number:15}{operator:+}{number:24}{operator:]}")
      parseOperand("[15+i+24]").should.eql("<22, 39>")
      html.should.eql("{operator:[}{number:15}{operator:+}{register:i}{operator:+}{number:24}{operator:]}")

    it "parses pick", ->
      parseOperand("pick 23").should.eql("<26, 23>")
      html.should.eql("{register:pick} {number:23}")

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

    it "parses trailing comments", ->
      [ pline, html ] = parseLine("SUB A, [0x1000]            ; 7803 1000")
      pline.toString().should.eql("SUB <0>, <30, 4096>")
      pline.toDebug().should.eql("{instruction:SUB} {register:A}{operator:,} {operator:[}{number:0x1000}{operator:]}            " +
        "{comment:; 7803 1000}")

    it "parses trailing comments in dat lines", ->
      [ pline, _ ] = parseLine(":old_ia dat 0       ; chained interrupt handler")
      pline.toString().should.eql(":old_ia ")
      pline.toDebug().should.eql("{label::old_ia} {instruction:dat} {number:0}       {comment:; chained interrupt handler}")

    it "parses a single op", ->
      [ pline, html ] = parseLine("  hwi 0")
      pline.toString().should.eql("HWI <31, 0>")
      html.should.eql("  {instruction:hwi} {number:0}")

    it "parses a labeled line", ->
      [ pline, html ] = parseLine(":start")
      pline.toString().should.eql(":start ")
      html.should.eql("{label::start}")
      [ pline, html ] = parseLine(":start  hwi 0")
      pline.toString().should.eql(":start HWI <31, 0>")
      html.should.eql("{label::start}  {instruction:hwi} {number:0}")

    it "parses a line with operands", ->
      [ pline, html ] = parseLine(":last set [a], ','")
      pline.toString().should.eql(":last SET <8>, <31, 44>")
      html.should.eql("{label::last} {instruction:set} {operator:[}{register:a}{operator:],} {string:','}")

    it "parses pick", ->
      [ pline, html ] = parseLine("set a, PICK 3")
      pline.toString().should.eql("SET <0>, <26, 3>")
      html.should.eql("{instruction:set} {register:a}{operator:,} {register:PICK} {number:3}")

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

    it "parses a definition with preserved case", ->
      [ pline, html, constants ] = parseLine("#define HappY 23")
      constants["HappY"].evaluate().should.eql(23)
      pline.toString().should.eql("")
      html.should.eql("{directive:#define} {identifier:HappY} \{number:23}")

    it "parses data", ->
      [ pline, html ] = parseLine("dat 3, 9, '@', \"cat\", p\"cat\"")
      pline.toString().should.eql("")
      pline.foldConstants()
      pline.data.should.eql([ 3, 9, 0x40, 0x63, 0x61, 0x74, 0x6361, 0x7400 ])
      html.should.eql("{instruction:dat} {number:3}{operator:,} {number:9}{operator:,} " +
        "{string:'@'}{operator:,} {string:\"cat\"}{operator:,} {string:p\"cat\"}")
      [ pline, html ] = parseLine(".dat 8, 7")
      pline.toString().should.eql("")
      pline.foldConstants()
      pline.data.should.eql([ 8, 7 ])

    it "parses data with unresolved expression", ->
      [ pline, html ] = parseLine("dat 3, 9, cat + 1")
      pline.toString().should.eql("")
      pline.data[0].evaluate().should.eql(3)
      pline.data[1].evaluate().should.eql(9)
      pline.data[2].resolvable().should.eql(false)
      pline.data[2].resolvable(cat: 9).should.eql(true)
      pline.data[2].evaluate(cat: 9).should.eql(10)
      pline.toDebug().should.eql("{instruction:dat} {number:3}{operator:,} {number:9}{operator:,} " +
        "{identifier:cat} {operator:+} {number:1}")

    it "parses fill", ->
      [ pline, html ] = parseLine(".fill 6, 900")
      pline.toString().should.eql(".fill")
      pline.foldConstants()
      pline.data.should.eql([ 900, 900, 900, 900, 900, 900 ])
      html.should.eql("{directive:.fill} {number:6}{operator:,} {number:900}")
      [ pline, html ] = parseLine(".fill 6, hello")
      pline.toString().should.eql(".fill")
      pline.foldConstants(hello: 901)
      pline.data.should.eql([ 901, 901, 901, 901, 901, 901 ])
      html.should.eql("{directive:.fill} {number:6}{operator:,} {identifier:hello}")
      [ pline, html ] = parseLine(".fill count, hello")
      pline.toString().should.eql(".fill")
      pline.foldConstants(count: 3, hello: 902)
      pline.data.should.eql([ 902, 902, 902 ])
      html.should.eql("{directive:.fill} {identifier:count}{operator:,} {identifier:hello}")

    it "parses rom strings", ->
      [ pline, html ] = parseLine("dat r\"cat\"")
      pline.toString().should.eql("")
      pline.data.map((x) => x.evaluate()).should.eql([ 0x6361, 0xf400 ])
      html.should.eql("{instruction:dat} {string:r\"cat\"}")

    it "parses org changes", ->
      [ pline, html ] = parseLine(".org 0x1000")
      pline.toString().should.eql(".org")
      pline.data.should.eql([ 4096 ])
      html.should.eql("{directive:.org} {number:0x1000}")
      [ pline, html ] = parseLine("  org 3")
      pline.toString().should.eql(".org")
      pline.data.should.eql([ 3 ])
      html.should.eql("  {directive:org} {number:3}")

    it "disallows an unknown opcode", ->
      (-> parseLine("qxq 9")).should.throw(/qxq/)

    it "requires binary operations to have 2 arguments", ->
      (-> parseLine("add x")).should.throw(/requires 2 arguments/)
      (-> parseLine("add x, y, z")).should.throw(/requires 2 arguments/)

    it "requires special operations to have 1 argument", ->
      (-> parseLine("jsr")).should.throw(/requires 1 argument/)
      (-> parseLine("jsr x, y")).should.throw(/requires 1 argument/)

    it "can ignore errors for syntax highlighting", ->
      parser = new d16bunny.Parser()
      pline = parser.parseLine("sum(3, 4)", "", 0, ignoreErrors: true)
      pline.line.toDebug().should.eql("{instruction:sum}{operator:(}{string:3}{operator:,} {string:4}{operator:)}")

    it "parses an include", ->
      parser = new d16bunny.Parser()
      pline = parser.parseLine(".include \"frosty.dasm\"")
      pline.line.toDebug().should.eql("{directive:.include} {string:\"frosty.dasm\"}")
      pline.directive.should.eql("include")
      pline.name.should.eql("frosty.dasm")

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
