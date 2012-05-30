
class Smoosher
  # gray, yellow, orange, red, purple, blue, cyan, green
  colors: [ "37", "33;1", "33", "31", "35", "34", "36", "32" ]

  inColor: (s, colorIndex) ->
    colorIndex %= 8
    "\u001b[" + @colors[colorIndex] + "m" + s + "\u001b[0m"

  smoosh: (obj, colorIndex = 0) ->
    switch typeof obj
      when 'undefined' then @inColor("undefined", colorIndex)
      when 'string' then @inColor(@smooshString(obj), colorIndex)
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

  smooshString: (s) ->
    out = ""
    for i in [0 ... s.length]
      ch = s.charCodeAt(s[i])
      if ch < 32 or ch > 127
        hex = ch.toString(16)
        while hex.length < 4 then hex = "0" + hex
        out += "\\u" + hex
      else
        out += s[i]
    "\"" + out + "\""

smoosher = new Smoosher()
exports.smoosh = smoosher
