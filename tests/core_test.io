#!/usr/bin/env io

Lobby doFile("src/Cinder16.io")

Test := Object clone do(
    count ::= 0

    fail := method(message,
        writeln("FAIL: ", message)
        System exit(1)
    )

    assertEqual := method(expected, actual, label,
        if(expected != actual,
            fail(
                label .. ": expected " .. expected asString ..
                ", got " .. actual asString
            )
        )
        setCount(count + 1)
    )

    assertTrue := method(value, label,
        if(value not, fail(label))
        setCount(count + 1)
    )
)

encodeRR := method(opcode, rd, rs,
    ((opcode & 0x0f) << 12) |
    ((rd & 0x07) << 9) |
    ((rs & 0x07) << 6)
)

encodeLDI := method(rd, immediate,
    (0x01 << 12) |
    ((rd & 0x07) << 9) |
    (immediate & 0x01ff)
)

encodeJZ := method(rd, target,
    (0x08 << 12) |
    ((rd & 0x07) << 9) |
    (target & 0x01ff)
)

encodeJump := method(target,
    (0x07 << 12) | (target & 0x0fff)
)

testWordWrapping := method(
    machine := Cinder16Machine new
    machine writeRegisterRaw(0, 0x10000)
    Test assertEqual(0, machine readRegister(0), "register wraps")

    machine writeMemoryRaw(42, -1)
    Test assertEqual(0xffff, machine readMemory(42), "memory wraps")
)

testArithmeticAndHalt := method(
    machine := Cinder16Machine new
    program := list(
        encodeLDI(1, 7),
        encodeLDI(2, 5),
        encodeRR(0x03, 1, 2),
        0xe000
    )

    machine loadWords(program, 0)
    executed := machine run(16)

    Test assertEqual(4, executed, "instruction count")
    Test assertEqual(12, machine readRegister(1), "ADD result")
    Test assertEqual(4, machine cycles, "cycle count")
    Test assertTrue(machine halted, "HALT state")
    Test assertEqual(4, machine trace size, "trace count")

    machine back
    Test assertTrue(machine halted not, "reverse HALT state")
    Test assertEqual(3, machine pc, "reverse HALT pc")
    Test assertEqual(3, machine cycles, "reverse HALT cycles")
)

testMemoryAndReverse := method(
    machine := Cinder16Machine new
    program := list(
        encodeLDI(1, 100),
        encodeLDI(2, 77),
        encodeRR(0x06, 1, 2),
        encodeLDI(2, 0),
        encodeRR(0x05, 2, 1),
        0xe000
    )

    machine loadWords(program, 0)

    machine step
    machine step
    machine step

    Test assertEqual(77, machine readMemory(100), "store result")
    Test assertEqual(3, machine pc, "pc after store")

    machine back

    Test assertEqual(0, machine readMemory(100), "reverse store")
    Test assertEqual(2, machine pc, "reverse pc")
    Test assertEqual(2, machine cycles, "reverse cycles")

    machine step
    machine step
    machine step

    Test assertEqual(77, machine readRegister(2), "load result")

    machine back
    Test assertEqual(0, machine readRegister(2), "reverse load")
)

testConditionalBranch := method(
    machine := Cinder16Machine new
    program := list(
        encodeLDI(0, 0),
        encodeJZ(0, 4),
        encodeLDI(1, 1),
        encodeJump(5),
        encodeLDI(1, 9),
        0xe000
    )

    machine loadWords(program, 0)
    machine run(16)

    Test assertEqual(9, machine readRegister(1), "JZ branch")
)

testInvalidOpcodeAtomicity := method(
    machine := Cinder16Machine new
    machine loadWords(list(0xf000), 0)

    exception := try(machine step)

    Test assertTrue(
        exception isNil not,
        "invalid opcode raises"
    )
    Test assertTrue(
        exception error containsSeq("invalid opcode"),
        "invalid opcode message"
    )
    Test assertEqual(0, machine pc, "invalid opcode pc")
    Test assertEqual(0, machine cycles, "invalid opcode cycles")
    Test assertEqual(0, machine trace size, "invalid opcode trace")
)

testBudgetFailure := method(
    machine := Cinder16Machine new
    machine loadWords(list(encodeJump(0)), 0)

    exception := try(machine run(3))

    Test assertTrue(
        exception isNil not,
        "budget exhaustion raises"
    )
    Test assertTrue(
        exception error containsSeq("execution budget exhausted"),
        "budget exception message"
    )
    Test assertEqual(3, machine cycles, "budget cycle count")
    Test assertEqual(3, machine trace size, "budget trace count")
)

testWordWrapping
testArithmeticAndHalt
testMemoryAndReverse
testConditionalBranch
testInvalidOpcodeAtomicity
testBudgetFailure

writeln("PASS: ", Test count, " assertions")
System exit(0)
