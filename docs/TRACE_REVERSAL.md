CINDER-16 TRACE AND REVERSAL
============================

THE DEBUGGER DOES NOT REPLAY HISTORY. IT INVERTS COMMITTED DATA.

WHY A TRACE EXISTS
------------------

A conventional execution log says what appeared to happen. CINDER-16 trace
entries contain the pre-values required to restore what actually changed.

That distinction is the reversibility contract:

```text
REPORT     human-readable claim
DELTA      machine-readable inverse data
```

Text output may be useful. It is not sufficient to reverse execution.

COMMIT UNIT
-----------

The unit of history is one successfully committed instruction.

```text
valid NOP       one delta
valid ADD       one delta
valid ST        one delta
valid JMP       one delta
valid HALT      one delta
invalid 0xF     zero deltas
failed load     zero deltas
```

The trace length therefore equals the number of committed instructions that
have not been reversed.

DELTA SCHEMA
------------

```text
Cinder16Delta
    pcBefore
    cyclesBefore
    haltedBefore
    instructionWord

    registerWrites[]
        index
        oldValue

    memoryWrites[]
        index
        oldValue

    pcAfter
    cyclesAfter
    haltedAfter
```

`index` identifies a register in `registerWrites` and a memory address in
`memoryWrites`.

WHY OLD VALUES ARE STORED
-------------------------

After an instruction commits, the live machine already contains the new values.
To undo the instruction, the machine needs the values that were destroyed.

For:

```text
R1 = 7
R2 = 5
ADD R1, R2
```

The live machine after execution contains:

```text
R1 = 12
```

The delta stores:

```text
registerWrites = [(R1, 7)]
```

The value `12` does not need to be duplicated in the write record. Post-state
metadata still records PC, cycle, and HALT values for inspection and hashing.

FORWARD ALGORITHM
-----------------

Conceptual pseudocode matching the implementation:

```text
step(machine):
    if machine.halted:
        fail "machine is halted"

    instruction = machine.memory[machine.pc]
    opcode = validate(instruction.opcode)

    delta = new Delta(
        pcBefore        = machine.pc,
        cyclesBefore    = machine.cycles,
        haltedBefore    = machine.halted,
        instructionWord = instruction
    )

    machine.pc = word(machine.pc + 1)

    execute instruction through write barriers

    machine.cycles += 1

    delta.pcAfter      = machine.pc
    delta.cyclesAfter  = machine.cycles
    delta.haltedAfter  = machine.halted

    machine.trace.append(delta)
    return delta
```

Opcode validation occurs before delta creation and before PC increment. An
invalid opcode cannot leave a partial delta.

REGISTER WRITE BARRIER
----------------------

```text
writeRegister(index, newValue, delta):
    oldValue = readRegister(index)
    delta.registerWrites.append(index, oldValue)
    writeRegisterRaw(index, word(newValue))
```

The raw write validates the register index and masks the value to 16 bits.

MEMORY WRITE BARRIER
--------------------

```text
writeMemory(address, newValue, delta):
    oldValue = readMemory(address)
    delta.memoryWrites.append(address, oldValue)
    writeMemoryRaw(address, word(newValue))
```

The raw write validates the address and masks the value to 16 bits.

INVERSE ALGORITHM
-----------------

Conceptual pseudocode matching `back`:

```text
back(machine):
    if machine.trace is empty:
        fail "trace history is empty"

    delta = machine.trace.pop()

    for write in reverse(delta.memoryWrites):
        writeMemoryRaw(write.index, write.oldValue)

    for write in reverse(delta.registerWrites):
        writeRegisterRaw(write.index, write.oldValue)

    machine.pc      = delta.pcBefore
    machine.cycles  = delta.cyclesBefore
    machine.halted  = delta.haltedBefore

    return delta
```

WHY REVERSE WRITE ORDER EXISTS
------------------------------

Imagine a future instruction performs two writes to the same location:

```text
initial R1 = 3
write R1 = 4     record old 3
write R1 = 5     record old 4
```

