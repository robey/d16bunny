
Dcpu = require("./dcpu").Dcpu
AssemblerError = require('./errors').AssemblerError

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
  constructor: (@text, @options={}) ->
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

  toDebug: ->
    x = 0
    rv = ""
    for span in @spans
      if x < span.start then rv += @text[x ... span.start]
      rv += "{#{span.type}:#{@text[span.start ... span.end]}}"
      x = span.end
    if x < @text.length then rv += @text[x ...]
    rv

  fail: (message) ->
    unless @options.ignoreErrors
      throw new AssemblerError(@text, @pos, message)

  finished: -> @pos == @end

  mark: -> { pos: @pos, spanLength: @spans.length }

  rewind: (m) ->
    @pos = m.pos
    @spans = @spans[0 ... m.spanLength]

  pointTo: (m) ->
    @pos = m.pos

  scan: (s, type) ->
    len = s.length
    if @pos + len <= @end and @text[@pos ... @pos + len].toLowerCase() == s
      @addSpan(type, @pos, @pos + len)
      @pos += len
      true
    else
      false

  scanAssert: (s, type) ->
    if not @scan(s, type) then @fail "Expected #{s}"

  scanAhead: (s) ->
    len = s.length
    @pos + len <= @end and @text[@pos ... @pos + len].toLowerCase() == s

  match: (regex, type) ->
    m = regex.exec(@text[@pos...])
    if not m? then return null
    @addSpan(type, @pos, @pos + m[0].length)
    @pos += m[0].length
    m[0]

  matchAhead: (regex) ->
    regex.exec(@text[@pos...])?

  skipWhitespace: ->
    return if @pos >= @end
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
      when 'e' then "\x1b"
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
    word = @match(Line.SymbolRegex, type)
    if not word? then @fail "#{name} must contain only letters, digits, _ or ."
    if Dcpu.Reserved[word] or Dcpu.ReservedOp[word] then @fail "Reserved keyword: #{word}"
    word

  parseIdentifier: (name) -> @parseWord(name, Span.Identifier)

  parseLabel: (name) -> @parseWord(name, Span.Label)

  parseInstruction: (name) -> @parseWord(name, Span.Instruction).toLowerCase()

  parseDirective: (name) -> @parseWord(name, Span.Directive).toLowerCase()

  parseMacroName: (name) -> @parseWord(name, Span.Instruction).toLowerCase()
        
  # just want all the literal text up to the next comma, closing paren, or
  # comment. but also allow quoting strings and chars.
  parseMacroArg: ->
    inString = false
    inChar = false
    parenCount = 0
    rv = ""
    mark = @pos
    while not @finished()
      if (@text[@pos] in [ ';', ')', ',' ]) and not inString and not inChar and parenCount == 0
        while @pos > mark and @text[@pos - 1] == " " then @pos -= 1
        # FIXME: "string" may not be the best syntax indicator
        if @pos > mark then @addSpan(Span.String, mark, @pos)
        return rv
      if @text[@pos] == '\\' and @pos + 1 < @end
        if @pos > mark then @addSpan(Span.String, mark, @pos)
        rv += @text[@pos++]
        rv += @text[@pos++]
        @addSpan(Span.StringEscape, @pos - 2, @pos)
        mark = @pos
      else
        ch = @text[@pos]
        rv += ch
        if ch == '"' then inString = not inString
        if ch == "\'" then inChar = not inChar
        if ch == "(" then parenCount += 1
        if ch == ")" then parenCount -= 1
        @pos++
    if inString then @fail "Expected closing \""
    if inChar then @fail "Expected closing \'"
    if @pos > mark then @addSpan(Span.String, mark, @pos)
    rv

  # return the text part of the string that includes any leading/trailing
  # whitespace or comment, but not the meat of it. this lets you change the
  # content of a line but preserve formatting and comments.
  getPrefixSuffix: ->
    if @spans.length == 0 then return [ "", "" ]
    pos = 0
    i = 0
    if @spans[0].type == Span.Label
      if @spans.length == 1 then return [ "", "" ]
      pos = @spans[0].end
      i = 1
    prefix = if @spans[i].start > pos then @text[pos ... @spans[i].start] else ""
    suffix = ""
    j = @spans.length - 1
    if @spans[j].type == "comment"
      pos = if j > i then @spans[j - 1].end else @spans[j].start
      suffix = @text[pos...]
    [ prefix, suffix ]


Line.SymbolRegex = /^[a-zA-Z_.][a-zA-Z_.0-9]*/


exports.Span = Span
exports.Line = Line
