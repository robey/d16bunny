
Dcpu = require("./dcpu").Dcpu
Operand = require('./operand').Operand
pp = require('./prettyprint').pp

class Instruction
  constructor: (@pc, @words, @opname, @a, @b, @aArgument, @bArgument) ->

  # if any of the arguments are labels, use the label name.
  resolve: (labels) ->
    if @aArgument? and labels[@aArgument]? then @aArgument = labels[@aArgument][0]
    if @bArgument? and labels[@bArgument]? then @bArgument = labels[@bArgument][0]
    this

  stringify: (x) ->
    if typeof x == "number"
      if x < 32 then x.toString() else "0x#{x.toString(16)}"
    else
      x.toString()

  decodeOperand: (op, argument, dest=false) ->
    if op >= Operand.Register and op < Operand.Register + 8
      Dcpu.RegisterNames[op]
    else if op >= Operand.RegisterDereference and op < Operand.RegisterDereference + 8
      "[#{Dcpu.RegisterNames[op - Operand.RegisterDereference]}]"
    else if op >= Operand.RegisterIndex and op < Operand.RegisterIndex + 8
      "[#{Dcpu.RegisterNames[op - Operand.RegisterIndex]} + #{@stringify(argument)}]"
    else if op == Dcpu.Specials["pop"]
      if dest then "PUSH" else "POP"
    else if op == Dcpu.Specials["peek"]
      "PEEK"
    else if op == Dcpu.Specials["pick"]
      "PICK #{@stringify(argument)}"
    else if op == Dcpu.Specials["sp"]
      "SP"
    else if op == Dcpu.Specials["pc"]
      "PC"
    else if op == Dcpu.Specials["ex"]
      "EX"
    else if op == Operand.ImmediateDereference
      "[#{@stringify(argument)}]"
    else if op == Operand.Immediate
      @stringify(argument)
    else
      "wut"

  toString: (labels) ->
    bString = if @b? then "#{@decodeOperand(@b, @bArgument, true)}, " else ""
    aString = @decodeOperand(@a, @aArgument)
    target = @target()
    if target
      target = if labels? and labels[target]? then labels[target][0] else @stringify(target)
    comment = if target? and target != aString then "  ; #{target}" else ""
    "#{@opname.toUpperCase()} #{bString}#{aString}#{comment}"

  # if this instruction has an easily-understood target, return it
  target: ->
    if @opname in [ "jsr", "ias" ] and @a == Operand.Immediate
      @aArgument
    else if @opname in [ "set", "add", "sub", "xor" ] and @b == Dcpu.Specials["pc"] and @a == Operand.Immediate
      switch @opname
        when "set" then @aArgument
        when "add" then ((@pc + @words) + @aArgument) & 0xffff
        when "sub" then ((@pc + @words) - @aArgument) & 0xffff
        when "xor" then ((@pc + @words) ^ @aArgument) & 0xffff
        else null
    else
      null

  # will this instruction change PC?
  terminal: ->
    @opname == "rfi" or (@opname in [ "set", "add", "sub", "xor", "adx", "sbx", "sti", "std" ] and @b == Dcpu.Specials["pc"])

  conditional: ->
    @opname[0..1] == "if"


class Disassembler
  hasImmediate:
    0x10: true
    0x11: true
    0x12: true
    0x13: true
    0x14: true
    0x15: true
    0x16: true
    0x17: true
    0x1a: true
    0x1e: true
    0x1f: true

  constructor: (@memory) ->
    @address = 0

  nextWord: ->
    word = @memory[@address] || 0
    @address = (@address + 1) & 0xffff
    word

  nextInstruction: ->
    pc = @address
    word = @nextWord()
    if word == 0 then return null
    opcode = word & 0x1f
    a = (word >> 10) & 0x3f
    b = (word >> 5) & 0x1f
    aArgument = null
    bArgument = null
    if opcode == 0
      # special
      opcode = b
      b = null
      opname = Dcpu.SpecialOpNames[opcode]
      if opname? then aArgument = if @hasImmediate[a] then @nextWord() else null
    else
      # binary
      opname = Dcpu.BinaryOpNames[opcode]
      if opname?
        aArgument = if @hasImmediate[a] then @nextWord() else null
        bArgument = if @hasImmediate[b] then @nextWord() else null
    if opname?
      # go ahead and decode embedded immediates
      if a >= 0x20
        aArgument = (a - 0x21) & 0xffff
        a = Operand.Immediate
    else
      opname = "DAT"
      aArgument = word
      a = Operand.Immediate
      b = null
    new Instruction(pc, @address - pc, opname, a, b, aArgument, bArgument)

  getInstruction: (address) ->
    @address = address
    x = @nextInstruction()
    if not x?
      x = new Instruction(address, 1, "DAT", Operand.Immediate, null, 0, null)
    x

  disassemble: ->
    out = []
    instructions = []
    # first, skip all zeros.
    while (@memory[@address] or 0) == 0 and @address < 0x10000 then @address += 1
    if @address >= 0x10000 then return []
    # also, ignore zeros from the end.
    end = 0x10000
    while (@memory[end - 1] or 0) == 0 then end -= 1
    # now, process all instructions.
    while @address < end
      x = @nextInstruction()
      if x? then instructions.push(x)
    # build up labels
    targets = []
    labels = {}
    for x in instructions
      target = x.target()
      if target? then targets.push(target)
    targets.sort()
    for t, i in targets
      if not labels[t]? then labels[t] = []
      labels[t].push "t#{i + 1}"
    # fill in labels
    for x in instructions then x.resolve(labels)
    # flush
    start = 0
    indent = "  "
    labeled = {}
    for x in instructions
      if x.pc != start
        if labels[start]? then for name in labels[start]
          out.push(":#{name}")
          labeled[start] = true
        out.push("")
        out.push(".ORG 0x#{x.pc.toString(16)}")
        indent = "  "
      if labels[x.pc]? then for name in labels[x.pc]
        out.push(":#{name}")
        labeled[x.pc] = true
      out.push(indent + x.toString(labels))
      indent = if x.conditional() then (indent + "  ") else "  "
      start = x.pc + x.words
    # clean up missing labels
    for address, list of labels
      if not labeled[address] then for name in list
        out.unshift(".DEFINE #{name} 0x#{parseInt(address).toString(16)}")
    out


exports.Disassembler = Disassembler
