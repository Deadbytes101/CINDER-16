CINDER-16 ISA v0.1
==================

MACHINE STATE
-------------

```text
WORD SIZE       16 bits
ADDRESS SPACE   65,536 words
REGISTERS       R0..R7, writable, 16 bits each
PC              16-bit program counter
CYCLES          monotonically increasing integer
HALTED          boolean
```

All register and memory writes are masked with `0xffff`. The program counter
wraps at `0xffff`. Memory is word-addressed.

INSTRUCTION WORD
----------------

Every instruction occupies exactly one 16-bit word.

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

OPCODES
-------

```text
0x0  NOP                 No architectural data change.
0x1  LDI  RD, IMM9       RD = zero_extend(IMM9).
0x2  MOV  RD, RS         RD = RS.
0x3  ADD  RD, RS         RD = (RD + RS) & 0xffff.
0x4  SUB  RD, RS         RD = (RD - RS) & 0xffff.
0x5  LD   RD, [RS]       RD = MEM[RS].
0x6  ST   [RD], RS       MEM[RD] = RS.
0x7  JMP  TARGET12       PC = zero_extend(TARGET12).
0x8  JZ   RD, TARGET9    If RD == 0, PC = zero_extend(TARGET9).
0x9  AND  RD, RS         RD = RD & RS.
0xA  OR   RD, RS         RD = RD | RS.
0xB  XOR  RD, RS         RD = RD ^ RS.
0xC  SHL  RD, RS         RD = (RD << (RS & 0x0f)) & 0xffff.
0xD  SHR  RD, RS         RD = (RD >> (RS & 0x0f)) & 0xffff.
0xE  HALT                HALTED = true.
0xF  INVALID             Trap before architectural state changes.
```

EXECUTION CONTRACT
------------------

For every valid instruction:

1. Fetch `MEM[PC]`.
2. Validate the opcode.
3. Capture pre-state metadata.
4. Set `PC = (PC + 1) & 0xffff`.
5. Execute the operation.
6. Increment `CYCLES` by one.
7. Commit one trace delta.

An invalid opcode raises an exception before PC, cycles, registers, memory, or
trace history are modified.

REVERSIBILITY CONTRACT
----------------------

Each committed instruction records:

```text
pc_before
cycles_before
halted_before
instruction_word
register_writes[] = (index, old_value)
memory_writes[]   = (address, old_value)
pc_after
cycles_after
halted_after
```

Applying the inverse delta must restore the exact state existing before that
instruction. Reverse-step removes the delta from trace history.

V0.1 LIMITS
-----------

- No interrupt model.
- No memory-mapped devices.
- No privilege levels.
- No flags register.
- No signed arithmetic opcodes.
- Jump targets are limited by their encoded immediate width.
