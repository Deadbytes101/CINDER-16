CINDER-16 ARCHITECTURE
======================

DESIGN RULE
-----------

STATE CHANGES ARE DATA.

The executor never relies on a textual log to reverse execution. Every
architectural mutation is performed through a write barrier that stores the
previous value in the current instruction delta before committing the new
value.

SYSTEM PATH
-----------

```text
IMAGE BYTES / HEX TEXT
        |
        v
STRICT PARSER
        |
        v
FULL IMAGE VALIDATION
        |
        v
ATOMIC WORD LOAD --------------------------+
        |                                   |
        v                                   |
64K WORD MEMORY                             |
        |                                   |
        v                                   |
FETCH -> DECODE -> EXECUTE                  |
                    |                       |
          +---------+----------+            |
          |         |          |            |
          v         v          v            |
       REG WRITE  MEM WRITE  PC/CYCLE/HALT  |
          |         |          |            |
          +---------+----------+            |
                    |                       |
                    v                       |
             INSTRUCTION DELTA              |
                    |                       |
                    v                       |
              TRACE HISTORY                 |
                 /      \                    |
                v        v                   |
             REVERSE   TRACE HASH            |
                                           |
DEBUGGER -----------------------------------+
  run / step / back / regs / mem / disasm
  break / watch / reset / load / trace
```

INVARIANTS
----------

```text
I1   Every register value is within 0x0000..0xffff.
I2   Every memory word is within 0x0000..0xffff.
I3   PC is within 0x0000..0xffff.
I4   A valid step appends exactly one delta.
I5   An invalid step appends no delta and changes no architectural state.
I6   Reverse-step removes exactly one delta.
I7   Step followed by reverse-step restores exact pre-state.
I8   Program loading is not instruction execution and produces no trace.
I9   Image parsing completes before the first load write.
I10  Failed debugger loads preserve the active machine object.
I11  Display commands do not mutate machine state.
I12  Equal executions produce equal trace hashes.
```

OBJECT MODEL
------------

`Cinder16Machine new` creates independent mutable state. Lists are allocated
during initialization instead of being stored as mutable objects on the shared
prototype.

`Cinder16Delta` contains only the state required to invert one instruction.
Register and memory write records contain an index/address and the value that
existed before the write.

`Cinder16Loader` converts raw bytes or strict hexadecimal text into a temporary
word list. Only a complete valid list is passed to `loadWords`.

`Cinder16Debugger` owns one active machine plus debugger-only breakpoint and
watchpoint state. A file load is performed against a fresh candidate machine.
The active machine is replaced only after successful parse and load.

`Cinder16Snapshot` copies every architectural field, all eight registers, and
all 65,536 memory words. Its equality operation performs direct value
comparison; it does not rely on a checksum.

`Cinder16TraceHasher` emits a deterministic 16-bit conformance digest over every
committed delta field and recorded old value. It is not a security primitive.

FAILURE MODEL
-------------

The following are hard failures:

```text
invalid register index
invalid memory address
wrapped display range
unknown raw byte order
odd raw byte count
malformed hexadecimal word
invalid hexadecimal character
missing image file
oversized program image
execution after HALT
execution budget exhausted
reverse-step with empty history
opcode 0xF
unknown debugger command
```

Loader failures occur before machine mutation. Invalid opcodes occur before PC,
cycle, register, memory, or trace mutation. Debugger command errors are returned
to the REPL without terminating the session.

STOP MODEL
----------

Debugger `run` stops on the first observed condition:

```text
HALT
BREAKPOINT BEFORE EXECUTION
WATCHPOINT AFTER COMMITTED MEMORY CHANGE
BUDGET EXHAUSTION
```

Breakpoints and watchpoints are debugger metadata and are not architectural
state. Reverse execution changes only machine state and refreshes watchpoint
baselines to the restored values.

TEST STRATEGY
-------------

```text
CORE REGRESSION
    word wrapping
    arithmetic and HALT
    memory store/load
    conditional branch
    reverse register and memory writes
    invalid opcode atomicity
    execution budget failure

V0.1 CONFORMANCE
    raw big-endian and little-endian loading
    strict hexadecimal loading
    malformed-image atomicity
    file-backed image loading
    one vector for every opcode 0x0..0xF
    0x0000 / 0x7fff / 0x8000 / 0xffff boundaries
    debugger command surface
    breakpoint and watchpoint stop conditions
    deterministic repeated-run trace hash
    direct full-memory forward/reverse equality
```

RUNTIME EVIDENCE
----------------

A committed test file is a claim, not runtime evidence.

The merged core has an observed `PASS: 27 assertions` result. The expanded v0.1
candidate remains UNVERIFIED until `tools/test.ps1` executes both test files and
the real Io processes return exit code zero.
