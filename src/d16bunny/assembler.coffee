
Dcpu = require("./dcpu").Dcpu
Expression = require('./expression').Expression
Parser = require('./parser').Parser
Operand = require('./operand').Operand
Macro = require('./parser').Macro
AssemblerError = require('./errors').AssemblerError
AssemblerOutput = require('./output').AssemblerOutput
pp = require('./prettyprint').pp

BuiltinMacros = require("./builtins").BuiltinMacros


padding = "0000"
hex = (n) ->
  rv = n.toString(16)
  "0x#{padding[0 ... 4 - rv.length]}#{rv}"


# line compiled into data at an address.
# data is an array of 16-bit words.
# in mid-compilation, some items in 'data' may be unresolved equations.
# 'expanded' may contain an array of DataLine objects expanded from a macro.
class DataLine
  constructor: (@pline, @address = 0, @data = []) ->
    @expanded = null

  toString: ->
    extra = if @expanded?
      "{ " + @expanded.map((x) -> x.toString()).join(" / ") + " }"
    else 
      ""
    data = @data.map (item) =>
      if item instanceof Expression
        item.toString()
      else
        hex(item)
    "#{hex(@address)}: " + data.join(", ") + extra

  fail: (message) ->
    throw new AssemblerError(@pline.line.text, 0, message)

  flatten: ->
    if not @expanded? then return
    address = @address
    if @data.length > 0 then @fail "Internal error: Expanded macro has data"
    for dline in @expanded
      if dline.address != address then @fail "Internal error: Disjunct expanded macro"
      for x in dline.data then if typeof x != 'number' then @fail "Internal error: unresolved expression"
      @data = @data.concat dline.data
      address += dline.data.length
    delete @expanded

  nextAddress: ->
    address = @address
    if @expanded?
      for dline in @expanded
        address += dline.data.length
    address += @data.length
    address

  # pack a sequence of DataLine objects (one per line) into a smaller array.
  # in theory, each new DataLine object should have all the data between two
  # ORG changes. the new DataLine array is sorted in address order. ParsedLine
  # information is removed.
  pack: (dlines) -> 
    i = 0
    end = dlines.length
    blocks = []
    while i < end
      runStart = i
      addressStart = address = dlines[i].address
      while i < end and dlines[i].address == address
        address += dlines[i].data.length
        i++
      data = new Array(address - addressStart)
      n = 0
      for j in [runStart...i]
        k = dlines[j].data.length
        data[n ... n + k] = dlines[j].data
        n += k
      if data.length > 0 then blocks.push(new DataLine(null, addressStart, data))
    blocks.sort((a, b) -> a.address > b.address)
    blocks


