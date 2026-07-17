Cinder16Util := Object clone do(
    word := method(value,
        value & 0xffff
    )

    checkedIndex := method(index, limit, label,
        if(index < 0 or index >= limit,
            Exception raise(label .. " out of range: " .. index asString)
        )
        index
    )

    zeroList := method(size,
        result := List clone
        result preallocateToSize(size)
        size repeat(result append(0))
        result
    )
)

Cinder16WriteRecord := Object clone do(
    index ::= 0
    oldValue ::= 0

    with := method(anIndex, anOldValue,
        record := self clone
        record setIndex(anIndex)
        record setOldValue(anOldValue)
        record
    )
)

Cinder16Delta := Object clone do(
    pcBefore ::= 0
    cyclesBefore ::= 0
    haltedBefore ::= false
    instructionWord ::= 0

    pcAfter ::= 0
    cyclesAfter ::= 0
    haltedAfter ::= false

    registerWrites ::= nil
    memoryWrites ::= nil

    new := method(pcValue, cycleValue, haltedValue, wordValue,
        delta := self clone
        delta setPcBefore(pcValue)
        delta setCyclesBefore(cycleValue)
        delta setHaltedBefore(haltedValue)
        delta setInstructionWord(wordValue)
        delta setRegisterWrites(List clone)
        delta setMemoryWrites(List clone)
        delta
    )

    finish := method(pcValue, cycleValue, haltedValue,
        setPcAfter(pcValue)
        setCyclesAfter(cycleValue)
        setHaltedAfter(haltedValue)
        self
    )
)

Cinder16Machine := Object clone do(
    memory ::= nil
    registers ::= nil
    pc ::= 0
    cycles ::= 0
    halted ::= false
    trace ::= nil

    new := method(
        machine := self clone
        machine initialize
        machine
    )

    initialize := method(
        setMemory(Cinder16Util zeroList(65536))
        setRegisters(Cinder16Util zeroList(8))
        setTrace(List clone)
        setPc(0)
        setCycles(0)
        setHalted(false)
        self
    )

    reset := method(
        initialize
    )

    readRegister := method(index,
        Cinder16Util checkedIndex(index, 8, "register")
        registers at(index)
    )

    writeRegisterRaw := method(index, value,
        Cinder16Util checkedIndex(index, 8, "register")
        registers atPut(index, Cinder16Util word(value))
        self
    )

    writeRegister := method(index, value, delta,
        oldValue := readRegister(index)
        delta registerWrites append(
            Cinder16WriteRecord with(index, oldValue)
        )
        writeRegisterRaw(index, value)
    )

    readMemory := method(address,
        Cinder16Util checkedIndex(address, 65536, "memory address")
        memory at(address)
    )

    writeMemoryRaw := method(address, value,
        Cinder16Util checkedIndex(address, 65536, "memory address")
        memory atPut(address, Cinder16Util word(value))
        self
    )

    writeMemory := method(address, value, delta,
        oldValue := readMemory(address)
        delta memoryWrites append(
            Cinder16WriteRecord with(address, oldValue)
        )
        writeMemoryRaw(address, value)
    )

    loadWords := method(words, startAddress,
        if(startAddress isNil, startAddress = 0)
        Cinder16Util checkedIndex(startAddress, 65536, "load address")
        if(words size > (65536 - startAddress),
            Exception raise("program image exceeds memory")
        )

        words foreach(offset, value,
            writeMemoryRaw(startAddress + offset, value)
        )
        self
    )

    opcodeOf := method(word, (word >> 12) & 0x0f)
    rdOf := method(word, (word >> 9) & 0x07)
    rsOf := method(word, (word >> 6) & 0x07)
    imm9Of := method(word, word & 0x01ff)
    target12Of := method(word, word & 0x0fff)

    validateOpcode := method(opcode,
        if(opcode == 0x0f,
            Exception raise("invalid opcode 0xF")
        )
        opcode
    )

    step := method(
        if(halted,
            Exception raise("machine is halted")
        )

        instruction := readMemory(pc)
        opcode := validateOpcode(opcodeOf(instruction))
        delta := Cinder16Delta new(pc, cycles, halted, instruction)

        rd := rdOf(instruction)
        rs := rsOf(instruction)

        setPc(Cinder16Util word(pc + 1))

        if(opcode == 0x00, nil)
        if(opcode == 0x01,
            writeRegister(rd, imm9Of(instruction), delta)
        )
        if(opcode == 0x02,
            writeRegister(rd, readRegister(rs), delta)
        )
        if(opcode == 0x03,
            writeRegister(
                rd,
                readRegister(rd) + readRegister(rs),
                delta
            )
        )
        if(opcode == 0x04,
            writeRegister(
                rd,
                readRegister(rd) - readRegister(rs),
                delta
            )
        )
        if(opcode == 0x05,
            writeRegister(
                rd,
                readMemory(readRegister(rs)),
                delta
            )
        )
        if(opcode == 0x06,
            writeMemory(
                readRegister(rd),
                readRegister(rs),
                delta
            )
        )
        if(opcode == 0x07,
            setPc(target12Of(instruction))
        )
        if(opcode == 0x08,
            if(readRegister(rd) == 0,
                setPc(imm9Of(instruction))
            )
        )
        if(opcode == 0x09,
            writeRegister(
                rd,
                readRegister(rd) & readRegister(rs),
                delta
            )
        )
        if(opcode == 0x0a,
            writeRegister(
                rd,
                readRegister(rd) | readRegister(rs),
                delta
            )
        )
        if(opcode == 0x0b,
            writeRegister(
                rd,
                readRegister(rd) ^ readRegister(rs),
                delta
            )
        )
        if(opcode == 0x0c,
            writeRegister(
                rd,
                readRegister(rd) << (readRegister(rs) & 0x0f),
                delta
            )
        )
        if(opcode == 0x0d,
            writeRegister(
                rd,
                readRegister(rd) >> (readRegister(rs) & 0x0f),
                delta
            )
        )
        if(opcode == 0x0e,
            setHalted(true)
        )

        setCycles(cycles + 1)
        delta finish(pc, cycles, halted)
        trace append(delta)
        delta
    )

    run := method(maxSteps,
        if(maxSteps isNil, maxSteps = 100000)
        if(maxSteps < 0,
            Exception raise("execution budget must be non-negative")
        )

        executed := 0
        while(halted not and executed < maxSteps,
            step
            executed = executed + 1
        )

        if(halted not,
            Exception raise("execution budget exhausted")
        )
        executed
    )

    back := method(
        if(trace size == 0,
            Exception raise("trace history is empty")
        )

        delta := trace pop

        delta memoryWrites reverseForeach(record,
            writeMemoryRaw(record index, record oldValue)
        )

        delta registerWrites reverseForeach(record,
            writeRegisterRaw(record index, record oldValue)
        )

        setPc(delta pcBefore)
        setCycles(delta cyclesBefore)
        setHalted(delta haltedBefore)
        delta
    )
)
