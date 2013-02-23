should = require 'should'
d16bunny = require '../src/d16bunny'

pp = require('../src/d16bunny/prettyprint').prettyPrinter

describe "Disassembler", ->
  dis1 = (bytes...) ->
    d = new d16bunny.Disassembler(bytes)
    d.nextInstruction()

  dis1at = (address, bytes...) ->
    memory = []
    for word, i in bytes then memory[address + i] = word
    d = new d16bunny.Disassembler(memory)
    d.address = address
    d.nextInstruction()

  disat = (address, bytes...) ->
    memory = []
    for word, i in bytes then memory[address + i] = word
    d = new d16bunny.Disassembler(memory)
    d.disassemble()


  it "decodes a register SET", ->
    dis1(0x0401).toString().should.eql("SET A, B")

  it "decodes a dereferenced SET", ->
    dis1(0x0561).toString().should.eql("SET [X], B")

  it "decodes an indexed SET", ->
    dis1(0x0661, 0x0004).toString().should.eql("SET [X + 4], B")
    dis1(0x0661, 0x0104).toString().should.eql("SET [X + 0x104], B")
    dis1(0x0661, 0x0104).resolve(0x104: "house").toString().should.eql("SET [X + house], B")

  it "decodes an immediate", ->
    dis1(0x7c21, 0x0384).toString().should.eql("SET B, 0x384")

  it "decodes an immediate dereference", ->
    dis1(0x7821, 0x0384).toString().should.eql("SET B, [0x384]")

  it "decodes a packed immediate", ->
    dis1(0xa821).toString().should.eql("SET B, 9")
    dis1(0x8021).toString().should.eql("SET B, 0xffff")

  it "decodes POP", ->
    dis1(0x60e1).toString().should.eql("SET J, POP")

  it "decodes PUSH", ->
    dis1(0x1b01).toString().should.eql("SET PUSH, I")

  it "decodes PEEK", ->
    dis1(0x6461).toString().should.eql("SET X, PEEK")

  it "decodes PICK", ->
    dis1(0x6861, 0x0002).toString().should.eql("SET X, PICK 2")

  it "decodes SP, PC, EX", ->
    dis1(0x6c61).toString().should.eql("SET X, SP")
    dis1(0x7061).toString().should.eql("SET X, PC")
    dis1(0x7461).toString().should.eql("SET X, EX")

  it "gives up for DAT", ->
    dis1(0).toString().should.eql("DAT 0")
    dis1(0xfffd).toString().should.eql("DAT 0xfffd")

  describe "finds targets", ->
    it "in JSR", ->
      x = dis1(0x7c20, 0xfded)
      x.toString().should.eql("JSR 0xfded")
      x.target().should.eql(0xfded)

    it "in IAS", ->
      x = dis1(0x7d40, 0xfded)
      x.toString().should.eql("IAS 0xfded")
      x.target().should.eql(0xfded)

    it "in BRA", ->
      x = dis1at(0x2000, 0x9782)
      x.toString().should.eql("ADD PC, 4  ; 0x2005")
      x.target().should.eql(0x2005)

    it "in JMP", ->
      x = dis1(0x7f81, 0x9000)
      x.toString().should.eql("SET PC, 0x9000")
      x.target().should.eql(0x9000)

  describe "finds terminals", ->
    it "in RET", ->
      x = dis1(0x6381)
      x.toString().should.eql("SET PC, POP")
      x.terminal().should.eql(true)

    it "in JMP", ->
      x = dis1(0x7f81, 0x9000)
      x.toString().should.eql("SET PC, 0x9000")
      x.terminal().should.eql(true)

    it "in RFI", ->
      x = dis1(0x8560)
      x.toString().should.eql("RFI 0")
      x.terminal().should.eql(true)
    
    it "nowhere else", ->
      x = dis1(0xa821)
      x.toString().should.eql("SET B, 9")
      x.terminal().should.eql(false)

  it "processes a loop", ->
    x = disat(0x200, 0x8862, 0xd476, 0x9383, 0x6381)
    x.should.eql([
      ".ORG 0x200"
      ":t1"
      "  ADD X, 1"
      "  IFL X, 20"
      "    SUB PC, 3  ; t1"
      "  SET PC, POP"
    ])

  it "processes nested conditionals", ->
    x = disat(0, 0x9816, 0x9014, 0x8033, 0x14ac, 0x6381)
    x.should.eql([
      "  IFL A, 5"
      "    IFG A, 3"
      "      IFN B, 0xffff"
      "        XOR Z, Z"
      "  SET PC, POP"
    ])

  it "processes jumps", ->
    x = disat(0x2000, 0x7f81, 0x2002, 0x7f81, 0x2000)
    x.should.eql([
      ".ORG 0x2000"
      ":t1"
      "  SET PC, t2"
      ":t2"
      "  SET PC, t1"
    ])
