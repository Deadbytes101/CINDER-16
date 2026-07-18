CINDER-16 PROGRAMMING GUIDE
===========================

WRITE THE WORDS. LOAD THE WORDS. WATCH THE MACHINE.

SCOPE
-----

CINDER-16 v0.1.0 executes machine words directly. There is no assembler, linker,
object format, label resolver, macro system, or compiler in this release.

A program is a sequence of 16-bit words loaded into word-addressed memory. The
program counter starts at `0x0000` after reset unless a host changes it directly.
The debugger load command loads a fresh machine and leaves PC at zero.

WORD LAYOUTS
------------

Register-register form:

```text
15          12 11       9 8        6 5                     0
+-------------+-----------+----------+-----------------------+
|   OPCODE    |    RD     |    RS    |       RESERVED        |
+-------------+-----------+----------+-----------------------+
```

Immediate form:

```text
15          12 11       9 8                                0
+-------------+-----------+----------------------------------+
|   OPCODE    |    RD     |             IMM9                 |
+-------------+-----------+----------------------------------+
```

Jump form:

```text
15          12 11                                           0
+-------------+-----------------------------------------------+
|   OPCODE    |                   TARGET12                    |
+-------------+-----------------------------------------------+
```

ENCODING FORMULAS
-----------------

```text
RR(op, rd, rs) = ((op & 0xF) << 12)
               | ((rd & 0x7) << 9)
               | ((rs & 0x7) << 6)

LDI(rd, imm)   = 0x1000
               | ((rd & 0x7) << 9)
               | (imm & 0x1FF)

JZ(rd, target) = 0x8000
               | ((rd & 0x7) << 9)
               | (target & 0x1FF)

JMP(target)    = 0x7000 | (target & 0xFFF)
```

The formulas mask fields. The machine decoder also masks fields. Do not use that
as permission to pass out-of-range operands silently in tools. A future assembler
should reject invalid source operands instead of truncating them.

OPCODE QUICK MAP
----------------

```text
0x0  NOP                 no data write
0x1  LDI  RD, IMM9       RD = IMM9
0x2  MOV  RD, RS         RD = RS
0x3  ADD  RD, RS         RD = word(RD + RS)
0x4  SUB  RD, RS         RD = word(RD - RS)
0x5  LD   RD, [RS]       RD = MEM[RS]
0x6  ST   [RD], RS       MEM[RD] = RS
0x7  JMP  TARGET12       PC = TARGET12
0x8  JZ   RD, TARGET9    if RD == 0, PC = TARGET9
0x9  AND  RD, RS         RD = RD & RS
0xA  OR   RD, RS         RD = RD | RS
0xB  XOR  RD, RS         RD = RD ^ RS
0xC  SHL  RD, RS         RD = word(RD << (RS & 0xF))
0xD  SHR  RD, RS         RD = RD >> (RS & 0xF)
0xE  HALT                HALTED = true
0xF  INVALID             trap before architectural mutation
```

IMMEDIATE LIMITS
----------------

```text
LDI IMM9       0x000..0x1FF
JZ TARGET9     0x000..0x1FF
JMP TARGET12   0x000..0xFFF
```

The machine has a 16-bit PC, but direct jump instructions cannot encode every
16-bit address. Indirect jump instructions do not exist in v0.1.0.

HEX IMAGE FORMAT
----------------

A hexadecimal text image contains exactly four hex digits per word.

Accepted separators:

```text
SPACE  TAB  LF  CR
```

Example:

```text
1207 1405
3280 E000
```

The following are not accepted:

```text
0x1207       prefixes are forbidden
120          short word
12070        long word
12_07        punctuation is forbidden
; comment    comments are not part of the format
```

The format contains words, not bytes. Byte order does not apply to hex text.

RAW IMAGE FORMAT
----------------

A raw image contains exactly two bytes per word. The loader requires explicit
byte order.

For word `0x1234`:

```text
BIG-ENDIAN     12 34
LITTLE-ENDIAN  34 12
```

An odd number of bytes is invalid. The loader never discards a trailing byte.

LOAD WITH THE DEBUGGER
----------------------

```text
load hex program.hex
load hex program.hex 0x0100
load raw program.bin big
load raw program.bin little 256
```

A successful load replaces the active machine with a fresh loaded machine and
clears breakpoints and watchpoints.

A failed load preserves the previous active machine.

The v0.1.0 command parser splits on whitespace. Paths containing spaces are not
representable. Keep image paths simple or run the repository from a path whose
relevant image filenames contain no spaces.

EXAMPLE 1: ADD TWO CONSTANTS
----------------------------

Source intent:

```text
LDI  R1, 7
LDI  R2, 5
ADD  R1, R2
HALT
```

Manual encoding:

```text
ADDRESS  WORD    DECODE
0000     1207    LDI R1, 0x0007
0001     1405    LDI R2, 0x0005
0002     3280    ADD R1, R2
0003     E000    HALT
```

Create `add.hex`:

```text
1207
1405
3280
E000
```

Debugger session:

```text
load hex add.hex
disasm 0 4
run 16
regs
trace 8
```

Expected important state:

```text
R1       0x000C
R2       0x0005
PC       0x0004
CYCLES   4
HALTED   yes
TRACE    4 committed deltas
```

