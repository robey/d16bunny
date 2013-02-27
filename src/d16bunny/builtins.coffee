
# builtin macros

BuiltinMacros = """

.define d16bunny 1

.macro jmp(addr) {
  set pc, addr
}

.macro hlt {
  sub pc, 1
}

.macro ret {
  set pc, pop
}
.macro rts {
  set pc, pop
}

.macro bra(addr) {
.onerror "Illegal argument to BRA."
  add pc, addr - .next
:.next
}
"""

exports.BuiltinMacros = BuiltinMacros
