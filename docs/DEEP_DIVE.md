CINDER-16 DEEP DIVE
===================

READ THIS WHEN THE README IS NOT ENOUGH.

PURPOSE
-------

CINDER-16 is a compact 16-bit virtual machine written in Io. Its design is built
around one rule:

```text
STATE CHANGES ARE DATA.
```

Execution is not treated as an irreversible side effect. Every committed
instruction records enough pre-state to undo itself exactly. The debugger does
not guess, replay, or reconstruct history from text. It applies inverse data.

This document explains the machine from image input to reverse execution. It is
written against the v0.1.0 source, not against an imagined future design.

MACHINE AT A GLANCE
-------------------

```text
WORD WIDTH       16 bits
ADDRESS SPACE    65,536 words
REGISTERS        R0..R7, all writable
PC               16-bit, wraps through word masking
CYCLES           monotonically increasing integer during forward execution
HALTED           boolean
INSTRUCTION      one 16-bit word
TRACE ENTRY      one delta per committed instruction
MEMORY MODEL     word-addressed, checked, zero-initialized
```

There are fifteen valid opcodes, `0x0` through `0xE`. Opcode `0xF` is an explicit
invalid instruction and traps before architectural mutation.

WHAT COUNTS AS ARCHITECTURAL STATE
----------------------------------

The machine object owns:

```text
memory[65536]
registers[8]
pc
cycles
halted
trace[]
```

The current debugger also owns breakpoints and watchpoints, but those are not
architectural state. They control observation and stopping. They do not belong
to the emulated CPU and are not stored in instruction deltas.

CONSTRUCTION
------------

`Cinder16Machine new` clones the prototype and allocates fresh mutable lists.
Every new machine receives independent memory, registers, and trace history.

Initialization performs exactly this state reset:

```text
memory      65,536 zero words
registers   8 zero words
trace       empty
pc          0
cycles      0
halted      false
```

`reset` calls the same initialization path. It does not preserve loaded memory,
register values, or trace history.

WORD DISCIPLINE
---------------

Every register and memory write passes through:

```text
value & 0xffff
```

Therefore:

```text
0x10000  becomes 0x0000
-1       becomes 0xffff
0x1ffff  becomes 0xffff
```

Address validation is different from value wrapping. Addresses are checked and
must already be within range:

```text
0 <= address < 65536
```

An invalid address is rejected. It is never silently wrapped into memory.

ONE INSTRUCTION, EXACTLY
------------------------

`step` follows this order:

```text
1. Reject execution if HALTED is already true.
2. Fetch MEM[PC].
3. Decode and validate the opcode.
4. Create a delta containing pre-state metadata.
5. Decode RD and RS fields.
6. Set PC = word(PC + 1).
7. Execute the opcode.
8. Increment CYCLES once.
9. Finish the delta with post-state metadata.
10. Append exactly one delta to TRACE.
11. Return that delta.
```

The validation order matters. Opcode `0xF` is rejected before delta creation,
PC increment, cycle increment, register writes, memory writes, or trace append.
That is why an invalid opcode is atomic with respect to architectural state.

DECODE FIELDS
-------------

```text
opcode    (word >> 12) & 0x0f
rd        (word >>  9) & 0x07
rs        (word >>  6) & 0x07
imm9      word & 0x01ff
target12  word & 0x0fff
```

Unused low bits in register-register instructions are currently ignored. They
remain part of the instruction word stored in the trace.

WRITE BARRIERS
--------------

Architectural writes used by instructions do not call raw mutation directly.
They pass through write barriers:

```text
writeRegister(index, newValue, delta)
writeMemory(address, newValue, delta)
```

Each barrier performs:

```text
oldValue = current architectural value
append (index/address, oldValue) to the current delta
commit the masked new value
```

The delta stores old values, not new values. The new values already exist in the
live machine after the instruction commits. Reversal needs the values that were
overwritten.

Raw writes exist for initialization, loading, test setup, and inverse apply.
They validate bounds and mask values, but do not create trace records.

DELTA SHAPE
-----------

Every committed instruction owns one `Cinder16Delta`:

```text
pcBefore
cyclesBefore
haltedBefore
instructionWord
registerWrites[]
memoryWrites[]
pcAfter
cyclesAfter
haltedAfter
```

Each write record is:

```text
index
oldValue
```

For a memory record, `index` is the memory address. For a register record, it is
the register number.

A NOP still emits one delta. A branch still emits one delta. HALT still emits
one delta. The rule is based on committed instructions, not on whether a data
write occurred.

WORKED FORWARD STEP
-------------------

Suppose:

```text
PC       0x0002
CYCLES   2
R1       0x0007
R2       0x0005
MEM[2]   0x3280    ; ADD R1, R2
```

The committed result is:

```text
R1       0x000c
PC       0x0003
CYCLES   3
TRACE    previous size + 1
```

The delta contains conceptually:

```text
pcBefore        0x0002
cyclesBefore    2
haltedBefore    false
instructionWord 0x3280
registerWrites  [(1, 0x0007)]
memoryWrites    []
pcAfter         0x0003
cyclesAfter     3
haltedAfter     false
```

REVERSE STEP
------------

`back` performs the inverse operation:

```text
1. Reject if TRACE is empty.
2. Pop the newest delta.
3. Restore memory writes in reverse record order.
4. Restore register writes in reverse record order.
5. Restore PC from pcBefore.
6. Restore CYCLES from cyclesBefore.
7. Restore HALTED from haltedBefore.
8. Return the removed delta.
```

Reverse record order matters if a future instruction writes the same location
more than once. The current ISA normally performs at most one register or memory
write per instruction, but the inverse algorithm is already correct for a more
general write sequence.

Loading is not instruction execution. Program loading creates no deltas and
cannot be undone with `back`.