Reverse the complete execution:

```text
back
back
back
back
regs
```

Expected restored state:

```text
R0..R7   all zero
PC       0x0000
CYCLES   0
HALTED   no
TRACE    empty
```

The loaded program words remain in memory because loading is not part of
instruction history.

EXAMPLE 2: STORE THEN LOAD
--------------------------

Source intent:

```text
LDI  R1, 100
LDI  R2, 77
ST   [R1], R2
LDI  R2, 0
LD   R2, [R1]
HALT
```

Encoded image:

```text
1264    ; LDI R1, 100
144D    ; LDI R2, 77
6280    ; ST [R1], R2
1400    ; LDI R2, 0
5440    ; LD R2, [R1]
E000    ; HALT
```

Comments above explain the words; remove comments from the actual `.hex` file:

```text
1264
144D
6280
1400
5440
E000
```

Observe the memory write:

```text
load hex store_load.hex
watch 100
run 32
mem 100
regs
```

Expected first stop:

```text
RUN steps=3 PC=0x0003 WATCH 0x0064 0x0000->0x004D
```

Continue:

```text
run 32
```

Expected final data:

```text
MEM[100]  0x004D
R2        0x004D
HALTED    yes
```

EXAMPLE 3: CONDITIONAL BRANCH
-----------------------------

Source intent:

```text
LDI  R0, 0
JZ   R0, 4
LDI  R1, 1
JMP  5
LDI  R1, 9
HALT
```

Encoded image:

```text
1000
8004
1201
7005
1209
E000
```

Execution path:

```text
PC 0  LDI R0, 0
PC 1  JZ R0, 4      taken
PC 4  LDI R1, 9
PC 5  HALT
```

Expected result:

```text
R1       0x0009
CYCLES   4
TRACE    4 entries
```

BREAKPOINTS
-----------

A breakpoint stops before execution at the matching PC.

```text
load hex add.hex
break 2
run 16
```

Expected result:

```text
RUN steps=2 PC=0x0002 BREAK 0x0002
```

The ADD at address 2 has not executed yet. Use `step` to execute it, or `back` to
undo address 1.

WATCHPOINTS
-----------

A watchpoint observes one memory word after each committed instruction.

```text
watch 100
watch
watch clear
```

A watchpoint does not watch register values. Register watchpoints do not exist in
v0.1.0.

MEMORY INSPECTION
-----------------

```text
mem 0
mem 0 8
mem 0x0064 4
```

The count must be between 1 and 256. The range must not cross address `0xFFFF`.

DISASSEMBLY
-----------

```text
disasm 0 8
```

Output contains address, raw word, and decoded instruction:

```text
0x0000: 0x1207  LDI R1, 0x0007
```

The disassembler decodes any 16-bit word. It prints opcode `0xF` as `INVALID`.
It does not validate reserved bits or prove that control flow will reach the
word.

TRACE INSPECTION
----------------

```text
trace
trace 32
```

Each line reports:

```text
PC_BEFORE  INSTRUCTION -> PC_AFTER cycle=N regWrites=N memWrites=N
```

This is a compact observation format. The in-memory delta contains more detail,
including old values and HALT state.

SOFTWARE STACKS
---------------

There is no architectural stack. A program may choose a register as a software
stack pointer and use `ST` and `LD` with ordinary memory.

Example convention:

```text
R7 = stack pointer
stack grows downward
```

But v0.1.0 lacks immediate decrement larger than what the available instruction
sequence can construct, lacks CALL/RET, and offers no hidden stack checks. Every
actual memory access is checked by the normal memory API. This is a convention,
not an ISA feature.

COMMON ENCODING ERRORS
----------------------

```text
ERROR                              RESULT
using byte addresses               wrong location; memory is word-addressed
writing 0x prefix in hex image     parser rejection
forgetting raw byte order          debugger usage error
odd raw byte count                 parser rejection
JZ target above 0x1FF              field cannot represent it
JMP target above 0xFFF             field cannot represent it
assuming R0 is constant zero       wrong; R0 is writable
assuming arithmetic flags          wrong; no flags register exists
assuming signed SHR                wrong; values are non-negative 16-bit words
using path with spaces             command parser splits the path
expecting load to be reversible    wrong; load creates no trace entries
```

PROGRAM DESIGN RULES
--------------------

```text
1. Treat every memory address as a word address.
2. Budget loops; no automatic watchdog exists inside the ISA.
3. End intended finite programs with HALT.
4. Use explicit memory locations and document register conventions.
5. Verify branch targets against immediate width.
6. Keep image generation deterministic.
7. Disassemble the loaded image before trusting it.
8. Use trace and back to prove state transitions, not to decorate output.
```

MINIMAL VERIFY LOOP
-------------------

For every hand-written program:

```text
load image
disasm complete image
set break/watch conditions
run with finite budget
inspect regs and memory
inspect trace
back to initial state when reversibility matters
```

RELATED DOCUMENTS
-----------------

```text
docs/ISA.md               normative opcode behavior
docs/LOADER.md            normative image parser behavior
docs/DEBUGGER.md          normative command grammar
docs/TRACE_REVERSAL.md    delta and inverse details
docs/DEEP_DIVE.md         complete system path
```
