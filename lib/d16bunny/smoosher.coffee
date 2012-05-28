
util = require 'util'

class Smoosher
  # gray, yellow, orange, red, purple, blue, cyan, green
  colors: [ "37", "33;1", "33", "31", "35", "34", "36", "32" ]

  inColor: (s, colorIndex) ->
    colorIndex %= 8
    "\u001b[" + @colors[colorIndex] + "m" + s + "\u001b[0m"

  smoosh: (obj, colorIndex = 0) ->
    switch typeof obj
      when 'string' then @inColor(util.format("%j", obj), colorIndex)
      when 'number' then @inColor("0x" + obj.toString(16), colorIndex)
      when 'object'
        if obj instanceof Array
          @smooshArray(obj, colorIndex + 1)
        else
          @smooshObject(obj, colorIndex + 1)
      else @inColor(obj.toString(), colorIndex)

  smooshArray: (obj, colorIndex) ->
    first = true
    out = @inColor("[", colorIndex)
    for x in obj
      if not first then out += @inColor(",", colorIndex)
      out += @inColor(" ", colorIndex) + @smoosh(x, colorIndex)
      first = false
    out += @inColor(" ]", colorIndex)
    return out

  smooshObject: (obj, colorIndex) ->
    first = true
    out = @inColor("{", colorIndex)
    for k, v of obj
      if typeof obj[k] != 'function'
        if not first then out += @inColor(",", colorIndex)
        out += @inColor(" " + k + ": ", colorIndex) + @smoosh(v, colorIndex)
        first = false
    out + @inColor(" }", colorIndex)

smoosher = new Smoosher()
exports.smoosh = smoosher
