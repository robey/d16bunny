DataLine = require("./assembler").DataLine

class AssemblerOutput
  # errors: array of errors discovered (and previously reported through
  #   the @logger attached to the Assembler)
  # lines: the list of compiled line objects
  # symtab: map of named variables/labels
  constructor: (@errors, @lines, @symtab) ->
    @lineMap = []
    for i in [0 ... @lines.length]
      line = @lines[i]
      continue if not line?
      delete line.pline
      size = line.data.length
      continue if size == 0
      @lineMap.push(address: line.address, end: line.address + size, lineno: i)
    @lineMap.sort((a, b) -> if a.org > b.org then 1 else -1)

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
      if line.address <= address < line.end then return line.lineno
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
        if hi < @lineMap.length then candidates.push(addr: @lineMap[hi].address, lineno: @lineMap[hi].lineno)
        if lo > 0 then candidates.push(addr: @lineMap[lo - 1].end - 1, lineno: @lineMap[lo - 1].lineno)
        for c in candidates then c.distance = Math.abs(c.addr - address)
        candidates.sort (a, b) => a.distance - b.distance
        if candidates.length == 0 or candidates[0].distance > 0x100 then return null
        return candidates[0].lineno
      n = lo + Math.floor((hi - lo) / 2)
      line = @lineMap[n]
      if line.org <= address < line.end then return line.lineno
      if address < line.address then hi = n else lo = Math.min(n + 1, hi)

  # return the memory address containing code compiled from a given line.
  # if the line has no code on it, return null.
  lineToMem: (lineno) ->
    if lineno < 0 or lineno >= @lines.length then return null
    if @lines[lineno].data.length == 0 then return null
    @lines[lineno].address

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
      memory[block.address ... (block.address + block.data.length)] = block.data
    memory

exports.AssemblerOutput = AssemblerOutput