# compile lines of DCPU assembly.
class Assembler
  # logger will be used to report errors: logger(line#, pos, message)
  # line # (y) and pos (x) are counted from zero.
  constructor: (@logger, @maxErrors = 10) ->
    if not @logger? then @logger = (filename, lineNumber, pos, reason) ->
    @includer = null
    @reset()

  reset: ->
    # current symbol table for resolving named references
    @symtab = {}
    @labels = {}
    # constants (copied into symtab) which don't change when code size changes.
    # they may still be unresolved (referring to labels).
    @constants = {}
    @errors = []
    @recompile = false

  debug: (list...) ->
    unless @debugger? then return
    slist = for item in list
      switch typeof item
        when 'string' then item.toString()
        else pp(item)
    @debugger(slist.join(""))

  fail: (x, message) ->
    throw new AssemblerError(@text, x, message)

  error: (filename, lineNumber, pos, reason) ->
    # because we do multiple resolve-phase passes, we might log the same error twice.
    for x in @errors then if x[0] == filename and x[1] == lineNumber and x[2] == pos and x[3] == reason then return
    @debug "  error on line #{lineNumber} at #{pos}: #{reason}"
    @logger(filename, lineNumber, pos, reason)
    @errors.push([ filename, lineNumber, pos, reason ])

  giveUp: ->
    @errors.length >= @maxErrors

  # internal: call a function, catching and reporting assembler errors.
  # returns null on error (or if there have been too many errors already).
  process: (filename, lineNumber, f, transformer) ->
    if @giveUp() then return null
    try
      f()
    catch e
      if e.type != "AssemblerError" then throw e
      pos = if e.pos? then e.pos else 0
      reason = if e.reason? then e.reason else e.toString()
      if transformer? then [ filename, lineNumber, pos, reason ] = transformer(filename, lineNumber, pos, reason)
      @error(filename, lineNumber, pos, reason)
      if @giveUp() then @error(filename, lineNumber, pos, "Too many errors; giving up.")
      null

  # do a full two-stage compile of this source.
  # returns an AssemblerOutput object with:
  #   - errors: list of errors discovered (also reported through @logger)
  #   - lines: the list of compiled line objects. each compiled line is:
  #     - address: memory address of this line
  #     - data: words of compiled data (length may be 0, or quite large for
  #       expanded macros or "dat" blocks)
  # the 'lines' output array will always be the same length as the 'lines'
  # input array, but the 'data' field on some lines may be empty if no code
  # was compiled for that line, or there were too many errors.
  #
  # the compiler will try to continue if there are errors, to greedily find
  # as many of the errors as it can. after 'maxErrors', it will stop.
  compile: (textLines, address=0, filename="") ->
    plines = @parse(textLines, filename)
    if @giveUp() then return new AssemblerOutput(@errors, [], @symtab)

    # repeat the compile/resolve cycle until we stop modifying the parsed
    # lines, either by optimizing, or compacting inline constants.
    @recompile = true
    originalAddress = address
    while @recompile
      @recompile = false
      address = originalAddress
      @symtab = {}
      @labels = {}
      for k, v of @constants then @symtab[k] = v
      dlines = plines.map (pline) =>
        if pline?
          dline = @compileLine(pline, address)
          @debug "  data: ", dline
          if dline? then address = dline.nextAddress()
          dline
        else
          null
      # force all unresolved expressions, because the symtab is now complete.
      for dline in dlines
        if dline?
          @resolveLine(dline)
          dline.flatten()
          # if anything failed, fill it in with zeros.
          for i in [0 ... dline.data.length]
            if typeof dline.data[i] == "object" then dline.data[i] = 0
    # make sure everything in the symtab is resolved now.
    for k, v of @symtab
      if v instanceof Expression then @symtab[k] = v.evaluate(@symtab) & 0xffff
    new AssemblerOutput(@errors, dlines, @symtab, @labels)

  # ----- parse phase

  parse: (textLines, filename) ->
    parser = new Parser()
    parser.debugger = @debugger
    @addBuiltinMacros(parser)
    plines = @parseChunk(parser, textLines, filename)
    for k, v of parser.constants then @constants[k] = v
    # resolve any expressions that can be taken care of by the constants
    for pline in plines then if pline? then pline.foldConstants(@constants)
    plines

  parseChunk: (parser, textLines, filename) ->
    plines = []
    for text, i in textLines
      pline = @process filename, i, => parser.parseLine(text, filename, i)
      return [] if @giveUp()
      continue unless pline?
      if pline.directive == "include"
        if not @includer?
          @error(filename, i, 0, "No mechanism to include files.")
        else
          newlines = @process filename, i, => @includer(pline.name)
          return [] if @giveUp()
          plines = plines.concat @parseChunk(parser, newlines, pline.name)
      plines.push(pline)
    plines

  addBuiltinMacros: (parser) ->
    for text, lineNumber in BuiltinMacros.split("\n")
      parser.parseLine(text, "(builtins)", lineNumber)

  # ----- compile phase

  # attempt to turn a ParsedLine into a DataLine.
  # the ParsedLine is left untouched unless an immediate value is newly
  # compactible, in which case @recompile is set, and the ParsedLine is
  # memoized with the compaction.
  compileLine: (pline, address) ->
    @debug "+ compiling @ ", address, ": ", pline

    # allow . and $ to refer to the current address
    @symtab["."] = address
    @symtab["$"] = address

    if pline.directive?
      switch pline.directive
        when "org" then address = pline.data[0]
    if pline.label?
      @symtab[pline.label] = address
      @labels[pline.label] = address
    if pline.data.length > 0 and not pline.directive?
      data = pline.data.map (expr) =>
        if (expr instanceof Expression) and expr.resolvable(@symtab)
          expr.evaluate(@symtab) & 0xffff
        else
          expr
      return new DataLine(pline, address, data)
    if pline.expanded?
      dline = new DataLine(pline, address, [])
      dline.expanded = pline.expanded.map (x) =>
        dataLine = @compileLine(x, address)
        address = dataLine.address + dataLine.data.length
        dataLine
      return dline
    if not pline.op? then return new DataLine(pline, address, [])

    dline = new DataLine(pline, address)
    @fillInstruction(dline)
    dline

  resolveLine: (dline, transformer=null) ->
    @debug "+ resolving @ ", dline.address, ": ", dline
    @symtab["."] = dline.address
    @symtab["$"] = dline.address
    dline.data = dline.data.map (item) =>
      if item instanceof Expression
        value = @process dline.pline.filename, dline.pline.lineNumber, (=> item.evaluate(@symtab) & 0xffff), transformer
        # we reported the error, so just save it as zero so we can try to continue.
        if value? then value else 0
      else
        item
    # fill in any missing bits we didn't know before symbols were resolved
    @fillInstruction(dline, true)
    # now that the expressions are all resolved, could this line have been
    # optimized, or compacted?
    @optimize(dline.pline)
    operands = dline.pline.operands
    if operands.length > 0
      operand = operands[operands.length - 1]
      if operand.checkCompact(@symtab)
        @debug "  compacted changed on ", operand
        # signal that we have to re-run compilation
        @recompile = true
    if dline.expanded?
      for dl in dline.expanded
        transformer = (filename, y, x, reason) =>
          for argOffset in dl.pline.macroArgOffsets then if x >= argOffset.left and x <= argOffset.right
            filename = dline.pline.filename
            y = dline.pline.lineNumber
            x = dline.pline.macroArgIndexes[argOffset.arg]
          [ filename, y, x, reason ]
        @resolveLine(dl, transformer)

  fillInstruction: (dline, force=false) ->
    pline = dline.pline
    if not pline.op? then return
    dline.data = [ 0 ]
    operandCodes = []
    if pline.operands.length > 0
      for i in [pline.operands.length - 1 .. 0]
        [ code, immediate ] = pline.operands[i].pack(@symtab)
        operandCodes.push(code)
        if immediate?
          if (immediate instanceof Expression) and force
            dline.data.push(0)
          else
            dline.data.push(immediate)
    if Dcpu.BinaryOp[pline.op]?
      dline.data[0] = (operandCodes[0] << 10) | (operandCodes[1] << 5) | Dcpu.BinaryOp[pline.op]
    else if Dcpu.SpecialOp[pline.op]?
      dline.data[0] = (operandCodes[0] << 10) | (Dcpu.SpecialOp[pline.op] << 5)


  # ----- optimizations

  optimize: (pline) ->
    @optimizeAdd(pline)

  # add/sub by a small negative constant can be flipped
  optimizeAdd: (pline) ->
    return if pline.op != "add" and pline.op != "sub"
    value = pline.operands[1].immediateValue(@symtab)
    return if not value? or value < 0xff00
    return unless pline.operands[0].code in [ Dcpu.Specials.pc, Dcpu.Specials.sp ]

    pline.op = (if pline.op == "add" then "sub" else "add")
    if pline.operands[1].expr?
      pline.operands[1].expr = Expression::Unary("", 0, "-", pline.operands[1].expr)
      pline.operands[1].immediate = null
    else
      pline.operands[1].immediate = 0x10000 - value
    @recompile = true
    @debug "  optimize/add: ", pline


exports.DataLine = DataLine
exports.Assembler = Assembler
