
Dcpu = require("./dcpu").Dcpu
Expression = require('./expression').Expression
AssemblerError = require('./errors').AssemblerError
prettyPrinter = require('./prettyprint').prettyPrinter

class Span
  constructor: (@type, @start, @end) ->

Span.Comment = "comment"
Span.Directive = "directive"
Span.Identifier = "identifier"
Span.Operator = "operator"
Span.String = "string"
Span.StringEscape = "string-escape"
Span.Register = "register"
Span.Number = "number"
Span.Instruction = "instruction"
Span.Label = "label"


# for parsing a line of text, and syntax highlighting
class Line
  constructor: (@text) ->
    @pos = 0            # current index within text
    @end = @text.length # parsing should not continue past end
    @spans = []         # spans for syntax highlighting

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

  mark: -> { pos: @pos, spanLength: @spans.length }

  rewind: (m) ->
    @pos = m.pos
    @spans = @spans[0 ... m.spanLength]

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
      @addSpan(Span.Comment, @pos, @end)
      @end = @pos

  parseChar: ->
    if @text[@pos] != "\\" or @pos + 1 == @end
      @addSpan(Span.String, @pos, @pos + 1)
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
    @addSpan(Span.StringEscape, start, @pos)
    rv

  parseString: ->
    rv = ""
    if not @scan('"', Span.String) then @fail "Expected string"
    while not @finished() and @text[@pos] != '"'
      rv += @parseChar()
    @scanAssert('"', Span.String)
    rv

  parseWord: (name, type = Span.Identifier) ->
    word = @match(Parser::SymbolRegex, type)
    if not word? then @fail "#{name} must contain only letters, digits, _ or ."
    word = word.toLowerCase()
    if Dcpu.Reserved[word] or Dcpu.ReservedOp[word] then @fail "Reserved keyword: #{word}"
    word

  # just want all the literal text up to the next comma, closing paren, or
  # comment. but also allow quoting strings and chars.
  parseMacroArg: ->
    inString = false
    inChar = false
    rv = ""
    while not @finished()
      return rv if (@text[@pos] in [ ';', ')', ',' ]) and not inString and not inChar
      start = @pos
      if @text[@pos] == '\\' and @pos + 1 < @end
        rv += @text[@pos++]
        rv += @text[@pos++]
        @addSpan(Span.StringEscape, start, @pos)
      else
        ch = @text[@pos]
        rv += ch
        if ch == '"' then inString = not inString
        if ch == "\'" then inChar = not inChar
        @pos++
        # FIXME: "string" may not be the best syntax indicator
        @addSpan(Span.String, start, @pos)
    if inString then @fail "Expected closing \""
    if inChar then @fail "Expected closing \'"
    rv


# things parsed out of a Line
class ParsedLine
  constructor: (@line) ->
    @label = null       # label (if any)
    @op = null          # operation (if any)
    @opPos = 0          # position of operation in text
    @directive = null   # directive, if this is a directive instead.
    @name = null        # name (if a constant is being defined)
    @operands = []      # array of expressions
    @data = []          # array of expressions, if this is a line of raw data
    @expanded = null    # list of other Line objects, if this is an expanded macro

  toString: ->
    [
      if @label? then ":#{@label} " else ""
      if @op? then @op.toUpperCase() else ""
      if @directive? then ".#{@directive}" else ""
      if @name? then " #{@name}" else ""
    ].join("") +
      @operands.map((x) => " " + x.toString()).join(",") +
      if @expanded? then ("{" + @expanded.map((x) => " " + x.toString()).join(";") + " }") else ""

  toHtml: -> @line.toHtml()


