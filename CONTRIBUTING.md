CONTRIBUTING TO CINDER-16
========================

CHANGE THE MACHINE WITHOUT LYING ABOUT THE MACHINE.

WORKING DOCTRINE
----------------

```text
CLASSIFY
DEFINE DONE
EVIDENCE
INTENT
ONE DECISION
SURGICAL CHANGE
OBSERVED VERIFY
ADVERSARIAL JUDGE
OUTCOME-FIRST REPORT
```

Reports are claims, not evidence.

A green-looking document is not a test result. A committed test is not a test
result. A plausible code review is not a test result. The real Io process must
execute the relevant suite and return success.

SCOPE OF V0.1.0
---------------

CINDER-16 v0.1.0 intentionally contains:

```text
16-bit word machine
65,536-word checked memory
8 writable registers
15 valid opcodes
one atomic invalid opcode
strict raw and hex loaders
reversible instruction deltas
local debugger
local test runner
```

It intentionally does not contain:

```text
GUI
JIT
networking
audio
devices
interrupts
plugins
package manager
assembler
compiler
architectural stack
division opcode
```

Do not smuggle a non-goal into a small unrelated patch.

BEFORE WRITING CODE
-------------------

Classify the requested change:

```text
CORE EXECUTION
ISA CONTRACT
LOADER
DEBUGGER
REVERSAL
TRACE / SNAPSHOT
BOOTSTRAP / TOOLCHAIN
TESTS
DOCUMENTATION
```

Then define the observable done condition.

Bad:

```text
Improve tracing.
```

Good:

```text
For one committed instruction, include field X in the in-memory delta, include
it in the trace hash in a documented order, reverse it exactly, and add an
observed conformance test that fails without the change.
```

BASELINE
--------

From the repository root on Windows:

```text
powershell -ExecutionPolicy Bypass -File tools/test.ps1
```

Expected release evidence:

```text
PASS: 27 assertions
PASS: tests/core_test.io
PASS: 85 assertions
PASS: tests/v0_1_test.io
PASS: 8 assertions
PASS: tests/policy_test.io
CINDER-16 V0.1 TEST SUITE PASSED
```

The exact assertion counts may legitimately change when tests are added or
removed. The process must still execute every file listed by `tools/test.ps1`
and return exit code zero.

GitHub Actions is not part of this repository's verification contract. Do not
add a workflow merely to make the project look automated.

CORE INVARIANTS
---------------

A core change must preserve or explicitly revise these contracts:

```text
I1   register values remain within 0x0000..0xFFFF
I2   memory values remain within 0x0000..0xFFFF
I3   invalid addresses are rejected, not wrapped
I4   one valid committed instruction appends one delta
I5   invalid opcode changes no architectural state
I6   back removes one delta and restores exact pre-state
I7   loading produces no instruction trace
I8   equal initial state and program produce deterministic execution
```

If an invariant changes, update code, tests, ISA documentation, architecture
documentation, debugger behavior where applicable, and release notes for the
next release.

MUTATION RULE
-------------

Validation must happen before mutation whenever the operation claims atomic
failure.

```text
validate complete request
build temporary representation
validate final bounds
commit mutation
```

This rule is already used by image loading and debugger machine replacement.

Do not write one word, discover an error, and then attempt to repair the damage.
Rollback logic is more complex than refusing to begin a bad commit.

ADDING OR CHANGING AN OPCODE
----------------------------

One opcode change touches more than `step`.

Required review path:

```text
1. Define binary encoding in docs/ISA.md.
2. Define exact reads, writes, PC behavior, cycle cost, and failure behavior.
3. Implement decode/execute in src/Cinder16.io.
4. Route architectural writes through delta-aware barriers.
5. Update disassembly in src/Debugger.io.
6. Add one direct conformance vector.
7. Add boundary vectors for arithmetic or address behavior.
8. Prove invalid or failing cases are atomic where claimed.
9. Prove forward then reverse restores exact state.
10. Consider trace-hash input compatibility.
11. Run the complete suite in real Io processes.
```

Do not allocate an opcode before its semantics are written.

Do not reuse opcode `0xF` casually. It is the explicit invalid-instruction trap
used by atomicity tests and documentation.

WRITE BARRIERS
--------------

Instruction implementations must not bypass:

```text
writeRegister(index, value, delta)
writeMemory(address, value, delta)
```

unless the operation is intentionally outside instruction history.

Raw writes are for:

```text
initialization
program loading
host-side test setup
inverse restoration
```

A new instruction using raw writes will appear to work forward and then fail to
reverse correctly.

PC AND CYCLE DISCIPLINE
-----------------------

The current valid instruction contract is:

```text
PC advances or branches exactly once per committed instruction
CYCLES increments exactly once per committed instruction
```

If variable cycle cost is introduced later, it must be a deliberate ISA change,
not an accidental side effect.

Invalid opcode validation must remain before PC, cycle, trace, register, memory,
or HALT mutation.

LOADER CHANGES
--------------

The loader contract is intentionally strict.

Raw image rules:

```text
explicit big or little byte order
exactly two bytes per word
no trailing byte truncation
all bytes within 0..255
```

Hex image rules:

```text
exactly four hex digits per word
ASCII TAB/LF/CR/SPACE separators only
no 0x prefix
no comments
no punctuation
```

