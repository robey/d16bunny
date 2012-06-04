
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
  prefixed by "0x", or label names.

these common extensions are also supported:

- operands can be arbitrarily nested expressions using the standard operators
  +, -, *, /, %, <<, >>, &, ^, and |, with their standard C precedenc, and ()
  for precedence grouping. operand expressions must evaluate to constants at
  compile-time, but they can use forward references.
- "JMP expr", "RET", and "BRK" are aliases for "SET PC, expr", "SET PC, POP",
  and "SUB PC, 1" respectively.
- the current (compiling) PC can be set with "ORG addr".
- constants can be defined with "name = expr", or with "#define name expr".
- the "DAT" instruction accepts words, characters using 'c', "fat" strings
  (one word per character) using "string", and packed strings (one half-word
  per character, big-endian) using p"string".

there are also some "fancy" new additions:

- "BRA addr" will perform a short (one-word) relative jump using "ADD PC, n"
  or "SUB PC, n". it will log an error if the address is too far away.
- the special label "." can always be used to refer to the PC of the current
  line being compiled.
- macros can be defined using the deNULL syntax, which looks like this:

      #macro swap(r1, r2) {
        set push, r1
        set r1, r2
        set r2, pop
      }

- macro calls perform text substitution, and look like function calls:

      swap(x, y)

inside character and string data, the following escapes are supported:

    \n    linefeed (0x000a)
    \r    return (0x000d)
    \t    tab (0x0009)
    \z    null (0x0000)
    \xNN  any single half-word (0x0000 - 0x00ff)
