
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
    @triedCompacting = false
    @foldConstants()

  toString: ->
    if @immediate?
      "<#{@code}, #{@immediate}>"
    else if @expr?
      "<#{@code}, #{@expr.toString()}>"
    else
      "<#{@code}>"

  clone: ->
    rv = new Operand(@pos, @code, @expr)
    rv.immediate = @immediate
    rv.compacting = @compacting
    rv

  resolvable: (symtab={}) ->
    if @expr? then @expr.resolvable(symtab) else true

  # resolve (permanently) any expressions that can be resolved by this
  # symtab. this is used as an optimization to take care of early constants.
  foldConstants: (symtab={}) ->
    if @expr? and @expr.resolvable(symtab)
      @immediate = @expr.evaluate(symtab) & 0xffff
      delete @expr

  # returns true if the operand is newly compactible.
  # (only the final operand can be compacted, so this function should only be
  # called on that operand.)
  # the compactible-ness is memoized, but resolved expressions are not.
  # this method is meant to be used as an edge-trigger that the size of the
  # instruction has shrunk (or grown), so symtab resolution may need to start
  # over. it also returns false if there's an expression that can't be 
  # resolved yet (so we don't know if it can be compacted).
  checkCompact: (symtab) ->
    if @code != Operand.Immediate then return false
    value = @immediateValue(symtab)
    if not value? then return false
    canCompact = (value == 0xffff or value < 31)
    if canCompact == @compacting then return false
    # okay, we should change compacting state and return true.
    if not canCompact
      # stop compacting, but also set a marker so we don't try again.
      @compacting = false
      @triedCompacting = true
      true
    else
      # don't change state if we've already been through one round of
      # compacting and then not. we might be bi-stable, so it's better to
      # just leave it alone, uncompacted.
      if @triedCompacting then return false
      @compacting = true
      true

  # return the 5-bit code for this operand, and any immediate value (or null).
  # if there's an expression that can't be resolved yet, it will be returned
  # instead of the immediate.
  pack: (symtab) ->
    value = @immediateValue(symtab)
    if @compacting
      if value?
        inline = if value == 0xffff then 0x00 else (0x01 + value)
        [ Operand.ImmediateInline + inline, null ]
      else
        # code to be resolved later...
        [ 0, null ]
    else if @expr? and not value?
      [ @code, @expr ]
    else if value?
      [ @code, value ]
    else
      [ @code, null ]

  # return the value of the immediate, if it is already known or can be
  # resolved with the current symtab. nothing is memoized. returns null if
  # there is no immediate, or it can't be resolved yet.
  immediateValue: (symtab) ->
    if @immediate? then return @immediate
    if @expr? and @expr.resolvable(symtab)
      @expr.evaluate(symtab) & 0xffff
    else
      null

Operand.Register = 0x00
Operand.RegisterDereference = 0x08
Operand.RegisterIndex = 0x10
Operand.ImmediateDereference = 0x1e
Operand.Immediate = 0x1f
Operand.ImmediateInline = 0x20


exports.Operand = Operand
