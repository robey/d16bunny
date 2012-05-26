
util = require 'util'

class ParseException
  constructor: (@message) ->
  toString: -> @message

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
  @LabelRegex = /^[a-zA-Z_.][a-zA-Z_.0-9]*$/

  @Registers = { "a": 0, "b": 1, "c": 2, "x": 3, "y": 4, "z": 5, "i": 6, "j": 7 }
  @RegisterNames = "ABCXYZIJ"

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

  # parse a single atom and return one of: literal, register, label, ...
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
    else if @text[@pos] == "'"
      # literal char
      [ ch, @pos ] = @unquoteChar(@text, @pos, @end)
      if @pos == @end or @text[@pos] != "'"
        throw new ParseException("Expected ' to close literal char")
      @pos++
      { literal: @text[@pos + 1], loc: loc }
    else if @text[@pos] == "%"
      # allow unix-style %A for register names
      @pos++
      register = Parser.Registers[@text[@pos].toLowerCase()]
      if not register?
        throw new ParseException("Expected register name")
      @pos++
      { register: register, loc: loc }
    else
      operand = Parser.OperandRegex.exec(@text.slice(@pos, @end))
      if not operand?
        throw new ParseException("Expected operand value")
      operand = operand[0].toLowerCase()
      @pos += operand.length
      operand = @vars[operand].toLowerCase() if @vars[operand]?
      if Parser.NumberRegex.exec(operand)?
        { literal: parseInt(operand, 10), loc: loc }
      else if Parser.HexRegex.exec(operand)?
        { literal: parseInt(operand, 16), loc: loc }
      else if Parser::BinaryRegex.exec(operand)?
        { literal: parseInt(operand.slice(2), 2), loc: loc }
      else if Parser.Registers[operand]?
        { register: Parser.Registers[operand], loc: loc }
      else if Parser.LabelRegex.exec(operand)?
        { label: operand, loc: loc }

  parseUnary: ->
    if @pos < @end and (@text[@pos] == "-" or @text[@pos] == "+")
      loc = @pos
      op = @text[@pos++]
      expr = @parseAtom()
      { unary: op, right: expr, loc: loc }
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
      left = { binary: op, left: left, right: right, loc: loc }

  # turn an expression struct into a string, for debugging.
  expressionToString: (expr) ->
    return expr.literal.toString() if expr.literal?
    return expr.label if expr.label?
    return Parser.RegisterNames[expr.register] if expr.register?
    return "(" + expr.unary + @expressionToString(expr.right) + ")" if expr.unary?
    if expr.binary?
      "(" + @expressionToString(expr.left) + " " + expr.binary + " " +
        @expressionToString(expr.right) + ")"
    else
      "ERROR"

exports.Parser = Parser
exports.ParseException = ParseException
