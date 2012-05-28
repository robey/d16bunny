
util = require 'util'

Dcpu = require('./dcpu').Dcpu

class ParseException
  constructor: (@text, @pos, message) ->
    @message = @format(message)

  format: (message) -> 
    spacer = if @pos == 0 then "" else (" " for i in [1 .. @pos]).join("")
    "\n" + @text + "\n" + spacer + "^\n" + message + "\n"

# an expression tree.
class Expression
  Register: (text, pos, r) ->
    e = new Expression(text, pos)
    e.register = r
    e.evaluate = (symtab) ->
      throw new ParseException(@text, @pos, "Constant expressions may not contain register references")
    e.toString = -> Dcpu.RegisterNames[@register] if @register
    e.resolvable = (symtab) -> true
    e

  Literal: (text, pos, n) ->
    e = new Expression(text, pos)
    e.literal = n
    e.evaluate = (symtab) -> @literal
    e.toString = -> @literal.toString()
    e.resolvable = (symtab) -> true
    e

  Label: (text, pos, x) ->
    e = new Expression(text, pos)
    e.label = x
    e.evaluate = (symtab) ->
      if Dcpu.Reserved[@label]
        throw new ParseException(@text, @pos, "You can't use " + @label.toUpperCase() + " in expressions.")
      if not symtab[@label]
        throw new ParseException(@text, @pos, "Can't resolve reference to " + @label)
      symtab[@label]
    e.toString = -> @label
    e.resolvable = (symtab) -> symtab[@label]?
    e

  Unary: (text, pos, op, r) ->
    e = new Expression(text, pos)
    e.unary = op
    e.right = r
    e.evaluate = (symtab) ->
      r = @right.evaluate(symtab)
      switch @unary
        when '-' then -r
        else r
    e.toString = -> "(" + @unary + @right.toString() + ")"
    e.resolvable = (symtab) -> @right.resolvable(symtab)
    e

  Binary: (text, pos, op, l, r) ->
    e = new Expression(text, pos)
    e.binary = op
    e.left = l
    e.right = r
    e.evaluate = (symtab) ->
      l = @left.evaluate(symtab)
      r = @right.evaluate(symtab)
      switch @binary
        when '+' then l + r
        when '-' then l - r
        when '*' then l * r
        when '/' then l / r
        when '%' then l % r
        when '<<' then l << r
        when '>>' then l >> r
        when '&' then l & r
        when '^' then l ^ r
        when '|' then l | r
        else throw new ParseException(@text, @pos, "Internal error (undefined binary operator)")
    e.toString = -> "(" + @left.toString() + " " + @binary + " " + @right.toString() + ")"
    e.resolvable = (symtab) -> @left.resolvable(symtab) and @right.resolvable(symtab)
    e

  constructor: (@text, @pos) ->

  # for debugging.
  toString: -> throw "must be implemented in objects"

  # Given a symbol table of names and values, resolve this expression tree
  # into a single number. Any register reference, or reference to a symbol
  # that isn't defined in 'symtab' will be an error.
  evaluate: (symtab) -> throw "must be implemented in objects"

  # can this expression's references be resolved by the symtab (yet)?
  resolvable: (symtab) -> throw "must be implemented in objects"


