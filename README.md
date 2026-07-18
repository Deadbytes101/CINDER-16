CINDER-16
=========

A SMALL 16-BIT MACHINE WITH AN HONEST DEBUGGER.

STATUS
------

v0.1 implementation candidate is complete on the working branch and awaits
observed local execution of the full test suite.

The merged machine core has already produced an observed Windows / MinGW result:

```text
PASS: 27 assertions
CINDER-16 CORE TESTS PASSED
```

That result proves the core slice only. Loader, debugger, conformance, trace-hash,
and full-state reverse tests are not called passing until `tests/v0_1_test.io`
returns exit code zero on a real Io process.

CINDER-16 is a clean-room 16-bit virtual machine written in Io. It has fixed
16-bit instructions, eight writable registers, 65,536 word-addressed memory
locations, deterministic cycle accounting, strict image loading, and reversible
instruction deltas.

V0.1 SURFACE
------------

```text
CPU
    16-bit wrapping register and memory writes
    65,536-word checked address space
    deterministic PC, cycle, HALT, and trace state
    15 valid opcodes and one atomic invalid-opcode trap

LOADER
    raw binary images
    mandatory big/little byte order
    four-digit hexadecimal text images
    full-image validation before memory mutation
    no truncation and no wrapped destination ranges

DEBUGGER
    run   step   back   regs   mem   disasm
    break watch  reset  load   trace

VERIFICATION
    one vector per opcode
    0x0000 / 0x7fff / 0x8000 / 0xffff boundaries
    invalid image atomicity
    deterministic repeated-run trace hash
    exact full-memory forward/reverse restoration
```

LOCAL TEST
----------

CINDER-16 does not require GitHub Actions.

Run from the repository root:

```text
powershell -ExecutionPolicy Bypass -File tools/test.ps1
```

The runner executes two independent Io processes:

```text
tests/core_test.io
tests/v0_1_test.io
```

The first run performs a local runtime bootstrap when `io.exe` is unavailable:

```text
1. Clone Io tag 2026.04.20-native-final into .tools/.
2. Verify commit e5024305c07a7c05d41c0200901678fb0789e029.
3. Apply local Windows / modern-GCC compatibility adjustments.
4. Configure a Release build with CMake.
5. Build the static Io interpreter.
6. Copy it to .tools/bin/io.exe.
7. Execute every committed test file listed by tools/test.ps1.
```

Required host commands:

```text
git
cmake
C compiler toolchain
```

MinGW-W64 is preferred when `mingw32-make` exists. Ninja is used when available.
Otherwise CMake selects the installed default toolchain.

The bootstrap does not install packages, modify PATH, alter project source, or
use a remote runner. Generated source and binaries stay under ignored `.tools/`.

Force a clean runtime rebuild:

```text
powershell -ExecutionPolicy Bypass -File tools/test.ps1 -RebuildRuntime
```

DEBUGGER
--------

After the runtime exists:

```text
.tools/bin/io.exe tools/debug.io
```

Inside the shell:

```text
help
load hex program.hex
load raw program.bin big
regs
disasm 0 8
break 4
watch 100
run 1000
trace 16
back
```

Image and debugger contracts are defined in `docs/LOADER.md` and
`docs/DEBUGGER.md`.

LAYOUT
------

```text
docs/ISA.md              Machine instruction contract.
docs/ARCHITECTURE.md     State and reversibility design.
docs/LOADER.md           Raw and hexadecimal image contract.
docs/DEBUGGER.md         Command and stop-condition contract.
src/Cinder16.io          Machine core.
src/Loader.io            Strict transactional image loader.
src/Debugger.io          Disassembler, debugger, trace hash, snapshot.
tests/core_test.io       Core regression tests.
tests/v0_1_test.io       Loader/debugger/conformance verification.
tools/debug.io           Local debugger REPL.
tools/bootstrap-io.ps1   Pinned local Io build.
tools/test.ps1           Complete local verification entry point.
LICENSE                  GNU GPL version 2.
```

DEFINED ABSENCES
----------------

CINDER-16 v0.1 has no division opcode and no architectural stack. Divide-by-zero
is not representable. Software stacks use ordinary checked memory. See
`docs/ISA.md`.

NON-GOALS
---------

NO GUI.
NO JIT.
NO NETWORK.
NO AUDIO.
NO PLUGIN SYSTEM.
NO PACKAGE MANAGER.
NO FAKE OS.

LICENSE
-------

GNU General Public License version 2. See LICENSE.
