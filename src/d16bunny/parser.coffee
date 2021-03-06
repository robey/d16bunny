
Dcpu = require("./dcpu").Dcpu
Span = require("./line").Span
Line = require("./line").Line
Operand = require("./operand").Operand
Expression = require('./expression').Expression
AssemblerError = require('./errors').AssemblerError
pp = require('./prettyprint').pp


# things parsed out of a Line
class ParsedLine
  constructor: (@line, @options) ->
    @label = null       # label (if any)
    @op = null          # operation (if any)
    @opPos = null       # position of operation in text
    @directive = null   # directive, if this is a directive instead.
    @name = null        # name (if a constant is being defined)
    @operands = []      # array of expressions
    @data = []          # array of expressions, if this is a line of raw data
    @expanded = null    # list of other Line objects, if this is an expanded macro
    # for an expanded macro, an array of info linking spans of the new line
    # to the original arguments, so that errors caused by arguments can be
    # traced back to the caller.
    @macroArgOffsets = null

  toString: ->
    [
      if @label? then ":#{@label} " else ""
      if @op? then @op.toUpperCase() else ""
      if @directive? then ".#{@directive}" else ""
      if @name? then " #{@name}" else ""
    ].join("") +
      @operands.map((x) => " " + x.toString()).join(",") +
      if @expanded? then ("{" + @expanded.map((x) => " " + x.toString()).join(";") + " }") else ""

  clone: ->
    rv = new ParsedLine(@line)
    rv.label = @label
    rv.op = @op
    rv.opPos = @opPos
    rv.directive = @directive
    rv.name = @name
    rv.operands = @operands.map (x) -> x.clone()
    rv.data = @data.map (x) -> x
    rv.expanded = if @expanded? then @expanded.map((x) -> x.clone()) else null
    rv

  toHtml: -> @line.toHtml()

  toDebug: -> @line.toDebug()

  fail: (message) ->
    unless @options.ignoreErrors
      throw new AssemblerError(@line.text, @opPos.pos, message)

  # resolve (permanently) any expressions that can be resolved by this
  # symtab. this is used as an optimization to take care of constants before
  # iterating over labels that move.
  foldConstants: (symtab) ->
    for x in @operands then x.foldConstants(symtab)
    @data = @data.map (x) =>
      if (x instanceof Expression) and x.resolvable(symtab)
        x.evaluate(symtab)
      else
        x
    if @directive == "fill" and not (@data[0] instanceof Expression)
      [ count, item ] = @data
      @data = (for i in [0 ... count] then item)
      @directive = null


class Macro
  constructor: (@name, @fullname, @parameters) ->
    @textLines = []
    @onError = null
    @parameterMatchers = @parameters.map (p) -> new RegExp("\\b#{p}\\b", "g")

  invoke: (parser, pline, args) ->
    parser.debug "  macro expansion of ", @fullname, ":"
    newTextLines = for [ filename, lineNumber, text ] in @textLines
      # textual substitution, no fancy stuff.
      argOffsets = []
      for i in [0 ... args.length]
        text = text.replace @parameterMatchers[i], (original, offset) =>
          argOffsets.push(left: offset, right: offset + args[i].length, arg: i)
          args[i]
      parser.debug "  -- ", text
      [ filename, lineNumber, text, argOffsets ]
    parser.debug "  --."

    # prefix relative labels with a unique tag
    parser.setLabelPrefix(@name + "." + Date.now() + "." + Math.floor(Math.random() * 1000000.0))

    plines = []
    try
      for [ filename, lineNumber, text, argOffsets ] in newTextLines
        try
          pline = parser.parseLine(text, filename, lineNumber)
        catch e
          if e.type != "AssemblerError" then throw e
          parser.debug "  error in macro invocation: pos=", e.pos, " args=", argOffsets, " reason=", e.reason
          if @onError? then e.setReason(@onError)
          for argOffset in argOffsets
            if e.pos >= argOffset.left and e.pos <= argOffset.right
              throw new AssemblerError(pline.line.text, pline.macroArgIndexes[argOffset.arg], e.reason)
          # hm. well, if we changed the error message, point to the caller.
          if @onError?
            throw new AssemblerError(pline.line.text, (if args.length > 0 then pline.macroArgIndexes[0] else 0), e.reason)
        pline.macroArgOffsets = argOffsets
        if pline.directive? then pline.line.fail "Macros can't have directives in them"
        if pline.expanded?
          # nested macros are okay, but unpack them.
          expanded = pline.expanded
          delete pline.expanded
          # if a macro was expanded on a line with a label, push the label by itself, so we remember it.
          if pline.label? then plines.push(pline)
          for x in expanded then plines.push(x)
        else
          plines.push(pline)
    finally
      parser.clearLabelPrefix()
    parser.debug "  macro expansion of ", @fullname, " complete: ", plines.length, " lines"
    plines


