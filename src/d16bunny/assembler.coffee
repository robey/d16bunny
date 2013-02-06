
Dcpu = require("./dcpu").Dcpu
Expression = require('./expression').Expression
Parser = require('./parser').Parser
Operand = require('./parser').Operand
Macro = require('./parser').Macro
AssemblerError = require('./errors').AssemblerError
AssemblerOutput = require('./output').AssemblerOutput
prettyPrinter = require('./prettyprint').prettyPrinter

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

  # internal: call a function, catching and reporting assembler errors.
  # returns null on error (or if there have been too many errors already).
  process: (lineNumber, f) ->
    if @errors.length >= @errorCount then return null
    try
      f()
    catch e
      if e.type != "AssemblerError" then throw e
      pos = if e.pos? then e.pos else 0
      reason = if e.reason? then e.reason else e.toString()
      @error(lineNumber, pos. reason)
      if @errors.length >= @errorCount
        @error(lineNumber, pos, "Too many errors; giving up.")
      null
    
  parse: (textLines, maxErrors = 10) ->
    parser = new Parser()
    parser.debugger = @debugger
    @addBuiltinMacros(parser)
    plines = []
    for text, i in textLines
      pline = @process i, => parser.parseLine(text, i)
      break if @errors.length >= @errorCount
      plines.push(pline)
    @addConstants(parser.constants)
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

  # compile a line of code at a given address.
  # fields that can't be resolved yet will be left as expression trees, but the data size will be
  # computed.
  # returns an object with:
  #   - data: compiled output, made up either of words or unresolved expression trees
  #   - org: the memory location (pc) where this data starts
  #   - branchFrom: (optional) if this is a relative-branch instruction






  # builtin macros
  builtins:
    jmp: [
      ".macro jmp(addr) {"
      "  set pc, addr"
      "}"
    ]
    hlt: [
      ".macro hlt {"
      "  sub pc, 1"
      "}"
    ]
    ret: [
      ".macro ret {"
      "  set pc, pop"
      "}"
    ]
    bra: [
      ".macro bra(addr) {"
      ".error \"Illegal argument to BRA.\""
      "  add pc, addr - .next"
      ":.next"
      "}"
    ]

  addBuiltinMacros: (parser) ->
    for name, textLines of @builtins
      for text, lineNumber in textLines
        parser.parseLine(text, lineNumber)

  # attempt to turn a parsed line into a chunk of words.
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
        if expr.resolvable(@symtab) then expr.evaluate(@symtab) else expr
      return new DataLine(pline, address, data)
    if pline.expanded?
      rv = new DataLine(pline, address, [])
      rv.expanded = pline.expanded.map (x) =>
        dataLine = @compileLine(x, address)
        address = dataLine.address + dataLine.data.length
        dataLine
      return rv
    if not pline.op? then return new DataLine(pline, address, [])

    @optimize(pline)

    data = [ 0 ]
    operandCodes = []
    if pline.operands.length > 0
      for i in [pline.operands.length - 1 .. 0]
        x = pline.operands[i]
        canCompact = (i == pline.operands.length - 1)
        # do any easy compactions.
        if canCompact and x.checkCompact(@symtab)
          @debug "  compacted ", x
          @shrunk = true
        [ code, immediate ] = x.pack(@symtab, canCompact)
        operandCodes.push(code)
        if immediate? then data.push(immediate)
    if Dcpu.BinaryOp[pline.op]?
      if pline.operands.length != 2
        pline.fail "#{pline.op.toUpperCase()} requires 2 parameters"
      data[0] = (operandCodes[0] << 10) | (operandCodes[1] << 5) | Dcpu.BinaryOp[pline.op]
    else if Dcpu.SpecialOp[pline.op]?
      if pline.operands.length != 1
        pline.fail "#{pline.op.toUpperCase()} requires 1 parameter"
      data[0] = (operandCodes[0] << 10) | (Dcpu.SpecialOp[pline.op] << 5)
    else
      pline.fail "Unknown instruction: #{pline.op}"
    new DataLine(pline, address, data)

  # ----- optimizations

  optimize: (pline) ->
    @optimizeAdd(pline)

  # add/sub by a small negative constant can be flipped
  optimizeAdd: (pline) ->
    if pline.op != "add" and pline.op != "sub" then return
    if pline.operands.length < 2 or not pline.operands[1].immediate? then return
    if pline.operands[1].immediate < 0xff00 then return
    pline.op = (if pline.op == "add" then "sub" else "add")
    pline.operands[1].immediate = 0x10000 - pline.operands[1].immediate
    @debug "  optimize/add: ", pline




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




  xcompileParsedLine: (line, org) ->
    @debug "  parsed line: ", line
    # ensure ./$ are set for macro expansions
    @symtab["."] = org
    @symtab["$"] = org
    if line.label? then @symtab[line.label] = org
    if line.data? then return { data: line.data, org: org }
    if line.expanded?
      info = { data: [], org: org }
      for x in line.expanded
        @debug "  expand macro: ", x
        if x.op? and x.op == "org"
          @fail line.pos, "Sorry, you can't use ORG in a macro."
        newinfo = @compileParsedLine(x, org)
        info.data = info.data.concat(newinfo.data)
        org += newinfo.data.length
        @debug "  finished macro expansion: ", newinfo
      return info
    if not line.op? then return { data: [], org: org }

    if line.op == "org"
      if line.operands.length != 1 then @fail line.pos, "ORG requires a single parameter"
      if not line.operands[0].expr.resolvable(@symtab)
        @fail line.operands[0].pos, "ORG must be a constant expression with no forward references"
      info = { org: line.operands[0].expr.evaluate(@symtab), data: [] }
      if line.label? then @symtab[line.label] = info.org
      return info
    if line.op == "equ"
      if line.operands.length != 1 then @fail line.pos, "EQU requires a single parameter"
      if not line.operands[0].expr.resolvable(@symtab)
        @fail line.operands[0].pos, "EQU must be a constant expression with no forward references"
      if not line.label? then @fail line.pos, "EQU requires a label"
      @symtab[line.label] = line.operands[0].expr.evaluate(@symtab)
      return { org: org, data: [] }

    # convenient aliases
    if line.op == "jmp"
      if line.operands.length != 1 then @fail line.pos, "JMP requires a single parameter"
      line.op = "set"
      @setText("pc")
      line.operands.unshift(@parseOperand(true))
      return @compileParsedLine(line, org)
    if line.op == "hlt"
      if line.operands.length != 0 then @fail line.pos, "HLT has no parameters"
      return @compileLine("sub pc, 1", org)
    if line.op == "ret"
      if line.operands.length != 0 then @fail line.pos, "RET has no parameters"
      return @compileLine("set pc, pop", org)
    if line.op == "bra"
      if line.operands.length != 1 then @fail line.pos, "BRA requires a single parameter"
      if line.operands[0].code != 0x1f then @fail line.operands[0].loc, "BRA takes only an immediate value"
      # we'll compute the branch on the 2nd pass.
      return { data: [ line.operands[0] ], org: org, branchFrom: org + 1 }

    info = { data: [ 0 ], org: org }
    if line.operands.length > 0
      for i in [line.operands.length - 1 .. 0]
        x = line.operands[i]
        @resolveOperand(x, i == line.operands.length - 1)
        if x.expr? then info.data.push(x.expr)
        if x.immediate? then info.data.push(x.immediate)
    if Dcpu.BinaryOp[line.op]?
      if line.operands.length != 2 then @fail line.pos, line.op.toUpperCase() + " requires 2 parameters"
      info.data[0] = (line.operands[1].code << 10) | (line.operands[0].code << 5) | Dcpu.BinaryOp[line.op]
    else if Dcpu.SpecialOp[line.op]?
      if line.operands.length != 1 then @fail line.pos, line.op.toUpperCase() + " requires 1 parameter"
      info.data[0] = (line.operands[0].code << 10) | (Dcpu.SpecialOp[line.op] << 5)
    else
      @fail line.pos, "Unknown instruction: " + line.op
    info

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
