class AssemblerOutput
  # errorCount: number of errors discovered (reported through @logger)
  # lines: the list of compiled line objects. each compiled line is:
  #   - org: memory address of this line
  #   - data: words of compiled data (length may be 0, or quite large for
  #     expanded macros or "dat" blocks)
  constructor: (@errorCount, @lines) ->

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

exports.AssemblerOutput = AssemblerOutput