# parse lines of DCPU assembly into structured data.
class Parser
  DelimiterRegex: /^(\)|,|\])/
  UnaryRegex: /^(\+|\-)/

  NumberRegex: /^[0-9]+/
  HexRegex: /^0x[0-9a-fA-F]+/
  BinaryRegex: /^0b[01]+/
  LabelRegex: /^([a-zA-Z_.][a-zA-Z_.0-9]*|\$)/
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
    @inMacro = null            # if waiting for an "}"
    @ifStack = []              # for nested .if
    @ignoring = false          # for skipping sections inside in .if
    @constants = {}            # definitions found by .define
    @lastLabel = null          # for resolving relative labels
    @labelPrefix = null        # label prefix for a currently-expanding macro
    @labelStack = []           # for saving the label prefix when entering a macro expansion

  debug: (list...) ->
    unless @debugger? then return
    slist = for item in list
      switch typeof item
        when 'string' then item.toString()
        else pp(item)
    @debugger(slist.join(""))

  fixLabel: (label, save=false) ->
    if label[0] == "."
      if @labelPrefix?
        label = @labelPrefix + label
      else if @lastLabel?
        label = @lastLabel + label
    else
      if save then @lastLabel = label
    label

  setLabelPrefix: (prefix) ->
    @labelStack.push([ @lastLabel, @labelPrefix ])
    @lastLabel = null
    @labelPrefix = prefix

  clearLabelPrefix: ->
    [ @lastLabel, @labelPrefix ] = @labelStack.pop()

  # returns a Line object, with syntax parsed out
  parseLine: (text, filename="", lineNumber=0, options={}) ->
    @debug "+ parse: ", lineNumber, ": ", text
    line = new Line(text, options)
    pline = new ParsedLine(line, options)
    pline.filename = filename
    pline.lineNumber = lineNumber
    line.skipWhitespace()
    if line.finished() then return pline

    sol = line.mark()
    if line.scan("#", Span.Directive) or line.scan(".", Span.Directive)
      if @parseDirective(line, pline) then return pline
      line.rewind(sol)
    if @ignoring then return pline

    if line.scan("}", Span.Directive)
      @parseMacroEnd(line)
      return pline

    if @inMacro
      @macros[@inMacro].textLines.push([ filename, lineNumber, text ])
      return pline

    if line.scan(":", Span.Label)
      pline.label = line.parseLabel("Label")
      pline.label = @fixLabel(pline.label, true)
      line.skipWhitespace()
    return pline if line.finished()

    pline.opPos = line.mark()
    pline.op = line.parseInstruction("Operation name")

    if pline.op == "equ"
      # allow ":label equ <val>" for windows people
      line.rewind(pline.opPos)
      line.scanAssert("equ", Span.Directive)
      line.skipWhitespace()
      expr = @parseExpression(line)
      if not pline.label?
        line.pointTo(pline.opPos)
        line.fail "EQU must be a directive or on a line with a label"
        return pline
      name = pline.label
      delete pline.label
      delete pline.op
      @constants[name] = expr
      @constants[name].filename = pline.filename
      @constants[name].lineNumber = pline.lineNumber
      line.skipWhitespace()
      if not line.finished() then line.fail "Unexpected content after definition"
      return pline

    if pline.op == "dat"
      @parseData(line, pline)
      return pline

    if pline.op == "org"
      line.rewind(pline.opPos)
      delete pline.op
      line.scanAssert("org", Span.Directive)
      pline.directive = "org"
      @parseOrgDirective(line, pline)
      return pline

    line.skipWhitespace()
    if line.scan("=", Span.Operator)
      # special case "name = value"
      line.rewind(pline.opPos)
      delete pline.op
      name = line.parseIdentifier("Constant name")
      line.skipWhitespace()
      line.scanAssert("=", Span.Operator)
      line.skipWhitespace()
      @constants[name] = @parseExpression(line)
      @constants[name].filename = pline.filename
      @constants[name].lineNumber = pline.lineNumber
      line.skipWhitespace()
      if not line.finished() then line.fail "Unexpected content after definition"
      return pline

    if not Dcpu.BinaryOp[pline.op]? and not Dcpu.SpecialOp[pline.op]?
      line.rewind(pline.opPos)
      delete pline.op
      return @parseMacroCall(line, pline)

    # any other operation is assumed to take actual operands
    pline.operands = []
    while not line.finished()
      pline.operands.push(@parseOperand(line, pline.operands.length == 0))
      line.skipWhitespace()
      if not line.finished()
        line.scanAssert(",", Span.Operator)
        line.skipWhitespace()
    if Dcpu.BinaryOp[pline.op]?
      if pline.operands.length != 2
        pline.fail "#{pline.op.toUpperCase()} requires 2 arguments"
    else if Dcpu.SpecialOp[pline.op]?
      if pline.operands.length != 1
        pline.fail "#{pline.op.toUpperCase()} requires 1 argument"
    else
      pline.fail "Unknown instruction: #{pline.op}"

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
      if not op?
        line.fail "Unknown operator (try: + - * / % << >> & ^ |)"
        return left
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
      return Expression::Register(line.text, m.pos, x?.toLowerCase())
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
      return Expression::Label(line.text, m.pos, @fixLabel(x, false))
    line.pointTo(m)
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
          line.pointTo(m)
          line.fail "You can't dereference #{expr.toString()}"
        if (destination and expr.register == "pop") or ((not destination) and expr.register == "push")
          line.pointTo(m)
          line.fail "You can't use #{expr.toString()} in this position"
        return new Operand(m.pos, Dcpu.Specials[expr.register])
      code = if dereference then Operand.RegisterDereference else Operand.Register
      return new Operand(m.pos, code + Dcpu.Registers[expr.register])
    # special case: [literal + register]
    if dereference
      [ r, e ] = expr.extractRegister()
      if r?
        if not Dcpu.Registers[r]?
          line.pointTo(m)
          line.fail "You can't use #{r.toUpperCase()} in [R+n] form"
        return new Operand(m.pos, Operand.RegisterIndex + Dcpu.Registers[r], e)
    new Operand(m.pos, (if dereference then Operand.ImmediateDereference else Operand.Immediate), expr)

  # ----- data

  # read a list of data objects, which could each be an expression or a string.
  parseData: (line, pline) ->
    delete pline.op
    delete pline.directive
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

  # ----- directives

  # a directive starts with "#" or "."
  parseDirective: (line, pline) ->
    m = line.mark()
    pline.directive = line.parseDirective("Directive")
    line.skipWhitespace()
    if pline.directive in [ "if", "else", "endif" ]
      if @inMacro then return false
      switch pline.directive
        when "if" then @parseIfDirective(line, pline)
        when "else" then @parseElseDirective(line, pline)
        when "endif" then @parseEndifDirective(line, pline)
      return true
    # no other directives count if we're in the ignoring part of an if-block.
    if @ignoring then return
    switch pline.directive
      when "macro" then @parseMacroDirective(line, pline)
      when "endmacro" then @parseMacroEnd(line)
      when "define", "equ" then @parseDefineDirective(line, pline)
      when "org" then @parseOrgDirective(line, pline)
      when "onerror" then @parseOnErrorDirective(line, pline)
      when "include" then @parseIncludeDirective(line, pline)
      when "dat" then @parseData(line, pline)
      when "fill" then @parseFillDirective(line, pline)
      when "error" then @parseError(line, m)
      else
        line.pointTo(m)
        line.fail "Unknown directive: #{pline.directive}"
    true

  parseDefineDirective: (line, pline) ->
    delete pline.directive
    name = line.parseIdentifier("Definition name")
    line.skipWhitespace()
    @constants[name] = @parseExpression(line)
    @constants[name].filename = pline.filename
    @constants[name].lineNumber = pline.lineNumber
    line.skipWhitespace()
    if not line.finished() then @fail "Unexpected content after definition"

  parseOrgDirective: (line, pline) ->
    line.skipWhitespace()
    pline.data.push(@parseExpression(line).evaluate())
    line.skipWhitespace()
    if not line.finished() then @fail "Unexpected content after origin"

  parseMacroDirective: (line, pline) ->
    m = line.mark()
    pline.name = line.parseIdentifier("Macro name")
    line.skipWhitespace()
    parameters = @parseMacroParameters(line)
    line.skipWhitespace()
    line.scan("{", Span.Directive)
    fullname = "#{pline.name}(#{parameters.length})"
    if @macros[fullname]?
      line.pointTo(m)
      line.fail "Duplicate definition of #{fullname}"
    @macros[fullname] = new Macro(pline.name, fullname, parameters)
    if not @macros[pline.name]? then @macros[pline.name] = []
    @macros[pline.name].push(parameters.length)
    @inMacro = fullname
    @debug "  defining macro ", fullname

  parseMacroParameters: (line) ->
    args = []
    if not line.scan("(", Span.Directive) then return []
    line.skipWhitespace()
    while not line.finished()
      if line.scan(")", Span.Directive) then return args
      args.push(line.parseIdentifier("Argument name"))
      line.skipWhitespace()
      if line.scan(",", Span.Directive) then line.skipWhitespace()
    line.fail "Expected )"

  parseMacroEnd: (line) ->
    if not @inMacro
      line.fail "Unexpected end of macro"
      return pline
    @debug "  finished defining macro ", @inMacro
    @inMacro = false
    line.skipWhitespace()
    if not line.finished() then line.fail "Unexpected content after end of macro"

  # expand a macro call, recursively parsing the nested lines
  parseMacroCall: (line, pline) ->
    m = line.mark()
    name = line.parseMacroName("Macro name")
    line.skipWhitespace()
    if line.scan("(", Span.Operator) then line.skipWhitespace()
    [ args, argIndexes ] = @parseMacroArgs(line)
    pline.macroArgIndexes = argIndexes
    # allow local labels to be passed to a macro:
    args = args.map (x) => if x[0] == "." then @fixLabel(x) else x
    if not @macros[name]
      line.pointTo(m)
      line.fail "Unknown macro '#{name}'"
    else if @macros[name].indexOf(args.length) < 0
      line.pointTo(m)
      line.fail "Macro '#{name}' requires #{@macros[name].join(' or ')} arguments"
    else
      pline.expanded = @macros["#{name}(#{args.length})"].invoke(@, pline, args)
    pline

  # don't overthink this. we want literal text substitution.
  parseMacroArgs: (line) ->
    args = []
    argIndexes = []
    line.skipWhitespace()
    while not line.finished()
      if line.scan(")", Span.Operator) then return [ args, argIndexes ]
      index = line.pos
      args.push(line.parseMacroArg())
      argIndexes.push(index)
      line.scan(",", Span.Operator)
      line.skipWhitespace()
    [ args, argIndexes ]

  parseIfDirective: (line, pline) ->
    line.skipWhitespace()
    m = line.mark()
    expr = @parseExpression(line)
    if not line.finished() then line.fail "Unexpected content after IF"
    if not expr.resolvable(@constants)
      line.pointTo(m)
      line.fail "IF expression must use only constants"
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
    @ignoring = if @ifStack.length > 0 then @ifStack[@ifStack.length - 1] else false

  parseOnErrorDirective: (line, pline) ->
    if not @inMacro? then line.fail "Can only use .onerror inside macros"
    line.skipWhitespace()
    @macros[@inMacro].onError = line.parseString()
    if not line.finished() then line.fail "Unexpected content after .onerror"

  parseIncludeDirective: (line, pline) ->
    line.skipWhitespace()
    pline.name = line.parseString()
    if not line.finished() then line.fail "Unexpected content after INCLUDE"

  # weird one: #fill (count) (item)
  parseFillDirective: (line, pline) ->
    line.skipWhitespace()
    count = @parseExpression(line)
    line.scanAssert(",", Span.Operator)
    line.skipWhitespace()
    item = @parseExpression(line)
    pline.data = [ count, item ]
    if not line.finished() then line.fail "Unexpected content after FILL <count>, <expr>"

  parseError: (line, mark) ->
    line.skipWhitespace()
    message = line.parseString()
    line.pointTo(mark)
    line.fail message


exports.Line = Line
exports.Macro = Macro
exports.Parser = Parser
