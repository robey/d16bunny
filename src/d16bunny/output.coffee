DataLine = require("./assembler").DataLine
Disassembler = require("./disassembler").Disassembler
sprintf = require("sprintf").sprintf

class AssemblerOutput
  # errors: array of errors discovered (and previously reported through
  #   the @logger attached to the Assembler)
  # lines: the list of compiled line objects
  # symtab: map of named variables/labels
  # labels: the portion of symtab that refers only to code
  constructor: (@errors, @lines, @symtab, @labels) ->
    @lineMap = []
    for i in [0 ... @lines.length]
      line = @lines[i]
      continue if not line?
      size = line.data.length
      continue if size == 0
      @lineMap.push(address: line.address, end: line.address + size, lineNumber: i)
    @lineMap.sort((a, b) -> if a.address > b.address then 1 else -1)

  # pack the compiled line data into an array of contiguous memory blocks,
  # suitable for copying into an emulator or writing out to an object file.
  # returns an array of DataLines, sorted in address order.
  pack: ->
    if @cachedPack? then return @cachedPack
    if @errors.length > 0 or @lines.length == 0 then return []
    @cachedPack = @lines[0].pack(@lines)
    @cachedPack

  # return the line # of an address in the compiled code. if it's not an
  # address in this compilation, return null.
  memToLine: (address) ->
    lo = 0
    hi = @lineMap.length
    loop
      if lo >= hi then return null
      n = lo + Math.floor((hi - lo) / 2)
      line = @lineMap[n]
      if line.address <= address < line.end then return line.lineNumber
      if address < line.address then hi = n else lo = n + 1

  # return the line # closest to an address in the compiled code. if there's
  # nothing within 0x100, return null.
  memToClosestLine: (address) ->
    lo = 0
    hi = @lineMap.length
    loop
      if lo == hi
        # find closest candidate
        candidates = []
        if hi < @lineMap.length then candidates.push(addr: @lineMap[hi].address, lineNumber: @lineMap[hi].lineNumber)
        if lo > 0 then candidates.push(addr: @lineMap[lo - 1].end - 1, lineNumber: @lineMap[lo - 1].lineNumber)
        for c in candidates then c.distance = Math.abs(c.addr - address)
        candidates.sort (a, b) => a.distance - b.distance
        if candidates.length == 0 or candidates[0].distance > 0x100 then return null
        return candidates[0].lineNumber
      n = lo + Math.floor((hi - lo) / 2)
      line = @lineMap[n]
      if line.org <= address < line.end then return line.lineNumber
      if address < line.address then hi = n else lo = Math.min(n + 1, hi)

  # return the memory address containing code compiled from a given line.
  # if the line has no code on it, return null.
  lineToMem: (lineNumber) ->
    if lineNumber < 0 or lineNumber >= @lines.length then return null
    if @lines[lineNumber].data.length == 0 then return null
    @lines[lineNumber].address

  # put the compiled data into a 128KB memory image.
  # if 'memory' is passed in, it must be an array of at least 64K entries.
  # memory that isn't used by the compiled code will be left alone, so you
  # should zero it out before calling this function if you want that.
  # if 'memory' isn't passed in, an array of size 64K will be allocated and
  # pre-filled with zeros.
  createImage: (memory = null) ->
    if not memory?
      memory = new Array(0x10000)
      for j in [0...0x10000] then memory[j] = 0
    for block in @pack()
      # can't use splice here. apparently splice is recursive (!)
      for i in [0 ... block.data.length] then memory[block.address + i] = block.data[i]
    memory

  # create a disassembled form that is simple enough to be understood by
  # most other assemblers.
  disassemble: () ->
    memory = @createImage()
    disasm = new Disassembler(memory)
    labelMap = {}
    for k, v of @labels then if v != 0
      if not labelMap[v]? then labelMap[v] = []
      labelMap[v].push(k)
    origins = for block in @pack() then block.address
    rv = []
    lastLineWasBlank = false
    for dline, i in @lines
      continue unless dline.pline.line?
      [ prefix, suffix ] = dline.pline.line.getPrefixSuffix()
      address = @lineToMem(i)
      if not address?
        text = prefix + suffix
        if text.match(/^\s*$/)?
          if not lastLineWasBlank then rv.push(text)
          lastLineWasBlank = true
        else
          rv.push text
        continue
      lastLineWasBlank = false
      if address in origins
        rv.push ""
        rv.push "ORG 0x" + sprintf("%04x", address)
        rv.push ""
      if labelMap[address]? then for name in labelMap[address]
        rv.push ":#{name}"
      if dline.pline.data?.length > 0
        # DAT line
        makeLine = (segment) ->
          prefix + "DAT " + segment.map((x) -> sprintf("0x%04x", x)).join(", ") + suffix
        end = address + dline.pline.data.length
        while address + 8 < end
          rv.push makeLine(memory[address ... address + 8])
          address += 8
        rv.push makeLine(memory[address ... end])
      else
        instruction = disasm.getInstruction(address)
        instruction.resolve(labelMap)
        rv.push prefix + instruction.toString(labelMap) + suffix
    rv


exports.AssemblerOutput = AssemblerOutput
