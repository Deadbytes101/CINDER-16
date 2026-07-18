CINDER-16 CHANGELOG
===================

0.1.0 - 2026-07-18
------------------

INITIAL PUBLIC RELEASE.

ADDED
-----

- Clean-room 16-bit virtual machine written in Io.
- Eight writable 16-bit registers and 65,536 word-addressed memory locations.
- Deterministic PC, cycle, HALT, and reversible trace state.
- Fifteen valid opcodes plus an atomic invalid-opcode trap.
- Strict transactional raw-binary and hexadecimal image loaders.
- Explicit big-endian and little-endian raw image support.
- Interactive reversible debugger with run, step, back, regs, mem, disasm,
  break, watch, reset, load, and trace commands.
- Deterministic trace hashing and direct full-memory snapshots.
- Local pinned Io runtime bootstrap for Windows.

VERIFIED
--------

Observed on Windows with MinGW GCC 16.1.0 and pinned native Io commit
`e5024305c07a7c05d41c0200901678fb0789e029`:

```text
PASS: 27 assertions
PASS: tests/core_test.io
PASS: 85 assertions
PASS: tests/v0_1_test.io
PASS: 8 assertions
PASS: tests/policy_test.io
CINDER-16 V0.1 TEST SUITE PASSED
```

All three Io processes returned exit code zero.

DEFINED ABSENCES
----------------

- No division opcode.
- No architectural stack.
- No GUI, JIT, network, audio, plugin system, package manager, or fake OS.

LICENSE
-------

GNU General Public License version 2.
