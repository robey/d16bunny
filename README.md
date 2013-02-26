
d16bunny
========

d16bunny is an assembler for the DCPU-16, written in coffeescript, and
licensed via the apache 2 open-source license (included in the LICENSE file).

it can be built into a node library suitable for command-line tools, or a
single javascript file for inclusion in online web app. my goal is to make a
powerful assembler so all of the web-based assembler/emulators and CLI tools
can share a large feature set and reduce bugs.

the assembler engine is based on deNULL's javascript assembler, with a lot of
refactoring, and some new features. it also comes with a suite of unit tests
and integration tests.

build
-----

- "cake test" to run tests
- "cake build" to build node-style javascript
- "cake web" to build a single web-friendly javascript file
- "cake clean" to clean up

use
---

a sample CLI assembler is included. it can build 128KB DCPU-16 image files,
or "dat" files that consist of only ORG and DAT lines, suitable for pasting
into a less intelligent assembler. it responds to help:

    ./bin/d16basm --help

the library API is optimized for interactive compiling. to use it, create a
new Assembler, pass in a logger function, and call "compile" with an array of
the source lines. the logger will be used to send back warnings and errors.
each warning/error will have the line number and horizontal position (both
counting from 0) attached.

    var logger = function (lineno, pos, message) {
      // append log message to UI element here.
    }
    var asm = new d16bunny.Assembler(logger);
    var output = asm.compile(lines);

the compiled output contains an error count, and a compiled object for each
source line. the compiled object contains the current PC and the compiled
data, so you could line up the compiled output next to the source if you
want. it also has functions for packing the result into a memory image, and
doing line number to memory address lookups, and memory address to line
number lookups. check out the comment block on "compile" for the details.

the assembler will try to continue even if it hits errors, but it will stop
trying after it hits a configured maximum number of errors (usually 10).

syntax
------

the basic notch syntax is supported:

- comments start with ";" and continue to the end of the line.
- labels are always at the beginning of a line and are prefixed by ":".
  labels may contain letters, digits, "_", and ".".
- constant (immediate) values can be decimal integers, hex integers if
  prefixed by "0x", binary integers if prefixed by "0b", or label names.
- operands can be arbitrarily nested expressions using the standard operators
  +, -, *, /, %, <<, >>, &, ^, and |, with their standard C precedence, and ()
  for precedence grouping. operand expressions must evaluate to constants at
  compile-time, but they can use forward references.

supported aliases:

- "JMP expr" for "SET PC, expr"
- "RET" for "SET PC, POP"
- "HLT" for "SUB PC, 1" (which some emulators use as a hint to pause
  execution until the next interrupt)
- "BRA addr" will perform a short (one-word) relative jump using "ADD PC, n"
  or "SUB PC, n". it will log an error if the address is too far away. the
  DCPU can only jump 30 words in either direction in this form.
- the special label "." (or "$") can always be used to refer to the PC of
  the current line being compiled.

directives
==========

assembler directives start with either "#" or ".". the following directives
are supported:

- `.ORG <addr>`
  move to a new target address for compilation (for compatibility, this
  directive may also be used without the "#" or ".").

- `.EQU <name> <expr>` or `.DEFINE <name> <expr>`
  assign a constant that can be used in expressions.

- `.MACRO <name>(<args...>)`
  define a macro which can be expanded by name elsewhere. for example:

      #macro swap(r1, r2) {
        set push, r1
        set r1, r2
        set r2, pop
      }

  which may be expanded later:

      swap(x, y)

data
====

the "DAT" instruction takes a comma-separated list of expressions, evaluates
them into words, and puts them directly into the compiled output. aside from
normal expressions that can be used in any instruction, "DAT" also supports:

- ASCII characters, in single quotes: 'c' (0x0063)
- fat strings (one word per character), in double quotes: "fat" (0x0066,
  0x0061, 0x0074)
- packed strings (one byte per character, big-endian), in double quotes
  prefixed by by "p": p"fat" (0x6661, 0x7400)
- rom strings (one byte per character, big-endian, with the high bit set on
  the last byte), in double quotes prefixed by "r": r"fat" (0x6661, 0xf400)

inside character and string data, the following escapes are supported:

    \n    linefeed (0x000a)
    \r    return (0x000d)
    \t    tab (0x0009)
    \z    null (0x0000)
    \e    escape (0x001b)
    \xNN  any single half-word (0x0000 - 0x00ff)

to-do
-----

- #include "filename"
- allow "label:"
- "#align"
- "#fill"?
- "#endmacro"
- define "d16bunny" so people can test for it


thanks
------

- denis olshin (denull) wrote the original javascript assembler that i ran
  through a blender and then rewrote a few times in an OCD craze -- i
  basically learned javascript by reading his code.
- maximinus-thrax wrote the assembler validity checks that i turned ino
  integration tests because they revealed a lot of bugs.