class Operand
  # pos: where it is in the string
  # code: 5-bit value for the operand in an opcode
  # expr: (optional) an expression to be evaluated for the immediate
  # immediate: (optional) a resolved 16-bit immediate
  #   (only one of 'expr' or 'immediate' will ever be set)
  # compactable: true if the im
  constructor: (@pos, @code, @expr) ->
    @immediate = null
    @compacting = false
    if @expr? and not @expr.dependency()?
      @immediate = @expr.evaluate() & 0xffff
      delete @expr

  toString: ->
    if @immediate?
      "<#{@code}, #{@immediate}>"
    else if @expr?
      "<#{@code}, #{@expr.toString()}>"
    else
      "<#{@code}>"

  dependency: (symtab={}) ->
    @expr?.dependency(symtab)

  # returns true if the operand is newly compactible.
  # the compactible-ness is memoized, but resolved expressions are not.
  # this method is meant to be used as an edge-trigger that the size of the
  # instruction has shrunk, so after a true result, future calls will return
  # false. it also returns false if there's an expression that can't be 
  # resolved yet (so we don't know if it can be compacted).
  checkCompact: (symtab) ->
    if @compacting or @code != Operand.Immediate then return false
    if @expr?
      if @expr.dependency(symtab)? then return false
      value = @expr.evaluate(symtab)
    else if @immediate?
      value = @immediate
    else
      return false
    if value == 0xffff or value < 31
      @compacting = true
      true
    else
      false

  # return the 5-bit code for this operand, and any immediate value (or null).
  # if there's an expression that can't be resolved yet, it will be returned
  # instead of the immediate.
  pack: (symtab, canCompact=false) ->
    value = null
    if @expr? and not @expr.dependency(symtab)?
      value = @expr.evaluate(symtab)
    else if @immediate?
      value = @immediate
    if @compacting and canCompact and value?
      inline = if value == 0xffff then 0x00 else (0x01 + value)
      [ Operand.ImmediateInline + inline, null ]
    else if @expr? and not value?
      [ @code, @expr ]
    else if value?
      [ @code, value ]
    else
      [ @code, null ]

  # attempt to resolve the expression in this operand. returns true on
  # success, and sets:
  #   - immediate: (optional) immediate value for this operand
  #FIXME delete
  resolve: (symtab) ->
    # FIXME move to caller
    #      @debug "  resolve operand: code=#{@code} expr=#{@expr.toString()}"
    if not @expr? then return true
    if @expr.dependency(symtab)? then return false
    @immediate = @expr.evaluate(symtab) & 0xffff
    delete @expr

  # will this fit into 
  # fit the immediate into a the operand code, if possible.
  #FIXME delete
  compact: ->
    if @code == Operand.Immediate and (@immediate == 0xffff or @immediate < 31)
      @code = 0x20 + (if @immediate == 0xffff then 0x00 else (0x01 + @immediate))
      delete @immediate
      true
    else
      false

Operand.Register = 0x00
Operand.RegisterDereference = 0x08
Operand.RegisterIndex = 0x10
Operand.ImmediateDereference = 0x1e
Operand.Immediate = 0x1f
Operand.ImmediateInline = 0x20


class Macro
  constructor: (@name, @parameters) ->
    @textLines = []
    @parameterMatchers = @parameters.map (p) -> new RegExp("\\b#{p}\\b", "g")