Required loader tests:

```text
valid empty image where supported
valid single word
valid multiple words
both raw byte orders
odd byte count
invalid byte value
short hex word
long hex word
invalid character
missing file
start address boundary
exact-fit final range
one-word overflow
failure preserves existing machine memory
```

Do not add permissive syntax without documenting why ambiguity is worth the
additional parser surface.

DEBUGGER CHANGES
----------------

The debugger is an observation and control layer. It must not quietly redefine
CPU behavior.

Command changes require:

```text
exact grammar
argument bounds
success output
failure output
mutation classification
interaction with breakpoints/watchpoints
interaction with reverse execution
tests
updated docs/DEBUGGER.md
```

Display commands should remain non-mutating.

Current stop order is:

```text
breakpoint before execution
watchpoint after committed memory change
HALT
budget
```

Changing stop order changes observable debugging semantics and requires explicit
tests.

Debugger `load` currently uses a fresh candidate machine. Preserve that atomic
replacement model unless a new transactional design is proven stronger.

REVERSAL CHANGES
----------------

Every new architectural mutation needs inverse data.

Ask:

```text
What exact old value is destroyed?
Can the same location be written more than once in one instruction?
Does reverse order matter?
Does PC change outside normal increment?
Does HALT state change?
Does cycle behavior change?
Can failure happen after some writes?
```

Use direct snapshot equality for strong verification. A trace hash is not a
substitute for complete state comparison.

TRACE HASH CHANGES
------------------

The trace hash is a deterministic 16-bit conformance digest, not a security
primitive.

Changing field order or adding a mixed field changes observed hashes. That may be
correct, but it is a compatibility change and must be documented.

Never claim collision resistance or identity from a 16-bit hash.

TEST DESIGN
-----------

Tests should expose one decision at a time.

Preferred pattern:

```text
arrange exact state
perform one operation
observe exact state
observe exact trace effect
reverse where relevant
observe exact restored state
```

Adversarial cases matter more than decorative volume:

```text
0x0000
0x7FFF
0x8000
0xFFFF
address 0
address 65535
range ending exactly at 65536
one-unit overflow
empty trace
already halted
invalid opcode
malformed first token
malformed last token
```

A test that only checks a success message may miss architectural corruption.
Inspect state.

TOOLCHAIN FAILURES VS PROJECT FAILURES
--------------------------------------

Classify before editing source.

```text
COMMAND NOT FOUND
    toolchain absent

CMAKE / COMPILER ERROR
    runtime bootstrap or host toolchain

Io VM FAILS BEFORE TEST FILE EXECUTES
    upstream runtime bootstrap

TEST FILE PRINTS FAIL OR RETURNS NONZERO
    CINDER-16 implementation or test contract
```

Do not patch CINDER-16 core to hide a missing compiler.

Do not call a build pass a machine-test pass.

DOCUMENTATION STYLE
-------------------

Use plain README.TXT structure:

```text
UPPERCASE HEADING
-----------------

compact paragraphs
ASCII diagrams
exact examples
few decorative elements
```

Document current bytes and behavior. Do not write future features as if they
exist.

Separate:

```text
NORMATIVE CONTRACT
IMPLEMENTATION DETAIL
OBSERVED EVIDENCE
DEFINED ABSENCE
FUTURE POSSIBILITY
```

Code comments and docs should explain why an order or invariant matters, not
repeat obvious syntax.

CHANGE SIZE
-----------

Prefer the smallest change that closes the defined condition.

Bad patch:

```text
new opcode + parser rewrite + debugger redesign + formatting sweep
```

Good patch:

```text
one opcode contract + implementation + disassembly + tests + docs
```

Mechanical formatting should not obscure semantic review.

BRANCH AND REVIEW
-----------------

For external contributions:

```text
1. Branch from current main.
2. Keep commits understandable.
3. Run the complete local suite.
4. Include observed output and host toolchain details.
5. Open one focused pull request.
6. State what was intentionally not changed.
```

A pull request body should lead with outcome and evidence.

REPORT FORMAT
-------------

Useful completion report:

```text
OUTCOME
    what observable behavior now exists

EVIDENCE
    exact command
    exact process result
    assertion counts
    exit status

CHANGE
    files and contracts changed

UNCHANGED
    protected scope not touched

LIMITS
    remaining uncertainty or platform scope
```

Avoid:

```text
should work
looks good
probably fixed
all done
```

unless followed by actual evidence that justifies the claim.

SECURITY AND SAFETY
-------------------

CINDER-16 is a local educational/research VM. It is not a sandbox for hostile
programs and does not claim process isolation.

The strict loader validates image structure and memory bounds. It does not make
arbitrary host files trustworthy.

Do not add network fetch, automatic package installation, or hidden PATH changes
to the normal test path.

LICENSE
-------

Contributions are accepted under GNU General Public License version 2, matching
the repository license.

FINAL CHECK
-----------

Before calling a change complete:

```text
[ ] scope classified
[ ] done condition written
[ ] contract documented
[ ] mutation order reviewed
[ ] failure path reviewed
[ ] reverse path reviewed
[ ] direct state assertions added
[ ] complete local suite executed
[ ] process returned success
[ ] report distinguishes evidence from claims
[ ] no unrelated system added
```
