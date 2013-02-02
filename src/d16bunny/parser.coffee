
Dcpu = require("./dcpu").Dcpu
Expression = require('./expression').Expression
AssemblerError = require('./errors').AssemblerError
prettyPrinter = require('./prettyprint').prettyPrinter

class Span
  Comment: "comment"
  Directive: "directive"
  Identifier: "identifier"
  Operator: "operator"
  String: "string"
  StringEscape: "string-escape"
  Register: "register"
  Number: "number"
  Instruction: "instruction"
  Label: "label"

  constructor: (@type, @start, @end) ->


class Line
  constructor: (@text) ->
    @pos = 0            # current index within text
    @end = @text.length # parsing should not continue past end
    # things parsed out:
    @label = null       # label (if any)
    @op = null          # operation (if any)
    @directive = null   # directive, if this is a directive instead.
    @name = null        # name (if a constant is being defined)
    @operands = []      # array of expressions
    @data = []          # array of expressions, if this is a line of raw data
    @expanded = null    # list of other Line objects, if this is an expanded macro
    @spans = []         # spans for syntax highlighting

  toString: ->
    [
      if @label? then ":#{@label} " else ""
      if @op? then @op.toUpperCase() else ""
      if @directive? then ".#{@directive}" else ""
      if @name? then " #{@name}" else ""
    ].join("") +
      @operands.map((x) => " " + x.toString()).join(",") +
      if @expanded? then ("{ " + @expanded.map((x) => x.toString()) + " }") else ""

  # useful for unit tests
  setText: (text) ->
    @text = text
    @pos = 0
    @end = text.length

  addSpan: (type, start, end) ->
    if @spans.length > 0 and @spans[@spans.length - 1].end == start and @spans[@spans.length - 1].type == type
      old = @spans.pop()
      @spans.push(new Span(type, old.start, end))
    else
      @spans.push(new Span(type, start, end))

  # from http://stackoverflow.com/questions/1219860/javascript-jquery-html-encoding
  htmlEscape: (s) ->
    String(s)
      .replace(/&/g, '&amp;')
      .replace(/"/g, '&quot;')
      .replace(/'/g, '&#39;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')

  toHtml: ->
    x = 0
    rv = ""
    for span in @spans
      if x < span.start then rv += @htmlEscape(@text[x ... span.start])
      rv += "<span class=\"syntax-#{span.type}\">#{@htmlEscape(@text[span.start ... span.end])}</span>"
      x = span.end
    if x < @text.length then rv += @htmlEscape(@text[x ...])
    rv

  fail: (message) ->
    throw new AssemblerError(@text, @pos, message)

  finished: -> @pos == @end

  setMark: -> @mark = @pos

  getMark: -> @mark

  rewind: (n = null) -> @pos = if n? then n else @mark

  scan: (s, type) ->
    len = s.length
    if @pos + len <= @end and @text[@pos ... @pos + len] == s
      @addSpan(type, @pos, @pos + len)
      @pos += len
      true
    else
      false

  scanAssert: (s, type) ->
    if not @scan(s, type) then @fail "Expected #{s}"

  scanAhead: (s) ->
    len = s.length
    @pos + len <= @end and @text[@pos ... @pos + len] == s

  match: (regex, type) ->
    m = regex.exec(@text[@pos...])
    if not m? then return null
    @addSpan(type, @pos, @pos + m[0].length)
    @pos += m[0].length
    m[0]

  matchAhead: (regex) ->
    regex.exec(@text[@pos...])?

  skipWhitespace: ->
    c = @text[@pos]
    while @pos < @end and (c == " " or c == "\t" or c == "\r" or c == "\n")
      c = @text[++@pos]
    if c == ';'
      # truncate line at comment
      @addSpan(Span::Comment, @pos, @end)
      @end = @pos

  parseChar: ->
    if @text[@pos] != "\\" or @pos + 1 == @end
      @addSpan(Span::String, @pos, @pos + 1)
      return @text[@pos++]
    start = @pos
    @pos += 2
    rv = switch @text[@pos - 1]
      when 'n' then "\n"
      when 'r' then "\r"
      when 't' then "\t"
      when 'z' then "\u0000"
      when 'x'
        if @pos + 1 < @end
          @pos += 2
          String.fromCharCode(parseInt(@text[@pos - 2 ... @pos], 16))
        else
          "\\x"
      else
        "\\" + @text[@pos - 1]
    @addSpan(Span::StringEscape, start, @pos)
    rv

  parseString: ->
    rv = ""
    if not @scan('"', Span::String) then @fail "Expected string"
    while not @finished() and @text[@pos] != '"'
      rv += @parseChar()
    @scanAssert('"', Span::String)
    rv

  parseWord: (name, type = Span::Identifier) ->
    word = @match(Parser::SymbolRegex, type)
    if not word? then @fail "#{name} must contain only letters, digits, _ or ."
    word = word.toLowerCase()
    if Dcpu.Reserved[word] or Dcpu.ReservedOp[word] then @fail "Reserved keyword: #{word}"
    word


class Operand
  # pos: where it is in the string
  # code: 5-bit value for the operand in an opcode
  # expr: (optional) an expression to be evaluated for the immediate
  constructor: (@pos, @code, @expr) ->

  toString: -> if @immediate then "<#{@code}, #{@immediate}>" else "<#{@code}>"

  dependency: (symtab={}) ->
    @expr?.dependency(symtab)

  # attempt to resolve the expression in this operand. returns true on
  # success, and sets:
  #   - immediate: (optional) immediate value for this operand
  resolve: (symtab) ->
    # FIXME move to caller
    #      @debug "  resolve operand: code=#{@code} expr=#{@expr.toString()}"
    if not @expr? then return true
    if @expr.dependency(symtab)? then return false
    @immediate = @expr.evaluate(symtab) & 0xffff
    delete @expr

  # fit the immediate into a the operand code, if possible.
  compact: ->
    if @code == 0x1f and (@immediate == 0xffff or @immediate < 31)
      @code = 0x20 + (if @immediate == 0xffff then 0x00 else (0x01 + @immediate))
    delete @immediate


class Macro
  constructor: (@name, @args) ->
    @lines = []


# parse lines of DCPU assembly into structured data.
class Parser
  DelimiterRegex: /^(\)|,|\])/
  UnaryRegex: /^(\+|\-)/

  NumberRegex: /^[0-9]+/
  HexRegex: /^0x[0-9a-fA-F]+/
  BinaryRegex: /^0b[01]+/
  LabelRegex: /^([a-zA-Z_.][a-zA-Z_.0-9]*|\$)/
  SymbolRegex: /^[a-zA-Z_.][a-zA-Z_.0-9]*/
  OperatorRegex: /^(\*|\/|%|\+|\-|<<|>>|\&|\^|\|)/

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

  constructor: ->
    @reset()

  reset: ->
    @macros = {}
    @inMacro = null    # if waiting for an "}"
    @lastLabel = null  # for resolving relative labels
    # when evaluating macros, this holds the current parameter set:
    @vars = {}

  debug: (list...) ->
    unless @debugger? then return
    slist = for item in list
      switch typeof item
        when 'string' then item.toString()
        else prettyPrinter.dump(item)
    @debugger(slist.join(""))

  # returns a Line object, with syntax parsed out
  parseLine: (text) ->
    line = new Line(text)
    line.skipWhitespace()
    if line.finished() then return line

    if @inMacro
      if line.scan("}", Span::Directive)
        @inMacro = false
      else
        @macros[@inMacro].lines.push(text)
      return line
    if line.scan("#", Span::Directive) or line.scan(".", Span::Directive)
      @parseDirective(line)
      return line

    if line.scan(":", Span::Label)
      line.label = line.parseWord("Label", Span::Label)
      if line.label[0] == "."
        if @lastLabel? then line.label = @lastLabel + line.label
      else
        @lastLabel = line.label
      line.skipWhitespace()
    return line if line.finished()

    opStart = line.pos
    line.op = line.parseWord("Operation name", Span::Instruction)
    if @vars[line.op] then line.op = @vars[line.op]
    line.skipWhitespace()

    if line.scan("=", Span::Operator)
      # special case "name = value"
      line.rewind(opStart)
      line.spans.pop()
      line.spans.pop()
      delete line.op
      line.directive = "define"
      line.name = line.parseWord("Constant name", Span::Identifier)
      line.skipWhitespace()
      line.scan("=", Span::Operator)
      line.skipWhitespace()
      line.operands.push @parseExpression(line)
      line.skipWhitespace()
      if not line.finished() then line.fail "Unexpected content after definition"
      return line

    # FIXME make sure macros can't have directives.

    # if @macros[line.op] then return @parseMacroCall(line)
    if line.op == "dat" then return @parseData(line)

    if line.op == "org"
      line.rewind(opStart)
      line.spans.pop()
      delete line.op
      line.scan("org", Span::Directive)
      line.directive = "org"
      @parseOrgDirective(line)
      return line

    # any other operation is assumed to take actual operands
    line.operands = []
    while not line.finished()
      line.operands.push(@parseOperand(line, line.operands.length == 0))
      line.skipWhitespace()
      if not line.finished() and line.scan(",", Span::Operator) then line.skipWhitespace()

    line

  # ----- expressions

  parseExpression: (line, precedence = 0) ->
    line.skipWhitespace()
    if line.finished() then line.fail "Expected expression"
    left = @parseUnary(line)
    loop
      line.skipWhitespace()
      return left if line.finished() or line.matchAhead(Parser::DelimiterRegex)
      line.setMark()
      op = line.match(Parser::OperatorRegex, Span::Operator)
      if not op? then line.fail "Unknown operator (try: + - * / % << >> & ^ |)"
      newPrecedence = Parser::Binary[op]
      if newPrecedence <= precedence
        line.rewind()
        line.spans.pop()
        return left
      start = line.getMark()
      right = @parseExpression(line, newPrecedence)
      left = Expression::Binary(line.text, start, op, left, right)

  parseUnary: (line) ->
    line.setMark()
    op = line.match(Parser::UnaryRegex, Span::Operator)
    if op?
      start = line.getMark()
      expr = @parseAtom(line)
      Expression::Unary(line.text, start, op, expr)
    else
      @parseAtom(line)

  # parse a single atom and return an expression.
  parseAtom: (line) ->
    line.skipWhitespace()
    if line.finished() then line.fail "Value expected (operand or expression)"
    line.setMark()
    if line.scan("(", Span::Operator)
      atom = @parseExpression(line)
      line.skipWhitespace()
      if line.finished() or (not line.scan(")", Span::Operator)) then line.fail "Missing ) on expression"
      return atom
    if line.scan("'", Span::String)
      # literal char
      ch = line.parseChar()
      line.scanAssert("'", Span::String)
      return Expression::Literal(line.text, line.getMark(), ch.charCodeAt(0))
    if line.scan("%", Span::Register)
      # allow unix-style %A for register names
      x = line.match(Dcpu.RegisterRegex, Span::Register)
      if not x? then line.fail "Expected register name"
      return Expression::Register(line.text, line.getMark(), x.toLowerCase())
    x = line.match(Parser::HexRegex, Span::Number)
    if x? then return Expression::Literal(line.text, line.getMark(), parseInt(x, 16))
    x = line.match(Parser::BinaryRegex, Span::Number)
    if x? then return Expression::Literal(line.text, line.getMark(), parseInt(x[2...], 2))
    x = line.match(Parser::NumberRegex, Span::Number)
    if x? then return Expression::Literal(line.text, line.getMark(), parseInt(x, 10))
    x = line.match(Dcpu.RegisterRegex, Span::Register)
    if x? then return Expression::Register(line.text, line.getMark(), x.toLowerCase())
    x = line.match(Parser::LabelRegex, Span::Identifier)
    if x?
      if x[0] == "." and @lastLabel? then x = @lastLabel + x
      return Expression::Label(line.text, line.getMark(), x)
    line.rewind()
    line.fail "Expected expression"

  # ----- operands

  # parse an operand expression.
  # if 'destination' is set, then the operand is in the destination slot
  # (which determines whether it uses "push" or "pop").
  parseOperand: (line, destination = false) ->
    @debug "  parse operand: dest=#{destination} pos=#{line.pos}"
    start = line.pos
    dereference = false
    inPick = false

    if line.scan("[", Span::Operator)
      dereference = true
    else if line.scan("pick", Span::Register)
      inPick = true

    expr = @parseExpression(line)
    @debug "  parse operand: expr=#{expr}"
    if dereference then line.scanAssert("]", Span::Operator)
    if inPick then return new Operand(start, 0x1a, expr)
    if expr.register? 
      if Dcpu.Specials[expr.register]?
        if dereference
          line.rewind(start)
          line.fail "You can't dereference #{expr.toString()}"
        if (destination and expr.register == "pop") or ((not destination) and expr.register == "push")
          line.rewind(start)
          line.fail "You can't use #{expr.toString()} in this position"
        return new Operand(start, Dcpu.Specials[expr.register])
      return new Operand(start, (if dereference then 0x08 else 0x00) + Dcpu.Registers[expr.register])
    # special case: [literal + register]
    if dereference and expr.binary? and (expr.left.register? or expr.right.register?)
      if expr.binary == '+' or (expr.binary == '-' and expr.left.register?)
        register = if expr.left.register? then expr.left.register else expr.right.register
        if not Dcpu.Registers[register]?
          line.rewind(start)
          line.fail "You can't use #{register.toUpperCase()} in [R+n] form"
        op = expr.binary
        expr = if expr.left.register? then expr.right else expr.left
        # allow [R-n]
        if op == '-' then expr = Expression::Unary(expr.text, expr.pos, '-', expr)
        return new Operand(start, 0x10 + Dcpu.Registers[register], expr)
      line.rewind(start)
      line.fail "Only a register +/- a constant is allowed"
    new Operand(start, (if dereference then 0x1e else 0x1f), expr)

  # ----- data

  # read a list of data objects, which could each be an expression or a string.
  parseData: (line) ->
    line.data = []
    while not line.finished()
      start = line.pos
      if line.scanAhead('"')
        s = line.parseString()
        line.data.push(Expression::Literal(line.text, start, s.charCodeAt(i))) for i in [0 ... s.length]
      else if line.scanAhead('p"') or line.scanAhead('r"')
        if line.scan("r", Span::String)
          rom = true
        else
          line.scan("p", Span::String)
        s = line.parseString()
        word = 0
        inWord = false
        for i in [0 ... s.length]
          ch = s.charCodeAt(i)
          if rom and i == s.length - 1 then ch |= 0x80
          if inWord then line.data.push(Expression::Literal(line.text, start, word | ch)) else (word = ch << 8)
          inWord = not inWord
        if inWord then line.data.push(Expression::Literal(line.text, start, word))
      else
        line.data.push(@parseExpression(line))
      line.skipWhitespace()
      if line.scan(",", Span::Operator) then line.skipWhitespace()
    line

  # FIXME: test data line with unresolved expression

  # ----- directives

  # a directive starts with "#" or "."
  parseDirective: (line) ->
    start = line.pos
    line.directive = line.parseWord("Directive", Span::Directive)
    line.skipWhitespace()
    switch line.directive
      when "macro" then @parseMacroDirective(line)
      when "define", "equ" then @parseDefineDirective(line)
      when "org" then @parseOrgDirective(line)
      else
        line.rewind(start)
        line.fail "Unknown directive: #{directive}"

  parseDefineDirective: (line) ->
    line.name = line.parseWord("Definition name")
    line.skipWhitespace()
    line.operands.push @parseExpression(line)
    line.skipWhitespace()
    if not line.finished() then @fail "Unexpected content after definition"

  parseOrgDirective: (line) ->
    line.skipWhitespace()
    line.data.push(@parseExpression(line))
    line.skipWhitespace()
    if not line.finished() then @fail "Unexpected content after origin"

  parseMacroDirective: (line) ->
    line.setMark()
    line.name = line.parseWord("Macro name")
    line.skipWhitespace()
    args = @parseMacroArgs(line)
    line.skipWhitespace()
    line.scanAssert("{", Span::Directive)
    fullname = "#{line.name}(#{args.length})"
    if @macros[fullname]?
      line.rewind()
      line.fail "Duplicate definition of #{fullname}"
    @macros[fullname] = new Macro(fullname, args)
    if not @macros[line.name]? then @macros[line.name] = []
    @macros[line.name].push(args.length)
    @inMacro = fullname

  parseMacroArgs: (line) ->
    args = []
    if not line.scan("(", Span::Directive) then return []
    line.skipWhitespace()
    while not line.finished()
      if line.scan(")", Span::Directive) then return args
      args.push(line.parseWord("Argument name"))
      line.skipWhitespace()
      if line.scan(",", Span::Directive) then line.skipWhitespace()
    line.fail "Expected )"


exports.Line = Line
exports.Operand = Operand
exports.Parser = Parser