# parse lines of DCPU assembly into structured data.
class Parser
  DelimiterRegex: /^(\)|,|\])/
  UnaryRegex: /^(\+|\-)/

  NumberRegex: /^[0-9]+/
  HexRegex: /^0x[0-9a-fA-F]+/
  BinaryRegex: /^0b[01]+/
  LabelRegex: /^([a-zA-Z_.][a-zA-Z_.0-9]*|\$)/
  SymbolRegex: /^[a-zA-Z_.][a-zA-Z_.0-9]*/
  OperatorRegex: /^(\*|\/|%|\+|\-|<<|>>|\&|\^|\||<\=|>\=|<|>|==|!=)/

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
    '<' : 4
    '>' : 4
    '<=' : 4
    '>=' : 4
    '==' : 4
    '!=' : 4

  constructor: ->
    @reset()

  reset: ->
    @macros = {}
    @inMacro = null    # if waiting for an "}"
    @ifStack = []      # for nested .if
    @ignoring = false  # for skipping sections inside in .if
    @constants = {}            # definitions found by .define
    @lastLabel = null          # for resolving relative labels
    @expandingMacro = null     # label prefix for a currently-expanding macro

  debug: (list...) ->
    unless @debugger? then return
    slist = for item in list
      switch typeof item
        when 'string' then item.toString()
        else prettyPrinter.dump(item)
    @debugger(slist.join(""))

  fixLabel: (label) ->
    if label[0] == "."
      if @lastLabel? then label = @lastLabel + label
    else
      @lastLabel = label
    if @expandingMacro? then label = @expandingMacro + "." + label
    label

  # returns a Line object, with syntax parsed out
  parseLine: (text, lineNumber = 0) ->
    @debug "+ parse: ", lineNumber, ": ", text
    line = new Line(text)
    pline = new ParsedLine(line)
    pline.lineNumber = lineNumber
    line.skipWhitespace()
    if line.finished() then return pline

    if line.scan("#", Span.Directive) or line.scan(".", Span.Directive)
      @parseDirective(line, pline)
      return pline
    if @ignoring then return pline

    if @inMacro
      if line.scan("}", Span.Directive)
        @inMacro = false
      else
        @macros[@inMacro].textLines.push(text)
      return pline

    if line.scan(":", Span.Label)
      pline.label = line.parseWord("Label", Span.Label)
      pline.label = @fixLabel(pline.label)
      line.skipWhitespace()
    return pline if line.finished()

    pline.opPos = line.mark()
    pline.op = line.parseWord("Operation name", Span.Instruction)

    if @macros[pline.op]
      line.rewind(pline.opPos)
      delete pline.op
      return @parseMacroCall(line, pline)

    if pline.op == "equ"
      # allow ":label equ <val>" for windows people
      line.rewind(pline.opPos)
      if not pline.label?
        line.fail "EQU must be a directive or on a line with a label"
      name = pline.label
      delete pline.label
      delete pline.op
      line.scan("equ", Span.Directive)
      line.skipWhitespace()
      @constants[name] = @parseExpression(line)
      line.skipWhitespace()
      if not line.finished() then line.fail "Unexpected content after definition"
      return pline

    if pline.op == "dat"
      @parseData(line, pline)
      return pline

    if pline.op == "org"
      line.rewind(pline.opPos)
      delete pline.op
      line.scan("org", Span.Directive)
      pline.directive = "org"
      @parseOrgDirective(line, pline)
      return pline

    line.skipWhitespace()
    if line.scan("=", Span.Operator)
      # special case "name = value"
      line.rewind(pline.opPos)
      delete pline.op
      name = line.parseWord("Constant name", Span.Identifier)
      line.skipWhitespace()
      line.scan("=", Span.Operator)
      line.skipWhitespace()
      @constants[name] = @parseExpression(line)
      line.skipWhitespace()
      if not line.finished() then line.fail "Unexpected content after definition"
      return pline

    # any other operation is assumed to take actual operands
    pline.operands = []
    while not line.finished()
      pline.operands.push(@parseOperand(line, pline.operands.length == 0))
      line.skipWhitespace()
      if not line.finished() and line.scan(",", Span.Operator) then line.skipWhitespace()

    pline

  # ----- expressions

  parseExpression: (line, precedence = 0) ->
    line.skipWhitespace()
    if line.finished() then line.fail "Expected expression"
    left = @parseUnary(line)
    loop
      line.skipWhitespace()
      return left if line.finished() or line.matchAhead(Parser::DelimiterRegex)
      m = line.mark()
      op = line.match(Parser::OperatorRegex, Span.Operator)
      if not op? then line.fail "Unknown operator (try: + - * / % << >> & ^ |)"
      newPrecedence = Parser::Binary[op]
      if newPrecedence <= precedence
        line.rewind(m)
        return left
      right = @parseExpression(line, newPrecedence)
      left = Expression::Binary(line.text, m.pos, op, left, right)

  parseUnary: (line) ->
    start = line.pos
    op = line.match(Parser::UnaryRegex, Span.Operator)
    if op?
      expr = @parseAtom(line)
      Expression::Unary(line.text, start, op, expr)
    else
      @parseAtom(line)

  # parse a single atom and return an expression.
  parseAtom: (line) ->
    line.skipWhitespace()
    if line.finished() then line.fail "Value expected (operand or expression)"
    m = line.mark()
    if line.scan("(", Span.Operator)
      atom = @parseExpression(line)
      line.skipWhitespace()
      if line.finished() or (not line.scan(")", Span.Operator)) then line.fail "Missing ) on expression"
      return atom
    if line.scan("'", Span.String)
      # literal char
      ch = line.parseChar()
      line.scanAssert("'", Span.String)
      return Expression::Literal(line.text, m.pos, ch.charCodeAt(0))
    if line.scan("%", Span.Register)
      # allow unix-style %A for register names
      x = line.match(Dcpu.RegisterRegex, Span.Register)
      if not x? then line.fail "Expected register name"
      return Expression::Register(line.text, m.pos, x.toLowerCase())
    x = line.match(Parser::HexRegex, Span.Number)
    if x? then return Expression::Literal(line.text, m.pos, parseInt(x, 16))
    x = line.match(Parser::BinaryRegex, Span.Number)
    if x? then return Expression::Literal(line.text, m.pos, parseInt(x[2...], 2))
    x = line.match(Parser::NumberRegex, Span.Number)
    if x? then return Expression::Literal(line.text, m.pos, parseInt(x, 10))
    x = line.match(Dcpu.RegisterRegex, Span.Register)
    if x? then return Expression::Register(line.text, m.pos, x.toLowerCase())
    x = line.match(Parser::LabelRegex, Span.Identifier)
    if x?
      if x[0] == "." and @lastLabel? then x = @lastLabel + x
      if @expandingMacro then x = @expandingMacro + "." + x
      return Expression::Label(line.text, m.pos, x)
    line.rewind(m)
    line.fail "Expected expression"

  # ----- operands

  # parse an operand expression.
  # if 'destination' is set, then the operand is in the destination slot
  # (which determines whether it uses "push" or "pop").
  parseOperand: (line, destination = false) ->
    @debug "  parse operand: dest=", destination, " pos=", line.pos
    m = line.mark()
    dereference = false
    inPick = false

    if line.scan("[", Span.Operator)
      dereference = true
    else if line.scan("pick", Span.Register)
      inPick = true

    expr = @parseExpression(line)
    @debug "  parse operand: expr=", expr
    if dereference then line.scanAssert("]", Span.Operator)
    if inPick then return new Operand(m.pos, Dcpu.Specials["pick"], expr)
    if expr.register? 
      if Dcpu.Specials[expr.register]?
        if dereference
          line.rewind(m)
          line.fail "You can't dereference #{expr.toString()}"
        if (destination and expr.register == "pop") or ((not destination) and expr.register == "push")
          line.rewind(m)
          line.fail "You can't use #{expr.toString()} in this position"
        return new Operand(m.pos, Dcpu.Specials[expr.register])
      code = if dereference then Operand.RegisterDereference else Operand.Register
      return new Operand(m.pos, code + Dcpu.Registers[expr.register])
    # special case: [literal + register]
    if dereference and expr.binary? and (expr.left.register? or expr.right.register?)
      if expr.binary == '+' or (expr.binary == '-' and expr.left.register?)
        register = if expr.left.register? then expr.left.register else expr.right.register
        if not Dcpu.Registers[register]?
          line.rewind(m)
          line.fail "You can't use #{register.toUpperCase()} in [R+n] form"
        op = expr.binary
        expr = if expr.left.register? then expr.right else expr.left
        # allow [R-n]
        if op == '-' then expr = Expression::Unary(expr.text, expr.pos, '-', expr)
        return new Operand(m.pos, Operand.RegisterIndex + Dcpu.Registers[register], expr)
      line.rewind(m)
      line.fail "Only a register +/- a constant is allowed"
    new Operand(m.pos, (if dereference then Operand.ImmediateDereference else Operand.Immediate), expr)

  # ----- data

  # read a list of data objects, which could each be an expression or a string.
  parseData: (line, pline) ->
    pline.data = []
    line.skipWhitespace()
    while not line.finished()
      m = line.mark()
      if line.scanAhead('"')
        s = line.parseString()
        pline.data.push(Expression::Literal(line.text, m.pos, s.charCodeAt(i))) for i in [0 ... s.length]
      else if line.scanAhead('p"') or line.scanAhead('r"')
        if line.scan("r", Span.String)
          rom = true
        else
          line.scan("p", Span.String)
        s = line.parseString()
        word = 0
        inWord = false
        for i in [0 ... s.length]
          ch = s.charCodeAt(i)
          if rom and i == s.length - 1 then ch |= 0x80
          if inWord then pline.data.push(Expression::Literal(line.text, m.pos, word | ch)) else (word = ch << 8)
          inWord = not inWord
        if inWord then pline.data.push(Expression::Literal(line.text, m.pos, word))
      else
        pline.data.push(@parseExpression(line))
      line.skipWhitespace()
      if line.scan(",", Span.Operator) then line.skipWhitespace()

  # FIXME: test data line with unresolved expression

  # ----- directives

  # a directive starts with "#" or "."
  parseDirective: (line, pline) ->
    m = line.mark()
    pline.directive = line.parseWord("Directive", Span.Directive)
    line.skipWhitespace()
    if pline.directive in [ "if", "else", "endif" ]
      switch pline.directive
        when "if" then @parseIfDirective(line, pline)
        when "else" then @parseElseDirective(line, pline)
        when "endif" then @parseEndifDirective(line, pline)
      return
    # no other directives count if we're in the ignoring part of an if-block.
    if @ignoring then return
    switch pline.directive
      when "macro" then @parseMacroDirective(line, pline)
      when "define", "equ" then @parseDefineDirective(line, pline)
      when "org" then @parseOrgDirective(line, pline)
      else
        line.rewind(m)
        line.fail "Unknown directive: #{directive}"

  parseDefineDirective: (line, pline) ->
    delete pline.directive
    name = line.parseWord("Definition name")
    line.skipWhitespace()
    @constants[name] = @parseExpression(line)
    line.skipWhitespace()
    if not line.finished() then @fail "Unexpected content after definition"

  parseOrgDirective: (line, pline) ->
    line.skipWhitespace()
    pline.data.push(@parseExpression(line).evaluate())
    line.skipWhitespace()
    if not line.finished() then @fail "Unexpected content after origin"

  parseMacroDirective: (line, pline) ->
    m = line.mark()
    pline.name = line.parseWord("Macro name")
    line.skipWhitespace()
    parameters = @parseMacroParameters(line)
    line.skipWhitespace()
    line.scanAssert("{", Span.Directive)
    fullname = "#{pline.name}(#{parameters.length})"
    if @macros[fullname]?
      line.rewind(m)
      line.fail "Duplicate definition of #{fullname}"
    @macros[fullname] = new Macro(fullname, parameters)
    if not @macros[line.name]? then @macros[pline.name] = []
    @macros[pline.name].push(parameters.length)
    @inMacro = fullname

  parseMacroParameters: (line) ->
    args = []
    if not line.scan("(", Span.Directive) then return []
    line.skipWhitespace()
    while not line.finished()
      if line.scan(")", Span.Directive) then return args
      args.push(line.parseWord("Argument name"))
      line.skipWhitespace()
      if line.scan(",", Span.Directive) then line.skipWhitespace()
    line.fail "Expected )"

  # expand a macro call, recursively parsing the nested lines
  parseMacroCall: (line, pline) ->
    m = line.mark()
    name = line.parseWord("Macro name", Span.Identifier)
    line.skipWhitespace()
    if line.scan("(", Span.Operator) then line.skipWhitespace()
    args = @parseMacroArgs(line)
    if @macros[name].indexOf(args.length) < 0
      line.rewind(m)
      line.fail "Macro '#{name}' requires #{@macros[name].join(' or ')} arguments"
    macro = @macros["#{name}(#{args.length})"]

    @debug "  macro expansion of ", name, "(", args.length, "):"
    newTextLines = for text in macro.textLines
      # textual substitution, no fancy stuff.
      for i in [0 ... args.length]
        text = text.replace(macro.parameterMatchers[i], args[i])
      @debug "  -- ", text
      text
    @debug "  --."

    pline.expanded = []
    saved1 = @expandingMacro
    @expandingMacro = name + "." + Date.now() + "." + Math.floor(Math.random() * 1000000.0)
    saved2 = @lastLabel
    @lastLabel = null
    for text in newTextLines
      xline = @parseLine(text)
      if xline.directive?
        line.rewind(m)
        line.fail "Macros can't have directives in them"
      if xline.expanded?
        # nested macros are okay, but unpack them.
        expanded = xline.expanded
        delete xline.expanded
        # if a macro was expanded on a line with a label, push the label by itself, so we remember it.
        if xline.label? then pline.expanded.push(xline)
        for x in expanded then pline.expanded.push(x)
      else
        pline.expanded.push(xline)
    @debug "  macro expansion of ", name, "(", args.length, ") complete: ", pline.expanded.length, " lines"
    @expandingMacro = saved1
    @lastLabel = saved2
    pline

  # don't overthink this. we want literal text substitution.
  parseMacroArgs: (line) ->
    args = []
    line.skipWhitespace()
    while not line.finished()
      if line.scan(")", Span.Operator) then return args
      args.push(line.parseMacroArg())
      if line.scan(",", Span.Operator) then line.skipWhitespace()
    args

  parseIfDirective: (line, pline) ->
    line.skipWhitespace()
    m = line.mark()
    expr = @parseExpression(line)
    if not line.finished() then line.fail "Unexpected content after IF"
    if expr.dependency(@constants)?
      line.rewind(m)
      line.fail "IF expression must use only constants (undefined: #{expr.dependency(@constants)}"
    expr = expr.evaluate(@constants)
    @ignoring = (expr == 0)
    @ifStack.push(@ignoring)

  parseElseDirective: (line, pline) ->
    line.skipWhitespace()
    if not line.finished() then line.fail "Unexpected content after ELSE"
    if @ifStack.length == 0 then line.fail "Dangling ELSE"
    @ignoring = not @ignoring
    @ifStack.pop()
    @ifStack.push(@ignoring)

  parseEndifDirective: (line, pline) ->
    line.skipWhitespace()
    if not line.finished() then line.fail "Unexpected content after ENDIF"
    if @ifStack.length == 0 then line.fail "Dangling ENDIF"
    @ifStack.pop()
    if @ifStack.length > 0 then @ignoring = @ifStack[@ifStack.length - 1]


exports.Line = Line
exports.Operand = Operand
exports.Parser = Parser
