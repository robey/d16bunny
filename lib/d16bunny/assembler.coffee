
util = require 'util'

class Assembler
  Registers: { "a": 0, "b": 1, "c": 2, "x": 3, "y": 4, "z": 5, "i": 6, "j": 7 }
  RegisterNames: "ABCXYZIJ"

  Specials:
    "push": 0x18
    "pop":  0x18
    "peek": 0x19
    "pick": 0x1a
    "sp":   0x1b
    "pc":   0x1c
    "ex":   0x1d

  Reserved: (x for x of Assembler::Registers).concat(x for x of Assembler::Specials)

  constructor: ->

exports.Assembler = Assembler
