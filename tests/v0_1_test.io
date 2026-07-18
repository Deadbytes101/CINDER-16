#!/usr/bin/env io

Lobby doFile("src/Debugger.io")

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

bytes := method(
    result := Sequence clone
    call evalArgs foreach(value, result append(value))
    result
)

machineFor := method(instruction,
    machine := Cinder16Machine new
    machine loadWords(list(instruction), 0)
    machine
)

testRawLoader := method(
    loader := Cinder16Loader clone

    machine := Cinder16Machine new
    loaded := loader loadRawBytes(
        machine,
        bytes(0x12, 0x34, 0xab, 0xcd),
        "big",
        10
    )
    Test assertEqual(2, loaded, "raw big word count")
    Test assertEqual(0x1234, machine readMemory(10), "raw big word 0")
    Test assertEqual(0xabcd, machine readMemory(11), "raw big word 1")
    Test assertEqual(0, machine trace size, "raw load has no trace")

    machine = Cinder16Machine new
    loaded = loader loadRawBytes(
        machine,
        bytes(0x34, 0x12, 0xcd, 0xab),
        "little",
        20
    )
    Test assertEqual(2, loaded, "raw little word count")
    Test assertEqual(0x1234, machine readMemory(20), "raw little word 0")
    Test assertEqual(0xabcd, machine readMemory(21), "raw little word 1")

    machine = Cinder16Machine new
    machine writeMemoryRaw(0, 0xbeef)
    exception := try(
        loader loadRawBytes(machine, bytes(1, 2, 3), "big", 0)
    )
    Test assertRaisesContains(
        exception,
        "incomplete trailing word",
        "raw odd-byte rejection"
    )
    Test assertEqual(0xbeef, machine readMemory(0), "raw failure is atomic")

    exception = try(
        loader loadRawBytes(machine, bytes(1, 2), "middle", 0)
    )
    Test assertRaisesContains(
        exception,
        "byte order",
        "raw byte order required"
    )
    Test assertEqual(0xbeef, machine readMemory(0), "byte-order failure atomic")
)

testHexLoader := method(
    loader := Cinder16Loader clone
    machine := Cinder16Machine new

    loaded := loader loadHexText(
        machine,
        "1234 abcd\n0001\tF00D\r\n",
        30
    )
    Test assertEqual(4, loaded, "hex word count")
    Test assertEqual(0x1234, machine readMemory(30), "hex word 0")
    Test assertEqual(0xabcd, machine readMemory(31), "hex lowercase")
    Test assertEqual(0x0001, machine readMemory(32), "hex leading zero")
    Test assertEqual(0xf00d, machine readMemory(33), "hex uppercase")

    machine = Cinder16Machine new
    machine writeMemoryRaw(0, 0xcafe)
    exception := try(loader loadHexText(machine, "123", 0))
    Test assertRaisesContains(exception, "expected 4", "short hex word")
    Test assertEqual(0xcafe, machine readMemory(0), "short hex atomic")

    exception = try(loader loadHexText(machine, "12G4", 0))
    Test assertRaisesContains(
        exception,
        "invalid character",
        "invalid hex character"
    )
    Test assertEqual(0xcafe, machine readMemory(0), "invalid hex atomic")

    exception = try(loader loadHexText(machine, "12345", 0))
    Test assertRaisesContains(exception, "more than 4", "long hex word")
    Test assertEqual(0xcafe, machine readMemory(0), "long hex atomic")

    exception = try(loader loadHexText(machine, "0001 0002", 65535))
    Test assertRaisesContains(
        exception,
        "exceeds memory",
        "hex bounds rejection"
    )
    Test assertEqual(0, machine readMemory(65535), "bounds failure atomic")
)

testFileLoader := method(
    loader := Cinder16Loader clone
    rawPath := "tests/.cinder16-loader.raw"
    hexPath := "tests/.cinder16-loader.hex"

    File with(rawPath) setContents(bytes(0x12, 0x34, 0xab, 0xcd))
    File with(hexPath) setContents("1111 2222\n")

    machine := Cinder16Machine new
    Test assertEqual(
        2,
        loader loadRawFile(machine, rawPath, "big", 4),
        "raw file count"
    )
    Test assertEqual(0x1234, machine readMemory(4), "raw file word")

    machine = Cinder16Machine new
    Test assertEqual(
        2,
        loader loadHexFile(machine, hexPath, 8),
        "hex file count"
    )
    Test assertEqual(0x2222, machine readMemory(9), "hex file word")

    File with(rawPath) remove
    File with(hexPath) remove
)

