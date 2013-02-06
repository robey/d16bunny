
# builtin macros

BuiltinMacros = """

.macro jmp(addr) {
  set pc, addr
}

.macro hlt {
  sub pc, 1
}

.macro ret {
  set pc, pop
}

.macro bra(addr) {
.error "Illegal argument to BRA."
  add pc, addr - .next
:.next
}

"""

exports.BuiltinMacros = BuiltinMacros
