
Dcpu = require('./dcpu').Dcpu
AssemblerError = require('./errors').AssemblerError

# an expression tree.
class Expression
  Register: (text, pos, r) ->
    e = new Expression(text, pos)
    e.register = r
    e.evaluate = (symtab) ->
      throw new AssemblerError(@text, @pos, "Constant expressions may not contain register references")
    e.toString = -> Dcpu.RegisterNames[@register] if @register
    e.resolvable = (symtab) -> true
    e

  Literal: (text, pos, n) ->
    if n > 0xffff or n < -0x8000
      throw new AssemblerError(text, pos, "16-bit value is out of range: #{n}")
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
        throw new AssemblerError(@text, @pos, "You can't use " + @label.toUpperCase() + " in expressions.")
      if not symtab[@label]?
        throw new AssemblerError(@text, @pos, "Can't resolve reference to " + @label)
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
        else throw new AssemblerError(@text, @pos, "Internal error (undefined binary operator)")
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

exports.Expression = Expression
