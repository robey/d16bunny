class AssemblerError
  constructor: (@text, @pos, @reason) ->
    @setReason(@reason)
    @type = "AssemblerError"

  format: (reason) -> 
    spacer = if @pos == 0 then "" else (" " for i in [0 ... @pos]).join("")
    "\n" + @text + "\n" + spacer + "^\n" + reason + "\n"

  setReason: (reason) ->
    @reason = reason
    @message = @format(@reason)


exports.AssemblerError = AssemblerError
