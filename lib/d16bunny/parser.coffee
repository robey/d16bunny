
util = require 'util'

class ParseException
  constructor: (@message) ->
  toString: -> @message

# an expression tree.
class Expression
  Register: (loc, r) ->
    e = new Expression(loc)
    e.register = r
    e

  Literal: (loc, n) ->
    e = new Expression(loc)
    e.literal = n
    e

  Label: (loc, x) ->
    e = new Expression(loc)
    e.label = x
    e

  Unary: (loc, op, r) ->
    e = new Expression(loc)
    e.unary = op
    e.right = r
    e

  Binary: (loc, op, l, r) ->
    e = new Expression(loc)
    e.binary = op
    e.left = l
    e.right = r
    e

  constructor: (@loc) ->

  # for debugging.
  toString: ->
    return @literal.toString() if @literal
    return @label if @label
    return Parser::RegisterNames[@register] if @register
    return "(" + @unary + @right.toString() + ")" if @unary
    return "(" + @left.toString() + " " + @binary + " " + @right.toString() + ")" if @binary
    "ERROR"

# parse bits of a line of assembly.
class Parser
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

  @OperandRegex = /^[A-Za-z_.0-9]+/
  @NumberRegex = /^[0-9]+$/
  @HexRegex = /^0x[0-9a-fA-F]+$/
  BinaryRegex: /^0b[01]+$/
  LabelRegex: /^[a-zA-Z_.][a-zA-Z_.0-9]*$/

  Registers: { "a": 0, "b": 1, "c": 2, "x": 3, "y": 4, "z": 5, "i": 6, "j": 7 }
  RegisterNames: "ABCXYZIJ"

  # logger will be used to report errors: logger(pos, message, fatal?)
  # if not fatal, it's just a warning.
  constructor: (@logger) ->
    # some state is kept by the parser during parsing of each line:
    @text = ""  # text currently being parsed
    @pos = 0    # current index within text
    @end = 0    # parsing should not continue past end
    # when evaluating macros, this holds the current parameters:
    @vars = {}

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
      register = Parser::Registers[@text[@pos].toLowerCase()]
      if not register?
        throw new ParseException("Expected register name")
      @pos++
      x = Expression::Register(loc, register)
      console.log("x = " + util.inspect(x))
      x
    else
      operand = Parser.OperandRegex.exec(@text.slice(@pos, @end))
      if not operand?
        throw new ParseException("Expected operand value")
      operand = operand[0].toLowerCase()
      @pos += operand.length
      operand = @vars[operand].toLowerCase() if @vars[operand]?
      if Parser.NumberRegex.exec(operand)?
        Expression::Literal(loc, parseInt(operand, 10))
      else if Parser.HexRegex.exec(operand)?
        Expression::Literal(loc, parseInt(operand, 16))
      else if Parser::BinaryRegex.exec(operand)?
        Expression::Literal(loc, parseInt(operand.slice(2), 2))
      else if Parser::Registers[operand]?
        Expression::Register(loc, Parser::Registers[operand])
      else if Parser::LabelRegex.exec(operand)?
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
      if not Parser::Binary[op]
        op += @text[@pos + 1]
      if not (newPrecedence = Parser::Binary[op])?
        throw new ParseException("Unknown operator (try: + - * / %)")
      return left if newPrecedence <= precedence
      loc = @pos
      @pos += op.length
      right = @parseExpression(newPrecedence)
      left = Expression::Binary(loc, op, left, right)


exports.Parser = Parser
exports.ParseException = ParseException