Correct inverse order:

```text
restore 4
restore 3
```

Forward-order restoration would incorrectly end at `4`. The current v0.1.0 ISA
usually records at most one register or memory write per instruction, but the
algorithm preserves the stronger rule.

PC, CYCLE, AND HALT
-------------------

These fields are restored directly from pre-state metadata. They do not use
write records.

This matters for control flow and HALT:

```text
JMP    changes PC without a register or memory write
JZ     may replace the normal incremented PC
HALT   changes halted from false to true
NOP    changes PC and cycles even with no data write
```

Every one of these instructions remains reversible because PC, cycles, and HALT
exist in the delta.

WORKED EXAMPLE: HALT
--------------------

Before:

```text
PC       0x0003
CYCLES   3
HALTED   false
MEM[3]   0xE000
```

After `step`:

```text
PC       0x0004
CYCLES   4
HALTED   true
```

Delta:

```text
pcBefore        0x0003
cyclesBefore    3
haltedBefore    false
instructionWord 0xE000
registerWrites  []
memoryWrites    []
pcAfter         0x0004
cyclesAfter     4
haltedAfter     true
```

After `back`:

```text
PC       0x0003
CYCLES   3
HALTED   false
```

The machine can execute HALT again.

WORKED EXAMPLE: STORE
---------------------

Before:

```text
PC         0x0002
R1         0x0064
R2         0x004D
MEM[0064]  0x0000
MEM[0002]  0x6280    ; ST [R1], R2
```

After:

```text
PC         0x0003
MEM[0064]  0x004D
```

Delta write content:

```text
memoryWrites = [(0x0064, 0x0000)]
```

After `back`:

```text
PC         0x0002
MEM[0064]  0x0000
```

LOADING IS OUTSIDE TRACE
------------------------

`loadWords`, raw loading, and hex loading use raw memory writes. They do not
append instruction deltas.

Therefore:

```text
load program
execute one instruction
back
```

restores machine state to immediately after loading, not to zero memory before
loading.

This is intentional. Image loading is a host operation, not an emulated CPU
instruction.

FAILED OPERATIONS
-----------------

Operations that fail before commit create no trace entry:

```text
opcode 0xF
step while halted
back with empty history
invalid register index
invalid memory address
malformed image
oversized image
failed debugger load
```

Machine-level run budget exhaustion is different. Instructions executed before
the budget expires are committed and remain in the trace.

DEBUGGER BREAKPOINTS
--------------------

Breakpoints are checked before executing the instruction at the current PC.
Stopping at a breakpoint does not create a delta.

```text
PC = 0x0010
breakpoint = 0x0010
run
```

Result:

```text
executed steps = 0
PC remains 0x0010
trace unchanged
```

DEBUGGER WATCHPOINTS
--------------------

Watchpoints are checked after each committed instruction. A watchpoint stores a
baseline value outside architectural state.

```text
record.address
record.value
```

After a memory change:

```text
current != record.value
```

The debugger reports the transition, updates the baseline, and stops.

After reverse execution, all watchpoint baselines are refreshed from restored
memory. This prevents `back` from being reported as a forward watchpoint event.

TRACE DISPLAY
-------------

The debugger's compact trace line is:

```text
PC_BEFORE INSTRUCTION -> PC_AFTER cycle=N regWrites=N memWrites=N
```

Example:

```text
0x0002 0x3280 -> 0x0003 cycle=3 regWrites=1 memWrites=0
```

This display intentionally omits old values. The full in-memory delta still owns
them. Display output is not the reversal database.

TRACE HASH
----------

`Cinder16TraceHasher` computes a deterministic 16-bit digest.

Initial value:

```text
0x811C
```

Mix function:

```text
mix(hash, value) = ((hash XOR word(value)) * 257) & 0xFFFF
```

Input order:

```text
trace size

for each delta in chronological order:
    pcBefore
    cyclesBefore
    haltedBefore as 0 or 1
    instructionWord
    pcAfter
    cyclesAfter
    haltedAfter as 0 or 1
    registerWrites size
    each register write:
        index
        oldValue
    memoryWrites size
    each memory write:
        index
        oldValue
```

