
Dcpu = require("./dcpu").Dcpu
Expression = require('./expression').Expression
Parser = require('./parser').Parser
AssemblerError = require('./errors').AssemblerError
AssemblerOutput = require('./output').AssemblerOutput
prettyPrinter = require('./prettyprint').prettyPrinter

# line compiled into data at an address.
# data is an array of 16-bit words.
# in mid-compilation, some items in 'data' may be unresolved equations.
# 'expanded' may contain an array of DataLine objects expanded from a macro.
class DataLine
  constructor: (@address = 0, @data = []) ->
    @expanded = null

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
    parser = new Parser(@logger)
    parser.debugger = @debugger
    for text, i in textLines
      3

  # # ensure ./$ are set for macro expansions
  # symtab["."] = org
  # symtab["$"] = org

  # attempt to turn a parsed line into a chunk of words.
  compileParsedLine: (line, address, symtab) ->
    @debug "  compiling: #{line}"
    if line.label? then symtab[line.label] = address
    if line.data? then return new DataLine(address, line.data)
    if line.directive?
      switch line.directive
        when "org" then return new DataLine(line.data[0], [])
        when "define" then symtab[line.name] = line.data[0]
      return null
    if line.expanded?
      rv = new DataLine(address, [])
      rv.expanded = line.expanded.map (xline) =>
        dataLine = @compileParsedLine(xline, address, symtab)
        address = dataLine.address + dataLine.data.length
        dataLine
      return rv
    if not line.op? then @error(line.lineNumber, 0, "Internal error: what is this line?")

    # convenient aliases
    if line.op == "jmp"
      if line.operands.length != 1 then @error(line.lineNumber, line.opPos, "JMP requires a single parameter")
      line.op = "set"
      line.operands.unshift(new Operand(line.opPos, Dcpu.Specials["pc"]))

    # if line.op == "hlt"
    #   if line.operands.length != 0 then @fail line.pos, "HLT has no parameters"
    #   return @compileLine("sub pc, 1", org)
    # if line.op == "ret"
    #   if line.operands.length != 0 then @fail line.pos, "RET has no parameters"
    #   return @compileLine("set pc, pop", org)
    # if line.op == "bra"
    #   if line.operands.length != 1 then @fail line.pos, "BRA requires a single parameter"
    #   if line.operands[0].code != 0x1f then @fail line.operands[0].loc, "BRA takes only an immediate value"
    #   # we'll compute the branch on the 2nd pass.
    #   return { data: [ line.operands[0] ], org: org, branchFrom: org + 1 }

    data = [ 0 ]
    if line.operands.length > 0
      for i in [line.operands.length - 1 .. 0]
        x = line.operands[i]
        if x.expr? then data.push(x.expr)
        if x.immediate? then data.push(x.immediate)
    if Dcpu.BinaryOp[line.op]?
      if line.operands.length != 2
        @error(line.lineNumber, line.opPos, "#{line.op.toUpperCase()} requires 2 parameters")
      data[0] = (line.operands[1].code << 10) | (line.operands[0].code << 5) | Dcpu.BinaryOp[line.op]
    else if Dcpu.SpecialOp[line.op]?
      if line.operands.length != 1
        @error(line.lineNumber, line.opPos, "#{line.op.toUpperCase()} requires 1 parameter")
      data[0] = (line.operands[0].code << 10) | (Dcpu.SpecialOp[line.op] << 5)
    else
      @error(line.lineNumber, line.opPos, "Unknown instruction: #{line.op}")
    new DataLine(address, data)




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



  # compile a line of code at a given address.
  # fields that can't be resolved yet will be left as expression trees, but the data size will be
  # computed.
  # returns an object with:
  #   - data: compiled output, made up either of words or unresolved expression trees
  #   - org: the memory location (pc) where this data starts
  #   - branchFrom: (optional) if this is a relative-branch instruction
  compileLine: (text, org) ->
    @symtab["."] = org
    @symtab["$"] = org
    @debug "+ compile line @ ", org, ": ", text, " -- symtab: ", @symtab
    @compileParsedLine(@parseLine(text), org)

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
