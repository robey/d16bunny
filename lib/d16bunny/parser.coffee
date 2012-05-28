
util = require 'util'

Dcpu = require('./dcpu').Dcpu

class ParseException
  constructor: (@message) ->
  toString: -> @message

# thrown when evaluating an expression that refers to a symbol that hasn't been defined (yet?)
class UnresolvableException
  constructor: (@message) ->
  toString: -> @message

# an expression tree.
class Expression
  Register: (loc, r) ->
    e = new Expression(loc)
    e.register = r
    e.evaluate = (symtab) ->
      throw new ParseException("Constant expressions may not contain register references")
    e

  Literal: (loc, n) ->
    e = new Expression(loc)
    e.literal = n
    e.evaluate = (symtab) -> @literal
    e

  Label: (loc, x) ->
    e = new Expression(loc)
    e.label = x
    e.evaluate = (symtab) ->
      if Dcpu.Reserved[@label]
        throw new ParseException("You can't use " + @label.toUpperCase() + " in expressions.")
      if not symtab[@label]
        throw new UnresolvableException("Can't resolve reference to " + @label)
      symtab[@label]
    e

  Unary: (loc, op, r) ->
    e = new Expression(loc)
    e.unary = op
    e.right = r
    e.evaluate = (symtab) ->
      r = @right.evaluate(symtab)
      switch @unary
        when '-' then -r
        else r
    e

  Binary: (loc, op, l, r) ->
    e = new Expression(loc)
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
        else throw "Internal error (undefined binary operator)"
    e

  constructor: (@loc) ->

  # for debugging.
  toString: ->
    return @literal.toString() if @literal
    return @label if @label
    return Dcpu.RegisterNames[@register] if @register
    return "(" + @unary + @right.toString() + ")" if @unary
    return "(" + @left.toString() + " " + @binary + " " + @right.toString() + ")" if @binary
    "ERROR"

  # Given a symbol table of names and values, resolve this expression tree
  # into a single number. Any register reference, or reference to a symbol
  # that isn't defined in 'symtab' will be an error.
  evaluate: (symtab) ->
    throw "must be implemented in objects"

