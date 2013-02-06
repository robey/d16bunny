class AssemblerOutput
  # errors: array of errors discovered (and previously reported through
  #   the @logger attached to the Assembler)
  # lines: the list of compiled line objects. each compiled line is:
  #   - org: memory address of this line
  #   - data: words of compiled data (length may be 0, or quite large for
  #     expanded macros or "dat" blocks)
  # symtab: map of named variables/labels
  constructor: (@errors, @lines, @symtab) ->
    @lineMap = []
    for i in [0 ... @lines.length]
      line = @lines[i]
      size = line.data.length
      continue if size == 0
      @lineMap.push(org: line.address, end: line.address + size, lineno: i)
    @lineMap.sort((a, b) -> if a.org > b.org then 1 else -1)

  # pack the compiled line data into an array of contiguous memory blocks,
  # suitable for copying into an emulator or writing out to an object file.
  # returns an array of data blocks. each block is:
  #   - org: starting address of the block
  #   - data: data within this block
  # the blocks are sorted in org order.
  pack: ->
    if @cachedPack? then return @cachedPack
    if @errors.length > 0 or @lines.length == 0 then return []
    i = 0
    end = @lines.length
    blocks = []
    while i < end
      runStart = i
      orgStart = org = @lines[i].org
      while i < end and @lines[i].org == org
        org += @lines[i].data.length
        i++
      data = new Array(org - orgStart)
      n = 0
      for j in [runStart...i]
        k = @lines[j].data.length
        data[n ... n + k] = @lines[j].data
        n += k
      if data.length > 0 then blocks.push(org: orgStart, data: data)
    blocks.sort((a, b) -> a.org > b.org)
    @cachedPack = blocks
    blocks

  # return the line # of an address in the compiled code. if it's not an
  # address in this compilation, return null.
  memToLine: (address) ->
    lo = 0
    hi = @lineMap.length
    loop
      if lo >= hi then return null
      n = lo + Math.floor((hi - lo) / 2)
      line = @lineMap[n]
      if line.org <= address < line.end then return line.lineno
      if address < line.org then hi = n else lo = n + 1

  # return the line # closest to an address in the compiled code. if there's
  # nothing within 0x100, return null.
  memToClosestLine: (address) ->
    lo = 0
    hi = @lineMap.length
    loop
      if lo == hi
        # find closest candidate
        candidates = []
        if hi < @lineMap.length then candidates.push(addr: @lineMap[hi].org, lineno: @lineMap[hi].lineno)
        if lo > 0 then candidates.push(addr: @lineMap[lo - 1].end - 1, lineno: @lineMap[lo - 1].lineno)
        for c in candidates then c.distance = Math.abs(c.addr - address)
        candidates.sort (a, b) => a.distance - b.distance
        if candidates.length == 0 or candidates[0].distance > 0x100 then return null
        return candidates[0].lineno
      n = lo + Math.floor((hi - lo) / 2)
      line = @lineMap[n]
      if line.org <= address < line.end then return line.lineno
      if address < line.org then hi = n else lo = Math.min(n + 1, hi)

  # return the memory address containing code compiled from a given line.
  # if the line has no code on it, return null.
  lineToMem: (lineno) ->
    if lineno < 0 or lineno >= @lines.length then return null
    if @lines[lineno].data.length == 0 then return null
    @lines[lineno].org

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
      memory[block.org ... (block.org + block.data.length)] = block.data
    memory

exports.AssemblerOutput = AssemblerOutput
