
Dcpu = require("./dcpu").Dcpu
Expression = require('./expression').Expression
Parser = require('./parser').Parser
Operand = require('./parser').Operand
Macro = require('./parser').Macro
AssemblerError = require('./errors').AssemblerError
AssemblerOutput = require('./output').AssemblerOutput
prettyPrinter = require('./prettyprint').prettyPrinter

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

  fail: (message) ->
    throw new AssemblerError(@pline.line.text, 0, message)

  flatten: ->
    if not @expanded? then return
    address = @address
    if @data.length > 0 then @fail "Internal error: Expanded macro has data"
    for xline in @expanded
      if xline.address != address then @fail "Internal error: Disjunct expanded macro"
      for x in xline.data then if typeof x != 'number' then @fail "Internal error: unresolved expression"
      @data = @data.concat xline.data
      address += xline.data.length
    delete @expanded

  resolve: (symtab) ->
    changed = false
    @resolved = true
    @data = @data.map (item) =>
      if item instanceof Expression
        if item.resolvable(symtab)
          changed = true
          item.evaluate(symtab)
        else
          @resolved = false
          item
      else
        item
    if @expanded?
      for xline in @expanded
        if xline.resolve(symtab) then changed = true
        if not xline.resolved then @resolved = false
    changed

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


# compile lines of DCPU assembly.
class Assembler
  # logger will be used to report errors: logger(line#, pos, message)
  # line # (y) and pos (x) are counted from zero.
  constructor: (@logger, @maxErrors = 10) ->
    @reset()

  reset: ->
    # current symbol table for resolving named references
    @symtab = {}
    @errors = []
    @shrunk = false

  debug: (list...) ->
    unless @debugger? then return
    slist = for item in list
      switch typeof item
        when 'string' then item.toString()
        else prettyPrinter.dump(item)
    @debugger(slist.join(""))

  fail: (x, message) ->
    throw new AssemblerError(@text, x, message)

  error: (lineNumber, pos, reason) ->
    @debug "  error on line #{lineNumber} at #{pos}: #{reason}"
    @logger(lineNumber, pos, reason)
    @errors.push([ lineNumber, pos, reason ])

  giveUp: ->
    @errors.length >= @maxErrors

  # internal: call a function, catching and reporting assembler errors.
  # returns null on error (or if there have been too many errors already).
  process: (lineNumber, f) ->
    if @giveUp() then return null
    try
      f()
    catch e
      if e.type != "AssemblerError" then throw e
      pos = if e.pos? then e.pos else 0
      reason = if e.reason? then e.reason else e.toString()
      @error(lineNumber, pos. reason)
      if @giveUp() then @error(lineNumber, pos, "Too many errors; giving up.")
      null
    
  compile: (textLines, address = 0) ->
    plines = @parse(textLines)
    if @giveUp then return new AssemblerOutput(@errors, [], @symtab)
    for pline in plines then @validate(pline)
    if @giveUp then return new AssemblerOutput(@errors, [], @symtab)
    dlines = plines.map (pline) =>
      dline = @process pline.lineNumber, => @compileLine(pline, address)
      if @giveUp() then return new AssemblerOutput(@errors, [], @symtab)
      address = dline.address
      dline



    @infos = []
    errorCount = 0
    giveUp = false
    defaultValue = { org: org, data: [] }
    process = (lineno, f) => 3
    # pass 1:
    for i in [0 ... lines.length]
      line = lines[i]
      info = process i, => @compileLine(line, org)
      @infos.push(info)
      org = info.org + info.data.length
    # pass 2:
    for i in [0 ... lines.length]
      info = @infos[i]
      process i, => @resolveLine(info)
      # if anything failed, fill it in with zeros.
      for j in [0 ... info.data.length]
        if typeof info.data[j] == 'object'
          info.data[j] = 0
    @lastOrg = org
    new AssemblerOutput(errorCount, @infos, @symtab)

  # ----- parse phase

  parse: (textLines) ->
    parser = new Parser()
    parser.debugger = @debugger
    @addBuiltinMacros(parser)
    plines = []
    for text, i in textLines
      pline = @process i, => parser.parseLine(text, i)
      break if @giveUp()
      plines.push(pline)
    @addConstants(parser.constants)
    # resolve any expressions that can be taken care of by the constants
    for pline in plines then pline.resolve(@symtab)
    plines

  # given a map of (key -> expr), try to resolve them all and add them into
  # the symtab of (key -> value). throw an error if any are unresolvable.
  addConstants: (constants) ->
    unresolved = {}
    for k, v of constants then unresolved[k] = v
    while Object.keys(unresolved).length > 0
      progress = false
      for k, v of unresolved
        if v.resolvable(@symtab)
          @symtab[k] = v.evaluate(@symtab)
          delete unresolved[k]
          progress = true
      if not progress
        for k, v of unresolved
          @process v.lineNumber, => v.evaluate(@symtab)

  addBuiltinMacros: (parser) ->
    for text, lineNumber in BuiltinMacros.split("\n")
      parser.parseLine(text, lineNumber)

  # ----- validate phase

  validateLine: (pline) ->
    data = [ 0 ]
    operandCodes = []
    if Dcpu.BinaryOp[pline.op]?
      if pline.operands.length != 2
        pline.fail "#{pline.op.toUpperCase()} requires 2 arguments"
    else if Dcpu.SpecialOp[pline.op]?
      if pline.operands.length != 1
        pline.fail "#{pline.op.toUpperCase()} requires 1 argument"
    else
      pline.fail "Unknown instruction: #{pline.op}"

  # ----- compile phase

  # attempt to turn a ParsedLine into a DataLine.
  # the ParsedLine is left untouched unless an immediate value is newly
  # compactible, in which case @shrunk is set, and the ParsedLine is
  # memoized with the compaction.
  compileLine: (pline, address) ->
    @debug "+ compiling @ ", address, ": ", pline

    # allow . and $ to refer to the current address
    @symtab["."] = address
    @symtab["$"] = address

    if pline.directive?
      switch pline.directive
        when "org" then address = pline.data.pop()
    if pline.label? then @symtab[pline.label] = address
    if pline.data.length > 0
      data = pline.data.map (expr) =>
        if (expr instanceof Expression) and expr.resolvable(@symtab) then expr.evaluate(@symtab) else expr
      return new DataLine(pline, address, data)
    if pline.expanded?
      rv = new DataLine(pline, address, [])
      rv.expanded = pline.expanded.map (x) =>
        dataLine = @compileLine(x, address)
        address = dataLine.address + dataLine.data.length
        dataLine
      return rv
    if not pline.op? then return new DataLine(pline, address, [])

    pline = @optimize(pline)

    data = [ 0 ]
    operandCodes = []
    if pline.operands.length > 0
      for i in [pline.operands.length - 1 .. 0]
        operand = pline.operands[i]
        canCompact = (i == pline.operands.length - 1)
        # do any easy compactions.
        if canCompact and operand.checkCompact(@symtab)
          @debug "  compacted ", operand
          @shrunk = true
        [ code, immediate ] = operand.pack(@symtab, canCompact)
        operandCodes.push(code)
        if immediate? then data.push(immediate)
    if Dcpu.BinaryOp[pline.op]?
      data[0] = (operandCodes[0] << 10) | (operandCodes[1] << 5) | Dcpu.BinaryOp[pline.op]
    else if Dcpu.SpecialOp[pline.op]?
      data[0] = (operandCodes[0] << 10) | (Dcpu.SpecialOp[pline.op] << 5)


    new DataLine(pline, address, data)

  # ----- optimizations

  optimize: (pline) ->
    @optimizeAdd(pline)

  # add/sub by a small negative constant can be flipped
  optimizeAdd: (pline) ->
    if pline.op != "add" and pline.op != "sub" then return pline
    value = pline.operands[1].immediateValue(@symtab)
    if not value? or value < 0xff00 then return pline
    newline = pline.clone()
    newline.op = (if pline.op == "add" then "sub" else "add")
    newline.operands[1].immediate = 0x10000 - value
    @debug "  optimize/add: ", newline
    newline




  # do a full two-stage compile of this source.
  # returns an AssemblerOutput object with:
  #   - errorCount: number of errors discovered (reported through @logger)
  #   - lines: the list of compiled line objects. each compiled line is:
  #     - org: memory address of this line
  #     - data: words of compiled data (length may be 0, or quite large for
  #       expanded macros or "dat" blocks)
  # the 'lines' output array will always be the same length as the 'lines'
  # input array, but the 'data' field on some lines may be empty if no code
  # was compiled for that line, or there were too many errors.
  #
  # the compiler will try to continue if there are errors, to greedily find
  # as many of the errors as it can. after 'maxErrors', it will stop.
  compile: (lines, org = 0, maxErrors = 10) ->
    @infos = []
    errorCount = 0
    giveUp = false
    defaultValue = { org: org, data: [] }
    process = (lineno, f) => 3
    # pass 1:
    for i in [0 ... lines.length]
      line = lines[i]
      info = process i, => @compileLine(line, org)
      @infos.push(info)
      org = info.org + info.data.length
    # pass 2:
    for i in [0 ... lines.length]
      info = @infos[i]
      process i, => @resolveLine(info)
      # if anything failed, fill it in with zeros.
      for j in [0 ... info.data.length]
        if typeof info.data[j] == 'object'
          info.data[j] = 0
    @lastOrg = org
    new AssemblerOutput(errorCount, @infos, @symtab)



  # force resolution of any unresolved expressions.
  resolveLine: (info) ->
    @symtab["."] = info.org
    if info.branchFrom
      # finally resolve (short) relative branch
      @debug "  resolve bra: ", info
      dest = info.data[0].expr.evaluate(@symtab)
      offset = info.branchFrom - dest
      if offset < -30 or offset > 30
        @fail info.data[0].pos, "Short branch can only move 30 words away (here: " + Math.abs(offset) + ")"
      opcode = if offset < 0 then Dcpu.BinaryOp.add else Dcpu.BinaryOp.sub
      info.data[0] = ((Math.abs(offset) + 0x21) << 10) | (Dcpu.Specials.pc << 5) | opcode
      delete info.branchFrom
    @debug "  resolve: ", info
    for i in [0 ... info.data.length]
      if typeof info.data[i] == 'object'
        info.data[i] = info.data[i].evaluate(@symtab)
    info

  # do a full two-stage compile of this source.
  # returns an AssemblerOutput object with:
  #   - errorCount: number of errors discovered (reported through @logger)
  #   - lines: the list of compiled line objects. each compiled line is:
  #     - org: memory address of this line
  #     - data: words of compiled data (length may be 0, or quite large for
  #       expanded macros or "dat" blocks)
  # the 'lines' output array will always be the same length as the 'lines'
  # input array, but the 'data' field on some lines may be empty if no code
  # was compiled for that line, or there were too many errors.
  #
  # the compiler will try to continue if there are errors, to greedily find
  # as many of the errors as it can. after 'maxErrors', it will stop.
  compile: (lines, org = 0, maxErrors = 10) ->
    @infos = []
    @continueCompile(lines, org, maxErrors)

  # compile new lines without clearing out old compiled blocks.
  # may be used to compile several files as if they were one unit.
  # this function does not know/care if a previous run had errors, so you
  # should check the errorCount after each run.
  continueCompile: (lines, org = null, maxErrors = 10) ->
    if not org? then org = @lastOrg
    errorCount = 0
    giveUp = false
    defaultValue = { org: org, data: [] }
    process = (lineno, f) =>
      if giveUp then return defaultValue
      try
        f()
      catch e
        if e.type != "AssemblerError" then throw e
        pos = if e.pos? then e.pos else 0
        reason = if e.reason? then e.reason else e.toString()
        @debug "  error on line ", lineno, " at ", pos, ": ", reason
        @logger(lineno, pos, reason)
        errorCount++
        if errorCount >= maxErrors
          @debug "  too many errors"
          @logger(lineno, 0, "Too many errors; giving up.")
          giveUp = true
        defaultValue
    # pass 1:
    for i in [0 ... lines.length]
      line = lines[i]
      info = process i, => @compileLine(line, org)
      @infos.push(info)
      org = info.org + info.data.length
    # pass 2:
    for i in [0 ... lines.length]
      info = @infos[i]
      process i, => @resolveLine(info)
      # if anything failed, fill it in with zeros.
      for j in [0 ... info.data.length]
        if typeof info.data[j] == 'object'
          info.data[j] = 0
    @lastOrg = org
    new AssemblerOutput(errorCount, @infos, @symtab)

exports.Assembler = Assembler
exports.AssemblerError = AssemblerError
