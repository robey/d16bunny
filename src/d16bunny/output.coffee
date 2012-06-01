class AssemblerOutput
  # errorCount: number of errors discovered (reported through @logger)
  # lines: the list of compiled line objects. each compiled line is:
  #   - org: memory address of this line
  #   - data: words of compiled data (length may be 0, or quite large for
  #     expanded macros or "dat" blocks)
  # symtab: map of named variables/labels
  constructor: (@errorCount, @lines, @symtab) ->
    @lineMap = []
    for i in [0 ... @lines.length]
      line = @lines[i]
      size = line.data.length
      continue if size == 0
      @lineMap.push(org: line.org, end: line.org + size, lineno: i)
    @lineMap.sort((a, b) -> if a.org > b.org then 1 else -1)

  # pack the compiled line data into an array of contiguous memory blocks,
  # suitable for copying into an emulator or writing out to an object file.
  # returns an array of data blocks. each block is:
  #   - org: starting address of the block
  #   - data: data within this block
  # the blocks are sorted in org order.
  pack: ->
    if @cachedPack? then return @cachedPack
    if @errorCount > 0 or @lines.length == 0 then return []
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
      blocks.push(org: orgStart, data: data)
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

  # return the memory address containing code compiled from a given line.
  # if the line has no code on it, return null.
  lineToMem: (lineno) ->
    if lineno < 0 or lineno >= @lines.length then return null
    if @lines[lineno].data.length == 0 then return null
    @lines[lineno].org

exports.AssemblerOutput = AssemblerOutput