The hash covers recorded trace content, not the complete live machine state.

WHAT THE HASH PROVES
--------------------

Useful claim:

```text
Two equal deterministic executions should produce equal trace hashes.
```

Invalid claim:

```text
Two equal 16-bit hashes prove the executions were identical.
```

The output space contains only 65,536 values. Collisions are unavoidable. The
hash is for regression and conformance detection, not identity, security,
authentication, or tamper resistance.

FULL SNAPSHOT
-------------

`Cinder16Snapshot capture(machine)` copies:

```text
pc
cycles
halted
trace size
8 registers
65,536 memory words
```

`equalsMachine` compares every copied element against the live machine.

This is stronger than a checksum. It is also more expensive.

```text
CAPTURE COST    proportional to 65,536 memory words
COMPARE COST    up to 65,536 memory comparisons plus registers and metadata
```

The v0.1.0 conformance test uses direct snapshot equality to verify:

```text
capture initial state
run finite program to HALT
assert state changed
back until trace empty
assert exact equality with initial snapshot
```

DETERMINISM CONTRACT
--------------------

For equal initial architectural state and equal memory image, execution is
expected to produce equal:

```text
register values
memory values
PC sequence
cycle count
HALT state
trace fields
trace hash
```

There are no timers, random sources, devices, interrupts, networking, or host I/O
inside the ISA.

Debugger metadata can change when a run stops, but it is outside the machine
state and outside the trace hash.

TRACE GROWTH
------------

Trace history grows once per committed instruction.

```text
100 instructions       100 deltas
1,000,000 instructions 1,000,000 deltas
```

There is no history cap, ring buffer, checkpoint compaction, or spill-to-disk in
v0.1.0. Long-running workloads can consume substantial host memory.

A future history policy must be explicit. Silent trace deletion would break the
promise that `back` can reach every retained committed step.

REVERSAL LIMITS
---------------

`back` cannot undo:

```text
program loading
machine reset
debugger breakpoint changes
debugger watchpoint changes
replacement of the active machine after successful debugger load
host-side file changes
```

It can undo committed instruction effects represented by the newest delta.

ADVERSARIAL QUESTIONS
---------------------

```text
Q: Can invalid opcode increment PC before failing?
A: No. Validation occurs before PC mutation and delta creation.

Q: Can malformed image partially overwrite memory?
A: No. Parsing completes before commit and bounds validation precedes writes.

Q: Can a breakpoint execute the instruction before stopping?
A: No. Breakpoint check occurs before step.

Q: Can a watchpoint stop before the write commits?
A: No. Watchpoint comparison occurs after step.

Q: Can back restore a value without bounds checking?
A: Raw restore writes still validate register or memory indices.

Q: Does trace hash replace direct state equality?
A: No. The snapshot test compares every memory and register value.

Q: Does reversing HALT remove its delta?
A: Yes. HALT becomes false, PC and cycles restore, and the HALT delta is popped.

Q: Can loading be reversed with back?
A: No. Loading is outside instruction history.
```

CONFORMANCE RECIPE
------------------

When modifying execution or reversal:

```text
1. Create a machine with known memory and registers.
2. Capture a full snapshot.
3. Execute the smallest program covering the change.
4. Inspect exact deltas, not only final output.
5. Reverse until trace is empty.
6. Compare direct full state against the snapshot.
7. Repeat the run and compare trace hashes.
8. Run all committed tests in real Io processes.
```

A source file containing tests is not evidence that the tests ran.

RELATED DOCUMENTS
-----------------

```text
docs/DEEP_DIVE.md      complete machine lifecycle
docs/PROGRAMMING.md    machine-code examples
docs/ARCHITECTURE.md   formal invariants
docs/DEBUGGER.md       stop and command contract
src/Cinder16.io        forward and inverse implementation
src/Debugger.io        trace hash, snapshot, debugger observation
```
