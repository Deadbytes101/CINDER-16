CINDER-16 v0.1.0
================

FIRST PUBLIC SOURCE RELEASE.

WHAT IT IS
----------

CINDER-16 is a compact clean-room 16-bit virtual machine written in Io. It has
fixed-width instructions, deterministic execution, strict image loading, and a
reversible debugger that restores exact prior architectural state.

GET THE SOURCE
--------------

```text
git clone https://github.com/Deadbytes101/CINDER-16.git
cd CINDER-16
```

VERIFY
------

From PowerShell:

```text
powershell -ExecutionPolicy Bypass -File tools/test.ps1
```

The first run builds the pinned native Io runtime locally under `.tools/` when
`io.exe` is unavailable. It does not install packages or modify system PATH.

EXPECTED RESULT
---------------

```text
PASS: 27 assertions
PASS: tests/core_test.io
PASS: 85 assertions
PASS: tests/v0_1_test.io
PASS: 8 assertions
PASS: tests/policy_test.io
CINDER-16 V0.1 TEST SUITE PASSED
```

RUN THE DEBUGGER
----------------

```text
.tools/bin/io.exe tools/debug.io
```

Example commands:

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

IMAGE FORMATS
-------------

```text
RAW BINARY   two bytes per word; explicit big or little byte order
HEX TEXT     exactly four hexadecimal digits per word; ASCII whitespace only
```

Invalid or oversized images are rejected before machine memory is mutated.

RELEASE SCOPE
-------------

```text
CPU          COMPLETE
LOADER       COMPLETE
DEBUGGER     COMPLETE
REVERSAL     VERIFIED
CONFORMANCE  VERIFIED
```

This is a source release. No prebuilt runtime binary is bundled.

LICENSE
-------

GNU General Public License version 2. See `LICENSE`.