testOpcodeConformance := method(
    machine := machineFor(0x0000)
    delta := machine step
    Test assertEqual(1, machine pc, "NOP pc")
    Test assertEqual(1, machine cycles, "NOP cycles")
    Test assertEqual(0, delta registerWrites size, "NOP register writes")

    machine = machineFor(encodeLDI(3, 0x01ff))
    machine step
    Test assertEqual(0x01ff, machine readRegister(3), "LDI")

    machine = machineFor(encodeRR(0x02, 1, 2))
    machine writeRegisterRaw(2, 0x8000)
    machine step
    Test assertEqual(0x8000, machine readRegister(1), "MOV")

    machine = machineFor(encodeRR(0x03, 1, 2))
    machine writeRegisterRaw(1, 0xffff)
    machine writeRegisterRaw(2, 1)
    machine step
    Test assertEqual(0x0000, machine readRegister(1), "ADD wraps")

    machine = machineFor(encodeRR(0x04, 1, 2))
    machine writeRegisterRaw(1, 0x0000)
    machine writeRegisterRaw(2, 1)
    machine step
    Test assertEqual(0xffff, machine readRegister(1), "SUB wraps")

    machine = machineFor(encodeRR(0x05, 1, 2))
    machine writeRegisterRaw(2, 100)
    machine writeMemoryRaw(100, 0x7fff)
    machine step
    Test assertEqual(0x7fff, machine readRegister(1), "LD")

    machine = machineFor(encodeRR(0x06, 1, 2))
    machine writeRegisterRaw(1, 100)
    machine writeRegisterRaw(2, 0x8000)
    machine step
    Test assertEqual(0x8000, machine readMemory(100), "ST")

    machine = machineFor(encodeJump(0x0345))
    machine step
    Test assertEqual(0x0345, machine pc, "JMP")

    machine = machineFor(encodeJZ(1, 0x01ff))
    machine writeRegisterRaw(1, 0)
    machine step
    Test assertEqual(0x01ff, machine pc, "JZ taken")

    machine = machineFor(encodeJZ(1, 0x01ff))
    machine writeRegisterRaw(1, 1)
    machine step
    Test assertEqual(1, machine pc, "JZ not taken")

    machine = machineFor(encodeRR(0x09, 1, 2))
    machine writeRegisterRaw(1, 0xffff)
    machine writeRegisterRaw(2, 0x8000)
    machine step
    Test assertEqual(0x8000, machine readRegister(1), "AND")

    machine = machineFor(encodeRR(0x0a, 1, 2))
    machine writeRegisterRaw(1, 0x7fff)
    machine writeRegisterRaw(2, 0x8000)
    machine step
    Test assertEqual(0xffff, machine readRegister(1), "OR")

    machine = machineFor(encodeRR(0x0b, 1, 2))
    machine writeRegisterRaw(1, 0xffff)
    machine writeRegisterRaw(2, 0x7fff)
    machine step
    Test assertEqual(0x8000, machine readRegister(1), "XOR")

    machine = machineFor(encodeRR(0x0c, 1, 2))
    machine writeRegisterRaw(1, 0x8000)
    machine writeRegisterRaw(2, 1)
    machine step
    Test assertEqual(0x0000, machine readRegister(1), "SHL wraps")

    machine = machineFor(encodeRR(0x0d, 1, 2))
    machine writeRegisterRaw(1, 0xffff)
    machine writeRegisterRaw(2, 15)
    machine step
    Test assertEqual(1, machine readRegister(1), "SHR")

    machine = machineFor(0xe000)
    machine step
    Test assertTrue(machine halted, "HALT")

    machine = machineFor(0xf000)
    exception := try(machine step)
    Test assertRaisesContains(exception, "invalid opcode", "opcode 0xF traps")
    Test assertEqual(0, machine pc, "invalid opcode pc atomic")
    Test assertEqual(0, machine cycles, "invalid opcode cycles atomic")
    Test assertEqual(0, machine trace size, "invalid opcode trace atomic")
)

testArithmeticBoundaries := method(
    machine := Cinder16Machine new
    boundaries := list(0x0000, 0x7fff, 0x8000, 0xffff)
    boundaries foreach(index, value,
        machine writeRegisterRaw(index, value)
        machine writeMemoryRaw(100 + index, value)
        Test assertEqual(value, machine readRegister(index), "register boundary")
        Test assertEqual(value, machine readMemory(100 + index), "memory boundary")
    )
)

testTraceDeterminism := method(
    program := list(
        encodeLDI(1, 100),
        encodeLDI(2, 7),
        encodeRR(0x06, 1, 2),
        encodeRR(0x05, 3, 1),
        0xe000
    )

    first := Cinder16Machine new
    second := Cinder16Machine new
    first loadWords(program, 0)
    second loadWords(program, 0)
    first run(16)
    second run(16)

    firstHash := Cinder16TraceHasher hash(first)
    secondHash := Cinder16TraceHasher hash(second)
    Test assertEqual(firstHash, secondHash, "repeated trace hash")
    Test assertTrue(firstHash != 0, "trace hash is nonzero")
    Test assertEqual(first trace size, second trace size, "trace length deterministic")
)