# compile lines of DCPU assembly.
class Assembler
  # precedence of supported binary operators in expressions
  Binary:
    '*': 10
    '/': 10
    '%': 10
    '+': 9
    '-': 9
    '<<' : 8
    '>>' : 8
    '&' : 7
    '^' : 6
    '|' : 5

  OperandRegex: /^[A-Za-z_.0-9]+/
  NumberRegex: /^[0-9]+$/
  HexRegex: /^0x[0-9a-fA-F]+$/
  BinaryRegex: /^0b[01]+$/
  LabelRegex: /^[a-zA-Z_.][a-zA-Z_.0-9]*$/
  SymbolRegex: /^[a-zA-Z_.][a-zA-Z_.0-9]*/

  # logger will be used to report errors: logger(pos, message, fatal?)
  # if not fatal, it's just a warning.
  constructor: (@logger) ->
    # some state is kept by the parser during parsing of each line:
    @text = ""         # text currently being parsed
    @pos = 0           # current index within text
    @end = 0           # parsing should not continue past end
    @inMacro = false   # waiting for an "}"
    # when evaluating macros, this holds the current parameters:
    @vars = {}
    # macros that have been defined:
    @macros = {}
    # current symbol table:
    @symtab = {}

  debug: (list...) ->
    unless @debugger? then return
    slist = for item in list
      switch typeof item
        when 'string' then item.toString()
        else require('./smoosher.coffee').smoosh.smoosh(item)
    @debugger(slist.join(""))

  # useful for unit tests
  setText: (text) ->
    @text = text
    @pos = 0
    @end = text.length

  fail: (loc, message) ->
    throw new ParseException(@text, loc, message)

  skipWhitespace: ->
    c = @text[@pos]
    while @pos < @end and (c == " " or c == "\t" or c == "\r" or c == "\n")
      c = @text[++@pos]
    if c == ';'
      # truncate line at comment
      @end = @pos

  parseWord: (name) ->
    loc = @pos
    m = Assembler::SymbolRegex.exec(@text.slice(@pos))
    if not m? then @fail loc, name + " must contain only letters, digits, _ or ."
    word = m[0].toLowerCase()
    @pos += word.length
    if Dcpu.Reserved[word] or Dcpu.ReservedOp[word]
      @fail loc, "Reserved keyword: " + word
    word

  unquoteChar: (text, pos, end) ->
    rv = if text[pos] == '\\' and pos + 1 < end
      switch text[++pos]
        when 'n' then "\n"
        when 'r' then "\r"
        when 't' then "\t"
        when 'z' then "\u0000"
        when 'x'
          if pos + 2 < end
            pos += 2
            String.fromCharCode(parseInt(text.slice(pos - 1, pos + 1), 16))
          else
            "\\x"
        else "\\" + text[pos]
    else
      text[pos]
    [ rv, pos + 1 ]

  # parse a single atom and return an expression.
  parseAtom: ->
    @skipWhitespace()
    if @pos == @end then @fail @pos, "Value expected (operand or expression)"

    loc = @pos
    if @text[@pos] == "("
      @pos++
      atom = @parseExpression(0)
      @skipWhitespace()
      if @pos == @end or @text[@pos] != ")" then @fail @pos, "Missing ) on expression"
      @pos++
      atom
    else if @text[@pos] == "'"
      # literal char
      [ ch, @pos ] = @unquoteChar(@text, @pos + 1, @end)
      if @pos == @end or @text[@pos] != "'"
        @fail @pos, "Expected ' to close literal char"
      @pos++
      Expression::Literal(@text, loc, ch.charCodeAt(0))
    else if @text[@pos] == "%"
      # allow unix-style %A for register names
      @pos++
      register = Dcpu.Registers[@text[@pos].toLowerCase()]
      if not register? then @fail @pos, "Expected register name"
      @pos++
      Expression::Register(@text, loc, register)
    else
      operand = Assembler::OperandRegex.exec(@text.slice(@pos, @end))
      if not operand? then @fail @pos, "Expected operand value"
      operand = operand[0].toLowerCase()
      @pos += operand.length
      operand = @vars[operand].toLowerCase() if @vars[operand]?
      if Assembler::NumberRegex.exec(operand)?
        Expression::Literal(@text, loc, parseInt(operand, 10))
      else if Assembler::HexRegex.exec(operand)?
        Expression::Literal(@text, loc, parseInt(operand, 16))
      else if Assembler::BinaryRegex.exec(operand)?
        Expression::Literal(@text, loc, parseInt(operand.slice(2), 2))
      else if Dcpu.Registers[operand]?
        Expression::Register(@text, loc, Dcpu.Registers[operand])
      else if Assembler::LabelRegex.exec(operand)?
        Expression::Label(@text, loc, operand)

  parseUnary: ->
    if @pos < @end and (@text[@pos] == "-" or @text[@pos] == "+")
      loc = @pos
      op = @text[@pos++]
      expr = @parseAtom()
      Expression::Unary(@text, loc, op, expr)
    else
      @parseAtom()

  parseExpression: (precedence) ->
    @skipWhitespace()
    if @pos == @end then @fail @pos, "Expression expected"
    left = @parseUnary()
    loop
      @skipWhitespace()
      return left if @pos == @end or @text[@pos] == ')' or @text[@pos] == ',' or @text[@pos] == ']'
      op = @text[@pos]
      if not Assembler::Binary[op]
        op += @text[@pos + 1]
      if not (newPrecedence = Assembler::Binary[op])?
        @fail @pos, "Unknown operator (try: + - * / % << >> & ^ |)"
      return left if newPrecedence <= precedence
      loc = @pos
      @pos += op.length
      right = @parseExpression(newPrecedence)
      left = Expression::Binary(@text, loc, op, left, right)

  parseString: ->
    rv = ""
    @pos++
    while @pos < @end and @text[@pos] != '"'
      [ ch, @pos ] = @unquoteChar(@text, @pos, @end)
      rv += ch
    if @pos == @end then @fail @pos, "Expected \" to close string"
    @pos++
    rv

  # parse an operand expression into:
  #   - loc: where we found it
  #   - code: 5-bit value for the operand in an opcode
  #   - expr: (optional) an expression to be evaluated for the immediate
  # if 'destination' is set, then the operand is in the destination slot (which determines whether
  #   it uses "push" or "pop").
  parseOperand: (destination) ->
    loc = @pos
    inPointer = false
    inPick = false

    if @text[@pos] == '['
      @pos++
      inPointer = true
    else if @pos + 4 < @end and @text.substr(@pos, 4).toLowerCase() == "pick"
      @pos += 4
      inPick = true

    expr = @parseExpression(0)
    if inPointer
      if @pos == @end or @text[@pos] != ']' then @fail loc, "Expected ]"
      @pos++
    if inPick
      return { loc: loc, code: 0x1a, expr: expr }
    if expr.register?
      return { loc: loc, code: (if inPointer then 0x08 else 0x00) + expr.register }
    if expr.label? and Dcpu.Specials[expr.label]
      if inPointer then @fail loc, "You can't use a pointer to " + expr.label.toUpperCase()
      if (destination and expr.label == "pop") or ((not destination) and expr.label == "push")
        @fail loc, "You can't use " + expr.label.toUpperCase() + " in this position"
      return { loc: loc, code: Dcpu.Specials[expr.label] }

    # special case: [literal + register]
    if inPointer and expr.binary? and (expr.left.register? or expr.right.register?)
      if expr.binary != '+' then @fail loc, "Only a value + register is allowed"
      register = if expr.left.register? then expr.left.register else expr.right.register
      expr = if expr.left.register? then expr.right else expr.left
      return { loc: loc, code: 0x10 + register, expr: expr }

    { loc: loc, code: (if inPointer then 0x1e else 0x1f), expr: expr, destination: destination }

  # attempt to resolve the expression in this operand. returns true on success, and sets:
  #   - immediate: (optional) immediate value for this operand
  resolveOperand: (operand) ->
    if not operand.expr? then return true
    if not operand.expr.resolvable(@symtab) then return false
    value = operand.expr.evaluate(@symtab) & 0xffff
    if operand.code == 0x1f and (value == 0xffff or value < 31) and not operand.destination
      operand.code = 0x20 + (if value == 0xffff then 0x00 else (0x01 + value))
    else
      operand.immediate = value
    delete operand.expr
    true

  parseMacroDirective: ->
    loc = @pos
    name = @parseWord("Macro name")
    @skipWhitespace()
    argNames = []
    if @pos < @end and @text[@pos] == '('
      @pos++
      @skipWhitespace()
      while @pos < @end and @text[@pos] != ')'
        break if @text[@pos] == ')'
        argNames.push(@parseWord("Parameter name"))
        @skipWhitespace()
        if @pos < @end and @text[@pos] == ','
          @pos++
          @skipWhitespace()
      if @pos == @end then @fail @pos, "Expected )"
      @pos++
    @skipWhitespace()
    if @pos == @end or @text[@pos] != '{'
      @fail @pos, "Expected { to start macro definition"
    fullname = name + "(" + argNames.length + ")"
    if @macros[fullname]? then @fail loc, "Duplicate definition of " + fullname
    @macros[fullname] = { name: fullname, lines: [], params: argNames }
    if not @macros[name]? then @macros[name] = []
    @macros[name].push(argNames.length)
    @inMacro = fullname

  parseDefineDirective: ->
    name = @parseWord("Definition name")
    @skipWhitespace()
    value = @parseExpression(0).evaluate()
    @symtab[name] = value

  # a directive starts with "#".
  parseDirective: ->
    loc = @pos
    directive = @parseWord("Directive")
    @skipWhitespace()
    switch directive
      when "macro" then @parseMacroDirective()
      when "define" then @parseDefineDirective()
      else @fail loc, "Unknown directive: " + directive

  parseMacroArgs: ->
    inString = false
    inChar = false
    args = []
    argn = 0
    while @pos < @end
      break if (@text[@pos] == ';' or @text[@pos] == ')') and not inString and not inChar
      if not args[argn]? then args.push("")
      if @text[@pos] == '\\' and @pos + 1 < @end
        args[argn] += @text[@pos++]
        args[argn] += @text[@pos++]
      else if @text[@pos] == ',' and not inString and not inChar
        argn++
        @pos++
        @skipWhitespace()
      else
        args[argn] += @text[@pos]
        if @text[@pos] == '"' then inString = not inString
        if @text[@pos] == "\'" then inChar = not inChar
        @pos++
    if inString then @fail @pos, "Expected closing \""
    if inChar then @fail @pos, "Expected closing \'"
    args

  # expand a macro call, recursively parsing the nested lines
  parseMacroCall: (line) ->
    if @pos < @end and @text[@pos] == '('
      @pos++
      @skipWhitespace()
    args = @parseMacroArgs()
    name = line.op
    delete line.op
    if @macros[name].indexOf(args.length) < 0
      @fail 0, "Macro '" + name + "' requires " + @macros[name].join(" or ") + " arguments"
    macro = @macros[name + "(" + args.length + ")"]

    old_vars = @vars
    @vars = {}
    for k, v of old_vars
      @vars[k] = v
    for i in [0 .. args.length - 1]
      @vars[macro.params[i]] = args[i]
    @debug "  new vars: ", @vars
    line.expanded = (@parseLine(x) for x in macro.lines)
    @vars = old_vars
    line

  # read a list of data objects, which could each be an expression or a string.
  parseData: (line) ->
    data = []
    while @pos < @end
      if @text[@pos] == '"'
        s = @parseString()
        data.push(s.charCodeAt(i)) for i in [0 .. s.length - 1]
      else if @pos + 1 < @end and @text[@pos] == 'p' and @text[@pos + 1] == '"'
        # packed string
        @pos++
        s = @parseString()
        word = 0
        inWord = false
        for i in [0 .. s.length - 1]
          ch = s.charCodeAt(i)
          if inWord then data.push(word | ch) else (word = ch << 8)
          inWord = not inWord
        if inWord then data.push(word)
      else
        expr = @parseExpression(0)
        data.push(if expr.resolvable(@symtab) then expr.evaluate(@symtab) else expr)
      if @pos < @end and @text[@pos] == ','
        @pos++
        @skipWhitespace()
    line.data = data
    line

  # returns an object containing:
  #   - label (if any)
  #   - op (if any)
  #   - operands (array of expressions, if present)
  #   - data (array of expressions, if this is a data line)
  #   - expanded (a sub-list of line objects, if a macro was expanded)
  parseLine: (text) ->
    @setText(text)
    @skipWhitespace()
    line = {}
    if @pos == @end then return line

    if @inMacro
      if @text[@pos] == '}'
        @inMacro = false
      else
        @macros[@inMacro].lines.push(text)
      return line
    if @text[@pos] == '#'
      @pos++
      @parseDirective()
      return line
    if @text[@pos] == ':'
      @pos++
      line.label = @parseWord("Label")
      @skipWhitespace()
    return line if @pos == @end

    line.pos = @pos
    line.op = @parseWord("Operation name")
    if @vars[line.op] then line.op = @vars[line.op]
    @skipWhitespace()

    if @text[@pos] == '='
      # special case "name = value"
      name = line.op
      delete line.op
      @pos++
      @skipWhitespace()
      value = @parseExpression(0).evaluate()
      @symtab[name] = value
      return line

    if @macros[line.op] then return @parseMacroCall(line)
    if line.op == "dat" then return @parseData(line)

    # any other operation is assumed to take actual operands
    line.operands = []
    while @pos < @end
      line.operands.push(@parseOperand(line.operands.length == 0))
      if @pos < @end and @text[@pos] == ','
        @pos++
        @skipWhitespace()
    line

  # compile a line of code at a given address.
  # fields that can't be resolved yet will be left as expression trees, but the data size will be
  # computed.
  # returns an object with:
  #   - data: compiled output, made up either of words or unresolved expression trees
  #   - org: (optional) if the origin was changed
  #   - branchFrom: (optional) if this is a relative-branch instruction
  compileLine: (text, org) ->
    @debug "+ compile line @ ", org, ": ", text
    @compileParsedLine(@parseLine(text), org)

  compileParsedLine: (line, org) ->
    @debug "  parsed line: ", line
    if line.label? then @symtab[line.label] = org
    if line.data? then return { data: line.data }
    if line.expanded?
      info = { data: [] }
      for x in line.expanded
        @debug "  expand macro: ", x
        newinfo = @compileParsedLine(x, org)
        info.data = info.data.concat(newinfo.data)
        if info.org? then org = info.org else org += newinfo.data.size
        @debug "  finished macro expansion: ", newinfo
      return info
    if not line.op? then return { data: [] }

    if line.op == "org"
      if line.operands.length != 1 then @fail line.pos, "ORG requires a single parameter"
      if not line.operands[0].resolvable(@symtab)
        @fail line.operands[0].pos, "ORG must be a constant expression with no forward references"
      info = { org: line.operands[0].evaluate(@symtab) }
      if line.label? then @symtab[line.label] = info.org
      return info

    # convenient aliases
    if line.op == "jmp"
      if line.operands.length != 1 then @fail line.pos, "JMP requires a single parameter"
      line.op = "set"
      @setText("pc")
      line.operands.unshift(@parseOperand(true))
      return @compileParsedLine(line)
    if line.op == "brk"
      if line.operands.length != 0 then @fail line.pos, "BRK has no parameters"
      return @compileLine("sub pc, 1", org)
    if line.op == "ret"
      if line.operands.length != 0 then @fail line.pos, "RET has no parameters"
      return @compileLine("set pc, pop", org)
    if line.op == "bra"
      # we'll compute the branch on the 2nd pass.
      return { data: [ 0 ], branchFrom: org + 1 }

    info = { data: [ 0 ] }
    for i in [line.operands.length - 1 .. 0]
      x = line.operands[i]
      @resolveOperand(x)
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


exports.Assembler = Assembler
exports.ParseException = ParseException