#    if (value < 0 || value > 0xffff) {
#      logger(pos, "(Warning) Literal value " + value.toString(16) + " will be truncated to " + (value & 0xffff).toString(16));
#     value = value & 0xffff;

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

  # useful for unit tests
  setText: (text) ->
    @text = text
    @pos = 0
    @end = text.length

  troubleSpot: (pos = @pos) ->
    spacer = if pos == 0 then "" else (" " for i in [1..pos]).join("")
    [ @text, spacer + "^" ]

  logTroubleSpot: (pos = @pos) ->
    console.log("")
    console.log(x) for x in @troubleSpot()

  skipWhitespace: ->
    c = @text[@pos]
    while @pos < @end and (c == " " or c == "\t" or c == "\r" or c == "\n")
      c = @text[++@pos]
    if c == ';'
      # truncate line at comment
      @end = @pos

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
    throw new ParseException("Value expected (operand or expression)") if @pos == @end

    loc = @pos
    if @text[@pos] == "("
      @pos++
      atom = @parseExpression(0)
      @skipWhitespace()
      if @pos == @end or @text[@pos] != ")"
        throw new ParseException("Missing ) on expression")
      @pos++
      atom
    else if @text[@pos] == "'"
      # literal char
      [ ch, @pos ] = @unquoteChar(@text, @pos + 1, @end)
      if @pos == @end or @text[@pos] != "'"
        @logTroubleSpot()
        throw new ParseException("Expected ' to close literal char")
      @pos++
      Expression::Literal(loc, ch.charCodeAt(0))
    else if @text[@pos] == "%"
      # allow unix-style %A for register names
      @pos++
      register = Dcpu.Registers[@text[@pos].toLowerCase()]
      if not register?
        throw new ParseException("Expected register name")
      @pos++
      Expression::Register(loc, register)
    else
      operand = Assembler::OperandRegex.exec(@text.slice(@pos, @end))
      if not operand?
        throw new ParseException("Expected operand value")
      operand = operand[0].toLowerCase()
      @pos += operand.length
      operand = @vars[operand].toLowerCase() if @vars[operand]?
      if Assembler::NumberRegex.exec(operand)?
        Expression::Literal(loc, parseInt(operand, 10))
      else if Assembler::HexRegex.exec(operand)?
        Expression::Literal(loc, parseInt(operand, 16))
      else if Assembler::BinaryRegex.exec(operand)?
        Expression::Literal(loc, parseInt(operand.slice(2), 2))
      else if Dcpu.Registers[operand]?
        Expression::Register(loc, Dcpu.Registers[operand])
      else if Assembler::LabelRegex.exec(operand)?
        Expression::Label(loc, operand)

  parseUnary: ->
    if @pos < @end and (@text[@pos] == "-" or @text[@pos] == "+")
      loc = @pos
      op = @text[@pos++]
      expr = @parseAtom()
      Expression::Unary(loc, op, expr)
    else
      @parseAtom()

  parseExpression: (precedence) ->
    @skipWhitespace()
    throw new ParseException("Expression expected") if @pos == @end
    left = @parseUnary()
    loop
      @skipWhitespace()
      return left if @pos == @end or @text[@pos] == ")"
      op = @text[@pos]
      if not Assembler::Binary[op]
        op += @text[@pos + 1]
      if not (newPrecedence = Assembler::Binary[op])?
        throw new ParseException("Unknown operator (try: + - * / %)")
      return left if newPrecedence <= precedence
      loc = @pos
      @pos += op.length
      right = @parseExpression(newPrecedence)
      left = Expression::Binary(loc, op, left, right)

  parseMacroDirective: ->
    m = Assembler::SymbolRegex.exec(@text.slice(@pos))
    if not m?
      throw new ParseException("Macro name must contain only letters, digits, _ or .")
    name = m[0].toLowerCase()
    @pos += name.length
    @skipWhitespace()
    if Dcpu.Reserved[name] or Dcpu.ReservedOp[name]
      throw new ParseException("Invalid name for macro: " + name)

    argNames = []
    if @pos < @end and @text[pos] == '('
      @pos++
      @skipWhitespace()
      while @pos < @end and @text[pos] != ')'
        break if @text[pos] == ')'
        m = Assembler::SymbolRegex.exec(@text.slice(@pos))
        if not m?
          throw new ParseException("Expected macro parameter name")
        argName = m[0].toLowerCase()
        argNames.push(argName)
        @pos += argName.length
        @skipWhitespace()
        if @text[pos] != ')' and @text[@pos] != ','
          throw new ParseException("Expected , or )")
      if @pos == @end
        throw new ParseException("Expected )")
      @pos++
    @skipWhitespace()
    if @pos < @end or @text[pos] != '{'
      throw new ParseException("Expected { to start macro definition")
    @inMacro = true

  parseDefineDirective: ->

  # a directive starts with "#".
  parseDirective: ->
    m = Assembler::SymbolRegex.exec(@text.slice(@pos))
    if not m?
      throw new ParseException("Expected directive name after #")
    directive = m[0].toLowerCase()
    @pos += directive.length
    @skipWhitespace()
    if directive == "macro"
      @parseMacroDirective()
    else if directive == "define"
      @parseDefineDirective()
    else
      throw new ParseException("Unknown directive: " + directive)

  # returns an object containing:
  #   - label (if any)
  #   - op (if any)
  #   - args (array)
  #   - argpos (array)
  parseLine: (text) ->
    @setText(text)
    @skipWhitespace()
    rv = { args: [], argpos: [] }
    if @pos == @end then return rv

    if @text[@pos] == '#'
      @pos++
      @parseDirective()
      return rv
    if @text[@pos] == ':'
      # label
      @pos++
      m = Assembler::SymbolRegex.exec(@text.slice(@pos))
      if not m?
        throw new ParseException("Label name must contain only letters, digits, _ or .")
      rv.label = m[0]
      @pos += rv.label.length
      @skipWhitespace()
    return rv if @pos == @end

    m = Assembler::SymbolRegex.exec @text.slice(@pos)
    if not m?
      throw new ParseException("Inscrutable opcode (expecting operation or macro call)")
    word = m[0].toLowerCase()
    if @vars[word] then word = @vars[word]
    @pos += word.length
    @skipWhitespace()
    rv.op = word

    # if this is a a macro call, the parameters (if any) will be surrounded by parens.
    if @macros[rv.op] and @pos < @end and @text[@pos] == '('
      @pos++
      @skipWhitespace()
    return rv if @pos == @end

    inString = false
    inChar = false
    argn = 0
    i = @pos
    while i < @end
      break if (@text[i] == ';' or @text[i] == ')') and not inString and not inChar
      if not rv.args[argn]?
        rv.args.push("")
        rv.argpos.push(i)
      if @text[i] == '\\' and i + 1 < @end
        rv.args[argn] += @text[i++]
        rv.args[argn] += @text[i++]
      else if (@text[i] == ',' or @text[i] == '=') and not inString and not inChar
        if @text[i] == '=' then rv.args[argn] += '='
        argn++
        i++
        while i < @end and (@text[i] == ' ' or @text[i] == '\t')
          i++
      else
        rv.args[argn] += @text[i]
        if @text[i] == '"' then inString = not inString
        if @text[i] == "\'" then inChar = not inChar
        i++
    if inString
      throw new ParseException("Expected closing \"")
    if inChar
      throw new ParseException("Expected closing \'")
    rv

#    if (text.charAt(pos) == "{") {
#        line.start_block = true;
#        pos++;
#      }
#      if (text.charAt(pos) == "}") {
#        line.end_block = true;
#        pos++;
#      }




exports.Assembler = Assembler
exports.ParseException = ParseException
exports.UnresolvableException = UnresolvableException
