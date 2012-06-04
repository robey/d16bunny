class AssemblerError
  constructor: (@text, @pos, @reason) ->
    @message = @format(@reason)
    @type = "AssemblerError"

  format: (reason) -> 
    spacer = if @pos == 0 then "" else (" " for i in [0 ... @pos]).join("")
    "\n" + @text + "\n" + spacer + "^\n" + reason + "\n"

exports.AssemblerError = AssemblerError
