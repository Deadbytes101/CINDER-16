CINDER-16 DEBUGGER
==================

START
-----

After the local Io runtime exists:

```text
.tools/bin/io.exe tools/debug.io
```

The debugger is a command shell over one CINDER-16 machine. A command either
returns observed state or raises an explicit error. There is no hidden mutation
for display commands.

COMMANDS
--------

```text
run [budget]
step
back
regs
mem <address> [count]
disasm <address> [count]
break [address|clear]
watch [address|clear]
reset
load raw <path> <big|little> [address]
load hex <path> [address]
trace [count]
help
quit
```

Numbers are unsigned decimal or hexadecimal with a `0x` prefix.

RUN / STEP / BACK
-----------------

`step` executes exactly one valid instruction and appends exactly one delta.

`back` removes one delta and restores its register writes, memory writes, PC,
cycle count, and HALT state.

`run` stops on the first of:

```text
HALT
BREAKPOINT BEFORE EXECUTION
WATCHPOINT AFTER MEMORY CHANGE
BUDGET EXHAUSTION
```

A breakpoint at the current PC stops before executing that instruction. Use
`step` to move past it intentionally.

BREAKPOINTS
-----------

```text
break             list breakpoints
break 0x0100      add one breakpoint
break clear       remove all breakpoints
```

WATCHPOINTS
-----------

```text
watch              list watched addresses and last observed values
watch 100          add one memory watchpoint
watch clear        remove all watchpoints
```

A watchpoint stops `run` after a committed instruction changes the watched
word. Reverse-step refreshes watch baselines to the restored memory state.

DISPLAY
-------

`regs` prints R0 through R7, PC, cycle count, and HALT state.

`mem` and `disasm` reject zero counts, counts above 256, and ranges crossing the
end of memory. They never wrap display ranges.

`trace` prints committed deltas in chronological order, limited to the newest
requested entries.

LOAD / RESET
------------

A successful `load` replaces the debugger machine with a fresh machine and
clears breakpoints and watchpoints. A failed load preserves the old machine
object and all of its state.

`reset` resets the current machine to zeroed memory, zeroed registers, PC zero,
zero cycles, HALT false, and empty trace. Watchpoint addresses remain and their
baseline values are refreshed.

TRACE HASH
----------

`Cinder16TraceHasher hash(machine)` computes a deterministic 16-bit digest over
all committed delta fields and every recorded old register or memory value. It
is a conformance signal, not a cryptographic hash.
