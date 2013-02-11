should = require 'should'
d16bunny = require '../src/d16bunny'

pp = d16bunny.pp

describe "Parser macros", ->
  it "parses a macro definition", ->
    parser = new d16bunny.Parser()
    pline = parser.parseLine("#macro swap(left, right) {")
    pline.toString().should.eql(".macro swap")
    pline.toDebug().should.eql("{directive:#macro} {identifier:swap}{directive:(}{identifier:left}{directive:,} " +
      "{identifier:right}{directive:)} {directive:{}")
    # check that it's there
    parser.macros["swap"].should.eql([ 2 ])
    parser.macros["swap(2)"].name.should.eql("swap")
    parser.macros["swap(2)"].fullname.should.eql("swap(2)")
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
    for text in [
      "#macro swap(left, right) {"
      "  set push, left"
      "  set left, right"
      "  set right, pop"
      "}"
    ] then parser.parseLine(text)
    pline = parser.parseLine("  swap(x, y)")
    pline.toString().should.eql("{ SET <24>, <3>; SET <3>, <4>; SET <4>, <24> }")
    pline.toDebug().should.eql("  {instruction:swap}{operator:(}{string:x}{operator:,} {string:y}{operator:)}")

  it "distinguishes two macros with the same name but different cardinality", ->
    parser = new d16bunny.Parser()
    for text in [
      "#macro inject(r) {"
      "  dat 1, r, 0"
      "}"
      "#macro inject(r1, r2) {"
      "  dat 2, r1, r2, 0"
      "}"
    ] then parser.parseLine(text)
    pline = parser.parseLine("inject 99")
    pline.toString().should.eql("{  }")
    pline.expanded[0].data.map((x) -> x.evaluate()).should.eql([ 1, 99, 0 ])
    pline = parser.parseLine("inject 10, 11")
    pline.toString().should.eql("{  }")
    pline.expanded[0].data.map((x) -> x.evaluate()).should.eql([ 2, 10, 11, 0 ])

  it "parses a nested macro call", ->
    parser = new d16bunny.Parser()
    for text in [
      "#macro save(r) {"
      "  set push, r"
      "}"
      "#macro restore(r) {"
      "  set r, pop"
      "}"
      "#macro swap(left, right) {"
      "  save(left)"
      "  set left, right"
      "  restore(right)"
      "}"
    ] then parser.parseLine(text)
    pline = parser.parseLine("  swap(x, y)")
    pline.toString().should.eql("{ SET <24>, <3>; SET <3>, <4>; SET <4>, <24> }")
    pline.toDebug().should.eql("  {instruction:swap}{operator:(}{string:x}{operator:,} {string:y}{operator:)}")

  it "parses a macro form of BRA", ->
    parser = new d16bunny.Parser()
    for text in [
      "#macro bra(addr) {"
      "  add pc, addr - .next"
      ":.next"
      "}"
    ] then parser.parseLine(text)
    pline = parser.parseLine("  bra 0x1000")
    label = pline.expanded[1].label
    (label.match(/bra\.(.*?)\.next/)?).should.equal(true)
    pline.toString().should.eql("{ ADD <28>, <31, (4096 - #{label})>; :#{label}  }")

  it "parses the argument offsets correctly for error handling", ->
    parser = new d16bunny.Parser()
    for text in [
      "#macro test(r1, r2) {"
      "  dat r1, r2"
      "}"
    ] then parser.parseLine(text)
    pline = parser.parseLine("test 0xffff, 0x1000")
    # kinda lame, but just verify the exact arg offsets
    pline.expanded[0].macroArgOffsets.should.eql([
      { arg: 0, left: 6, right: 12 }
      { arg: 1, left: 14, right: 20 }
    ])

  it "transforms an invalid macro parameter into an error at the caller", ->
    parser = new d16bunny.Parser()
    for text in [
      "#macro test(r1, r2) {"
      "  dat r1, r2"
      "}"
    ] then parser.parseLine(text)
    try
      parser.parseLine("test 0xffff, 99%")
      throw "fail"
    catch e
      e.type.should.eql("AssemblerError")
      e.pos.should.equal(13)
      e.message.should.match(/test/)