RUN
---

The machine-level `run(maxSteps)` repeatedly calls `step` until HALT or budget
exhaustion.

```text
DEFAULT BUDGET   100000
NEGATIVE BUDGET  hard failure
NO HALT IN TIME  execution budget exhausted
```

The debugger implements its own run loop because it must observe breakpoints and
watchpoints between instructions.

STRICT IMAGE LOADING
--------------------

The loader separates parsing from commit:

```text
bytes/text
    |
    v
parse complete image into temporary word list
    |
    v
validate start address and final range
    |
    v
commit words to memory
```

No word is written before the complete image has parsed successfully.

RAW BINARY
----------

A raw image must specify `big` or `little`. Two bytes form one word.

```text
BIG      [0x12, 0x34] -> 0x1234
LITTLE   [0x34, 0x12] -> 0x1234
```

Odd byte counts are rejected as incomplete trailing words. Values outside
`0..255` are rejected by the byte parser.

HEX TEXT
--------

Each word is exactly four hexadecimal digits. The only separators are ASCII:

```text
TAB  LF  CR  SPACE
```

Accepted:

```text
1207 1405
3280 E000
```

Rejected:

```text
123        fewer than four digits
12345      more than four digits
12G4       invalid character
0x1234     prefix is not part of the format
```

The format is intentionally narrow. A strict format is easier to verify than a
permissive parser with hidden normalization rules.

DEBUGGER OWNERSHIP
------------------

`Cinder16Debugger` owns:

```text
machine
loader
breakpoints[]
watchpoints[]
```

A debugger `load` does not mutate the active machine incrementally. It creates a
fresh candidate machine, loads the image into that candidate, and replaces the
active machine only after success. A failed load therefore preserves the active
machine.

A successful debugger load clears breakpoints and watchpoints because they refer
to the previous machine instance.

STOP ORDER
----------

Debugger `run` observes conditions in this order:

```text
1. BREAKPOINT at current PC, before instruction execution.
2. Execute one instruction.
3. WATCHPOINT change, after committed memory mutation.
4. HALT after the loop observes halted state.
5. BUDGET when no earlier stop condition fired.
```

A breakpoint at address `A` leaves `PC == A` and executes zero instructions at
that address.

A watchpoint stores the last observed value for one memory address. After each
committed instruction, the debugger compares current memory against that stored
value. A difference stops the run and updates the watchpoint baseline.

After `back`, watchpoint baselines are refreshed to restored memory. Reverse
execution does not generate a fake forward watch event.

DISPLAY COMMANDS
----------------

`regs`, `mem`, `disasm`, and `trace` are observational. They do not mutate the
machine.

Memory and disassembly ranges:

```text
count must be positive
count must not exceed 256
address + count must not exceed 65536
```

Numbers accepted by the debugger are unsigned decimal or `0x`-prefixed
hexadecimal. Negative numbers, signs, and other prefixes are rejected.

The command parser splits on whitespace. File paths containing spaces cannot be
represented by the v0.1.0 command grammar.

TRACE HASH
----------

The trace hasher produces a deterministic 16-bit digest over trace content. It
mixes trace length, metadata, and every recorded old value in a fixed order.

It is a conformance aid, not a cryptographic hash. Collisions are possible and
expected in a 16-bit output space. Equal executions should produce equal hashes;
an equal hash alone does not prove equal execution.

FULL SNAPSHOT
-------------

`Cinder16Snapshot` copies:

```text
PC
CYCLES
HALTED
TRACE SIZE
all 8 registers
all 65,536 memory words
```

Equality compares every value directly. It does not use the trace hash. This is
the strong verification path used to prove that forward execution followed by
complete reversal restores exact initial architectural state.

FAILURE BOUNDARIES
------------------

```text
FAILURE                              EXPECTED MUTATION
invalid register index               none
invalid memory address               none
opcode 0xF                           none
odd raw byte count                   none
unknown byte order                   none
malformed hex image                  none
oversized image                      none
failed debugger load                 active machine preserved
step after HALT                      none
back with empty trace                none
run budget exhaustion                committed prior steps remain
```

Budget exhaustion is not transactional. Every instruction executed before the
budget expires remains committed and reversible.

DEFINED ABSENCES
----------------

CINDER-16 v0.1.0 has no DIV opcode. Divide-by-zero is therefore not
representable in the ISA.

It also has no architectural stack pointer and no PUSH, POP, CALL, or RET.
Software may treat an ordinary register as a stack pointer and ordinary checked
memory as stack storage. Address checks still apply. There is no hidden wrapping
stack policy.

COST MODEL
----------

The implementation favors clarity over compression:

```text
machine memory      65,536 Io list elements
trace history       grows with committed instructions
full snapshot       copies all memory and registers
reverse one step    proportional to writes in one delta
trace hash          proportional to complete trace length
```

There is no trace eviction, checkpoint compression, JIT, sparse memory, or
snapshot deduplication in v0.1.0.

TRUST MODEL
-----------

The project makes a narrow claim:

```text
The observed v0.1.0 test suite passed 120 assertions in three real Io processes
on Windows / MinGW GCC 16.1.0 with the pinned native Io runtime.
```

That evidence does not prove every future platform, compiler, or modification.
Run `tools/test.ps1` after changing the machine, loader, debugger, bootstrap, or
tests. A report is a claim. Process output and exit status are evidence.

READ NEXT
---------

```text
docs/PROGRAMMING.md       encode and run machine programs
docs/TRACE_REVERSAL.md    exact delta and inverse semantics
docs/ISA.md               normative instruction contract
docs/LOADER.md            normative image contract
docs/DEBUGGER.md          command contract
docs/ARCHITECTURE.md      invariants and component map
CONTRIBUTING.md           rules for changing the machine
```
