
Dcpu = require('./dcpu').Dcpu
AssemblerError = require('./errors').AssemblerError

# an expression tree.
class Expression
  Register: (text, pos, name) ->
    e = new Expression(text, pos)
    e.register = name.toLowerCase()
    e.evaluate = (symtab) ->
      throw new AssemblerError(@text, @pos, "Constant expressions may not contain register references")
    e.toString = -> @register.toUpperCase()
    e.resolvable = (symtab={}) -> false
    e

  Literal: (text, pos, n) ->
    if n > 0xffff or n < -0x8000
      throw new AssemblerError(text, pos, "16-bit value is out of range: #{n}")
    e = new Expression(text, pos)
    e.literal = n
    e.evaluate = (symtab) -> @literal
    e.toString = -> @literal.toString()
    e.resolvable = (symtab={}) -> true
    e

  Label: (text, pos, x) ->
    e = new Expression(text, pos)
    e.label = x
    e.evaluate = (symtab) ->
      if not symtab[@label]?
        throw new AssemblerError(@text, @pos, "Can't resolve reference to " + @label)
      if @recursing then throw new AssemblerError(@text, @pos, "Recursive reference chain")
      expr = symtab[@label]
      if expr instanceof Expression
        @recursing = true
        expr = expr.evaluate(symtab)
        @recursing = false
      expr
    e.toString = -> @label
    e.resolvable = (symtab={}) ->
      # if it's infinite recursion, we'll catch you on evaluate.
      if @recursing then return false
      expr = symtab[@label]
      if not expr? then return false
      if not (expr instanceof Expression) then return true
      @recursing = true
      rv = expr.resolvable(symtab)
      @recursing = false
      rv
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
    e.resolvable = (symtab={}) -> @right.resolvable(symtab)
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
        when '<' then (if l < r then 1 else 0)
        when '>' then (if l > r then 1 else 0)
        when '<=' then (if l <= r then 1 else 0)
        when '>=' then (if l >= r then 1 else 0)
        when '==' then (if l == r then 1 else 0)
        when '!=' then (if l != r then 1 else 0)
        else throw new AssemblerError(@text, @pos, "Internal error (undefined binary operator)")
    e.toString = -> "(" + @left.toString() + " " + @binary + " " + @right.toString() + ")"
    e.resolvable = (symtab={}) -> @left.resolvable(symtab) and @right.resolvable(symtab)
    e.extractRegister = ->
      return [ null, null ] unless @binary in [ "+", "-" ]
      if @left.register?
        expr = @right
        if @binary == "-" then expr = Expression::Unary(expr.text, expr.pos, "-", expr)
        return [ @left.register, expr ]
      if @binary == "+" and @right.register?
        return [ @right.register, @left ]
      [ r, expr ] = @left.extractRegister(true)
      if r? then return [ r, Expression::Binary(@text, @pos, @binary, expr, @right) ]
      if @binary == "+"
        [ r, expr ] = @right.extractRegister()
        if r? then return [ r, Expression::Binary(@text, @pos, @binary, @left, expr) ]
      [ null, null ]
    e

  constructor: (@text, @pos) ->

  # for debugging.
  toString: -> throw "must be implemented in objects"

  # return true if this expression can be resolved into a final value, given
  # this symtab. never throw an exception.
  resolvable: (symtab={}) -> throw "must be implemented in objects"

  # Given a symbol table of names and values, resolve this expression tree
  # into a single number. Any register reference, or reference to a symbol
  # that isn't defined in 'symtab' will be an error.
  evaluate: (symtab={}) -> throw "must be implemented in objects"

  # if the expression can boil down to some form of (register + expr), then
  # extract and return [register, expr]. otherwise, null.
  extractRegister: -> [ null, null ]


exports.Expression = Expression