testExactForwardReverse := method(
    machine := Cinder16Machine new
    machine loadWords(
        list(
            encodeLDI(1, 120),
            encodeLDI(2, 0x01ff),
            encodeRR(0x06, 1, 2),
            encodeLDI(2, 0),
            encodeRR(0x05, 2, 1),
            encodeRR(0x03, 2, 2),
            0xe000
        ),
        0
    )
    machine writeRegisterRaw(7, 0x8000)
    machine writeMemoryRaw(120, 0x7fff)

    snapshot := Cinder16Snapshot capture(machine)
    machine run(32)
    Test assertTrue(snapshot equalsMachine(machine) not, "execution changes state")

    while(machine trace size > 0, machine back)
    Test assertTrue(
        snapshot equalsMachine(machine),
        "forward then reverse restores exact state"
    )
)

testDebuggerCommands := method(
    machine := Cinder16Machine new
    machine loadWords(list(0x0000, 0xe000), 0)
    debugger := Cinder16Debugger new(machine)

    Test assertTrue(
        debugger execute("regs") containsSeq("R0=0x0000"),
        "debugger regs"
    )
    Test assertTrue(
        debugger execute("mem 0 2") containsSeq("0x0001: 0xE000"),
        "debugger mem"
    )
    Test assertTrue(
        debugger execute("disasm 0 2") containsSeq("HALT"),
        "debugger disasm"
    )
    Test assertTrue(
        debugger execute("step") containsSeq("NOP"),
        "debugger step"
    )
    Test assertEqual(1, machine pc, "debugger step pc")
    Test assertTrue(
        debugger execute("back") containsSeq("BACK"),
        "debugger back"
    )
    Test assertEqual(0, machine pc, "debugger back pc")

    debugger execute("break 1")
    output := debugger execute("run 8")
    Test assertTrue(output containsSeq("BREAK 0x0001"), "debugger breakpoint")
    Test assertEqual(1, machine pc, "breakpoint pc")
    Test assertTrue(
        debugger execute("break") containsSeq("0x0001"),
        "breakpoint list"
    )
    debugger execute("break clear")

    machine = Cinder16Machine new
    machine loadWords(
        list(
            encodeLDI(1, 100),
            encodeLDI(2, 7),
            encodeRR(0x06, 1, 2),
            0xe000
        ),
        0
    )
    debugger = Cinder16Debugger new(machine)
    debugger execute("watch 100")
    output = debugger execute("run 16")
    Test assertTrue(output containsSeq("WATCH 0x0064"), "debugger watchpoint")
    Test assertEqual(7, machine readMemory(100), "watchpoint memory")
    Test assertEqual(3, machine pc, "watchpoint stop pc")
    Test assertTrue(
        debugger execute("trace 3") containsSeq("memWrites=1"),
        "debugger trace"
    )

    debugger execute("reset")
    Test assertEqual(0, debugger machine readMemory(100), "debugger reset memory")
    Test assertEqual(0, debugger machine pc, "debugger reset pc")
    Test assertTrue(
        debugger execute("help") containsSeq("load raw"),
        "debugger help"
    )
)

testDebuggerLoadAtomicity := method(
    goodPath := "tests/.cinder16-debug-good.raw"
    badPath := "tests/.cinder16-debug-bad.raw"
    File with(goodPath) setContents(bytes(0x12, 0x34, 0xe0, 0x00))
    File with(badPath) setContents(bytes(0x12, 0x34, 0xff))

    debugger := Cinder16Debugger new
    output := debugger execute(
        "load raw " .. goodPath .. " big 4"
    )
    Test assertTrue(output containsSeq("LOAD words=2"), "debugger raw load")
    Test assertEqual(0x1234, debugger machine readMemory(4), "debugger load word")

    previousMachine := debugger machine
    exception := try(
        debugger execute("load raw " .. badPath .. " big 0")
    )
    Test assertRaisesContains(
        exception,
        "incomplete trailing word",
        "debugger rejects bad image"
    )
    Test assertTrue(
        debugger machine == previousMachine,
        "debugger bad load preserves machine object"
    )
    Test assertEqual(
        0x1234,
        debugger machine readMemory(4),
        "debugger bad load preserves state"
    )

    File with(goodPath) remove
    File with(badPath) remove
)

testRawLoader
testHexLoader
testFileLoader
testOpcodeConformance
testArithmeticBoundaries
testTraceDeterminism
testExactForwardReverse
testDebuggerCommands
testDebuggerLoadAtomicity

writeln("PASS: ", Test count, " assertions")
System exit(0)
