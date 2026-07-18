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

    assertRaisesContains := method(exception, fragment, label,
        if(exception isNil, fail(label .. ": expected exception"))
        if(exception error containsSeq(fragment) not,
            fail(
                label .. ": expected error containing '" .. fragment ..
                "', got '" .. exception error .. "'"
            )
        )
        setCount(count + 1)
    )
)

machine := Cinder16Machine new
machine writeMemoryRaw(0, 0x1111)
machine writeMemoryRaw(65535, 0xeeee)

exception := try(machine readMemory(-1))
Test assertRaisesContains(
    exception,
    "memory address out of range",
    "software stack underflow address"
)
Test assertEqual(0x1111, machine readMemory(0), "underflow does not wrap")

exception = try(machine writeMemoryRaw(65536, 0x2222))
Test assertRaisesContains(
    exception,
    "memory address out of range",
    "software stack overflow address"
)
Test assertEqual(0xeeee, machine readMemory(65535), "overflow does not wrap")

machine = Cinder16Machine new
machine loadWords(list(0xf000), 0)
exception = try(machine step)
Test assertRaisesContains(
    exception,
    "invalid opcode",
    "opcode 0xF is not implicit division"
)
Test assertEqual(0, machine pc, "undefined division encoding keeps pc")
Test assertEqual(0, machine cycles, "undefined division encoding keeps cycles")
Test assertEqual(0, machine trace size, "undefined division encoding keeps trace")

writeln("PASS: ", Test count, " assertions")
System exit(0)
