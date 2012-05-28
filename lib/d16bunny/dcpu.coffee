Dcpu =
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

  BinaryOp:
    "set": 0x01
    "add": 0x02
    "sub": 0x03
    "mul": 0x04
    "mli": 0x05
    "div": 0x06
    "dvi": 0x07
    "mod": 0x08
    "mdi": 0x09
    "and": 0x0a
    "bor": 0x0b
    "xor": 0x0c
    "shr": 0x0d
    "asr": 0x0e
    "shl": 0x0f
    "ifb": 0x10
    "ifc": 0x11
    "ife": 0x12
    "ifn": 0x13
    "ifg": 0x14
    "ifa": 0x15
    "ifl": 0x16
    "ifu": 0x17
    "adx": 0x1a
    "sbx": 0x1b
    "sti": 0x1e
    "std": 0x1f
  SpecialOp:
    "jsr": 0x01
    "hcf": 0x07
    "int": 0x08
    "iag": 0x09
    "ias": 0x0a
    "rfi": 0x0b
    "iaq": 0x0c
    "hwn": 0x10
    "hwq": 0x11
    "hwi": 0x12

Dcpu.Reserved = (x for x of Dcpu.Registers).concat(x for x of Dcpu.Specials)

Dcpu.ReservedOp = (x for x of Dcpu.BinaryOp).concat(x for x of Dcpu.SpecialOp).concat(
  [ "jmp", "brk", "ret", "bra", "dat", "org" ])

exports.Dcpu = Dcpu
