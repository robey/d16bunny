
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
    e.dependency = (symtab) -> null
    e

  Literal: (text, pos, n) ->
    if n > 0xffff or n < -0x8000
      throw new AssemblerError(text, pos, "16-bit value is out of range: #{n}")
    e = new Expression(text, pos)
    e.literal = n
    e.evaluate = (symtab) -> @literal
    e.toString = -> @literal.toString()
    e.dependency = (symtab) -> null
    e

  Label: (text, pos, x) ->
    e = new Expression(text, pos)
    e.label = x
    e.evaluate = (symtab) ->
      if not symtab[@label]?
        throw new AssemblerError(@text, @pos, "Can't resolve reference to " + @label)
      symtab[@label]
    e.toString = -> @label
    e.dependency = (symtab) -> if symtab?[@label]? then null else @label
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
    e.dependency = (symtab) -> @right.dependency(symtab)
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
    e.dependency = (symtab) ->
      missing = @left.dependency(symtab)
      if not missing? then missing = @right.dependency(symtab)
      missing
    e

  constructor: (@text, @pos) ->

  # for debugging.
  toString: -> throw "must be implemented in objects"

  # return the name of the first symbol that's required by this expression,
  # but missing from the symtab. return null if everything is okay.
  # (if 'dependency' returns null, then 'evaluate' must succeed.)
  dependency: (symtab) -> throw "must be implemented in objects"

  # Given a symbol table of names and values, resolve this expression tree
  # into a single number. Any register reference, or reference to a symbol
  # that isn't defined in 'symtab' will be an error.
  evaluate: (symtab) -> throw "must be implemented in objects"

exports.Expression = Expression
