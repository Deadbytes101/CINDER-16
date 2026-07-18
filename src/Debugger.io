Lobby doFile("src/Loader.io")

Cinder16Format := Object clone do(
    hexWord := method(value,
        Cinder16Util word(value) asHex alignRight(4, "0") asUppercase
    )

    address := method(value,
        "0x" .. hexWord(value)
    )

    register := method(index,
        "R" .. index asString
    )
)

Cinder16Disassembler := Object clone do(
    lineFor := method(address, word,
        opcode := (word >> 12) & 0x0f
        rd := (word >> 9) & 0x07
        rs := (word >> 6) & 0x07
        imm9 := word & 0x01ff
        target12 := word & 0x0fff
        text := nil

        if(opcode == 0x00, text = "NOP")
        if(opcode == 0x01,
            text = "LDI " .. Cinder16Format register(rd) .. ", " ..
                Cinder16Format address(imm9)
        )
        if(opcode == 0x02,
            text = "MOV " .. Cinder16Format register(rd) .. ", " ..
                Cinder16Format register(rs)
        )
        if(opcode == 0x03,
            text = "ADD " .. Cinder16Format register(rd) .. ", " ..
                Cinder16Format register(rs)
        )
        if(opcode == 0x04,
            text = "SUB " .. Cinder16Format register(rd) .. ", " ..
                Cinder16Format register(rs)
        )
        if(opcode == 0x05,
            text = "LD " .. Cinder16Format register(rd) .. ", [" ..
                Cinder16Format register(rs) .. "]"
        )
        if(opcode == 0x06,
            text = "ST [" .. Cinder16Format register(rd) .. "], " ..
                Cinder16Format register(rs)
        )
        if(opcode == 0x07,
            text = "JMP " .. Cinder16Format address(target12)
        )
        if(opcode == 0x08,
            text = "JZ " .. Cinder16Format register(rd) .. ", " ..
                Cinder16Format address(imm9)
        )
        if(opcode == 0x09,
            text = "AND " .. Cinder16Format register(rd) .. ", " ..
                Cinder16Format register(rs)
        )
        if(opcode == 0x0a,
            text = "OR " .. Cinder16Format register(rd) .. ", " ..
                Cinder16Format register(rs)
        )
        if(opcode == 0x0b,
            text = "XOR " .. Cinder16Format register(rd) .. ", " ..
                Cinder16Format register(rs)
        )
        if(opcode == 0x0c,
            text = "SHL " .. Cinder16Format register(rd) .. ", " ..
                Cinder16Format register(rs)
        )
        if(opcode == 0x0d,
            text = "SHR " .. Cinder16Format register(rd) .. ", " ..
                Cinder16Format register(rs)
        )
        if(opcode == 0x0e, text = "HALT")
        if(opcode == 0x0f, text = "INVALID")

        Cinder16Format address(address) .. ": " ..
            Cinder16Format address(word) .. "  " .. text
    )
)

Cinder16TraceHasher := Object clone do(
    mix := method(hash, value,
        ((hash ^ Cinder16Util word(value)) * 257) & 0xffff
    )

    hash := method(machine,
        value := 0x811c
        value = mix(value, machine trace size)

        machine trace foreach(delta,
            value = mix(value, delta pcBefore)
            value = mix(value, delta cyclesBefore)
            value = mix(value, if(delta haltedBefore, 1, 0))
            value = mix(value, delta instructionWord)
            value = mix(value, delta pcAfter)
            value = mix(value, delta cyclesAfter)
            value = mix(value, if(delta haltedAfter, 1, 0))
            value = mix(value, delta registerWrites size)
            delta registerWrites foreach(record,
                value = mix(value, record index)
                value = mix(value, record oldValue)
            )
            value = mix(value, delta memoryWrites size)
            delta memoryWrites foreach(record,
                value = mix(value, record index)
                value = mix(value, record oldValue)
            )
        )
        value
    )
)

Cinder16Snapshot := Object clone do(
    pc ::= 0
    cycles ::= 0
    halted ::= false
    traceSize ::= 0
    registers ::= nil
    memory ::= nil

    copyList := method(source,
        copy := List clone
        copy preallocateToSize(source size)
        source foreach(value, copy append(value))
        copy
    )

    capture := method(machine,
        snapshot := self clone
        snapshot setPc(machine pc)
        snapshot setCycles(machine cycles)
        snapshot setHalted(machine halted)
        snapshot setTraceSize(machine trace size)
        snapshot setRegisters(copyList(machine registers))
        snapshot setMemory(copyList(machine memory))
        snapshot
    )

    equalsMachine := method(machine,
        if(pc != machine pc, return false)
        if(cycles != machine cycles, return false)
        if(halted != machine halted, return false)
        if(traceSize != machine trace size, return false)
        if(registers size != machine registers size, return false)
        if(memory size != machine memory size, return false)

        index := 0
        while(index < registers size,
            if(registers at(index) != machine registers at(index),
                return false
            )
            index = index + 1
        )

        index = 0
        while(index < memory size,
            if(memory at(index) != machine memory at(index),
                return false
            )
            index = index + 1
        )
        true
    )
)

Cinder16WatchRecord := Object clone do(
    address ::= 0
    value ::= 0

    with := method(anAddress, aValue,
        record := self clone
        record setAddress(anAddress)
        record setValue(aValue)
        record
    )
)

Cinder16Debugger := Object clone do(
    machine ::= nil
    loader ::= nil
    breakpoints ::= nil
    watchpoints ::= nil

    new := method(aMachine,
        debugger := self clone
        if(aMachine isNil, aMachine = Cinder16Machine new)
        debugger setMachine(aMachine)
        debugger setLoader(Cinder16Loader clone)
        debugger setBreakpoints(List clone)
        debugger setWatchpoints(List clone)
        debugger
    )

    parseUnsigned := method(token, label, maximum,
        if(token isNil or token size == 0,
            Exception raise(label .. " is missing")
        )
        if(maximum isNil, maximum = 65535)

        base := 10
        index := 0
        if(token size >= 2 and token at(0) == 48 and
            (token at(1) == 120 or token at(1) == 88),
            base = 16
            index = 2
        )
        if(index == token size,
            Exception raise(label .. " is not a number")
        )

        value := 0
        while(index < token size,
            byte := token at(index)
            digit := -1
            if(base == 10,
                if(byte >= 48 and byte <= 57, digit = byte - 48)
            ,
                digit = loader hexDigitValue(byte)
            )
            if(digit < 0 or digit >= base,
                Exception raise(label .. " is not an unsigned number: " .. token)
            )
            value = (value * base) + digit
            if(value > maximum,
                Exception raise(label .. " exceeds " .. maximum asString)
            )
            index = index + 1
        )
        value
    )

    hasBreakpoint := method(address,
        breakpoints foreach(value,
            if(value == address, return true)
        )
        false
    )

    addBreakpoint := method(address,
        Cinder16Util checkedIndex(address, 65536, "breakpoint")
        if(hasBreakpoint(address) not, breakpoints append(address))
        address
    )

    breakpointOutput := method(
        if(breakpoints size == 0, return "BREAKPOINTS empty")
        output := Sequence clone appendSeq("BREAKPOINTS")
        breakpoints foreach(address,
            output appendSeq(" ", Cinder16Format address(address))
        )
        output
    )

    findWatchRecord := method(address,
        watchpoints foreach(record,
            if(record address == address, return record)
        )
        nil
    )

    addWatchpoint := method(address,
        Cinder16Util checkedIndex(address, 65536, "watchpoint")
        if(findWatchRecord(address) isNil,
            watchpoints append(
                Cinder16WatchRecord with(address, machine readMemory(address))
            )
        )
        address
    )

    watchpointOutput := method(
        if(watchpoints size == 0, return "WATCHPOINTS empty")
        output := Sequence clone appendSeq("WATCHPOINTS")
        watchpoints foreach(record,
            output appendSeq(
                " ", Cinder16Format address(record address), "=",
                Cinder16Format address(record value)
            )
        )
        output
    )

    refreshWatchpoints := method(
        watchpoints foreach(record,
            record setValue(machine readMemory(record address))
        )
        self
    )

    checkWatchpoints := method(
        output := Sequence clone
        watchpoints foreach(record,
            current := machine readMemory(record address)
            if(current != record value,
                if(output size > 0, output appendSeq(" "))
                output appendSeq(
                    "WATCH ", Cinder16Format address(record address), " ",
                    Cinder16Format address(record value), "->",
                    Cinder16Format address(current)
                )
                record setValue(current)
            )
        )
        if(output size == 0, nil, output)
    )

    regsOutput := method(
        output := Sequence clone
        index := 0
        while(index < 8,
            if(output size > 0, output appendSeq(" "))
            output appendSeq(
                Cinder16Format register(index), "=",
                Cinder16Format address(machine readRegister(index))
            )
            index = index + 1
        )
        output appendSeq(
            " PC=", Cinder16Format address(machine pc),
            " CYCLES=", machine cycles asString,
            " HALTED=", if(machine halted, "yes", "no")
        )
        output
    )

    checkedRange := method(address, count, label,
        Cinder16Util checkedIndex(address, 65536, label)
        if(count <= 0, Exception raise(label .. " count must be positive"))
        if(count > 256, Exception raise(label .. " count exceeds 256"))
        if(address + count > 65536,
            Exception raise(label .. " range exceeds memory")
        )
        self
    )

    memOutput := method(tokens,
        if(tokens size < 2 or tokens size > 3,
            Exception raise("usage: mem <address> [count]")
        )
        address := parseUnsigned(tokens at(1), "memory address", 65535)
        count := 1
        if(tokens size == 3,
            count = parseUnsigned(tokens at(2), "memory count", 256)
        )
        checkedRange(address, count, "memory")

        output := Sequence clone
        offset := 0
        while(offset < count,
            if(output size > 0, output appendSeq("\n"))
            output appendSeq(
                Cinder16Format address(address + offset), ": ",
                Cinder16Format address(machine readMemory(address + offset))
            )
            offset = offset + 1
        )
        output
    )

    disasmOutput := method(tokens,
        if(tokens size < 2 or tokens size > 3,
            Exception raise("usage: disasm <address> [count]")
        )
        address := parseUnsigned(tokens at(1), "disassembly address", 65535)
        count := 1
        if(tokens size == 3,
            count = parseUnsigned(tokens at(2), "disassembly count", 256)
        )
        checkedRange(address, count, "disassembly")

        output := Sequence clone
        offset := 0
        while(offset < count,
            if(output size > 0, output appendSeq("\n"))
            currentAddress := address + offset
            output appendSeq(
                Cinder16Disassembler lineFor(
                    currentAddress,
                    machine readMemory(currentAddress)
                )
            )
            offset = offset + 1
        )
        output
    )

    deltaOutput := method(delta,
        Cinder16Format address(delta pcBefore) .. " " ..
            Cinder16Format address(delta instructionWord) .. " -> " ..
            Cinder16Format address(delta pcAfter) ..
            " cycle=" .. delta cyclesAfter asString ..
            " regWrites=" .. delta registerWrites size asString ..
            " memWrites=" .. delta memoryWrites size asString
    )

    traceOutput := method(tokens,
        if(tokens size > 2,
            Exception raise("usage: trace [count]")
        )
        count := 16
        if(tokens size == 2,
            count = parseUnsigned(tokens at(1), "trace count", 256)
            if(count == 0, Exception raise("trace count must be positive"))
        )
        if(machine trace size == 0, return "TRACE empty")

        start := (machine trace size - count) max(0)
        output := Sequence clone
        index := start
        while(index < machine trace size,
            if(output size > 0, output appendSeq("\n"))
            output appendSeq(deltaOutput(machine trace at(index)))
            index = index + 1
        )
        output
    )

    stepCommand := method(tokens,
        if(tokens size != 1, Exception raise("usage: step"))
        address := machine pc
        word := machine readMemory(address)
        delta := machine step
        watchMessage := checkWatchpoints
        output := Cinder16Disassembler lineFor(address, word) ..
            " -> PC=" .. Cinder16Format address(delta pcAfter)
        if(watchMessage isNil not,
            output = output .. " " .. watchMessage
        )
        output
    )

    backCommand := method(tokens,
        if(tokens size != 1, Exception raise("usage: back"))
        delta := machine back
        refreshWatchpoints
        "BACK " .. Cinder16Format address(delta pcBefore) ..
            " PC=" .. Cinder16Format address(machine pc)
    )

    runCommand := method(tokens,
        if(tokens size > 2, Exception raise("usage: run [budget]"))
        budget := 100000
        if(tokens size == 2,
            budget = parseUnsigned(tokens at(1), "run budget", 1000000)
        )
        if(budget == 0, Exception raise("run budget must be positive"))

        executed := 0
        stopReason := nil
        while(machine halted not and executed < budget and stopReason isNil,
            if(hasBreakpoint(machine pc),
                stopReason = "BREAK " .. Cinder16Format address(machine pc)
            ,
                machine step
                executed = executed + 1
                watchMessage := checkWatchpoints
                if(watchMessage isNil not, stopReason = watchMessage)
            )
        )

        if(stopReason isNil,
            if(machine halted,
                stopReason = "HALT"
            ,
                stopReason = "BUDGET"
            )
        )

        "RUN steps=" .. executed asString ..
            " PC=" .. Cinder16Format address(machine pc) ..
            " " .. stopReason
    )

    breakpointCommand := method(tokens,
        if(tokens size == 1, return breakpointOutput)
        if(tokens size != 2,
            Exception raise("usage: break [address|clear]")
        )
        if(tokens at(1) == "clear",
            setBreakpoints(List clone)
            return "BREAKPOINTS cleared"
        )
        address := parseUnsigned(tokens at(1), "breakpoint", 65535)
        addBreakpoint(address)
        "BREAKPOINT " .. Cinder16Format address(address)
    )

    watchpointCommand := method(tokens,
        if(tokens size == 1, return watchpointOutput)
        if(tokens size != 2,
            Exception raise("usage: watch [address|clear]")
        )
        if(tokens at(1) == "clear",
            setWatchpoints(List clone)
            return "WATCHPOINTS cleared"
        )
        address := parseUnsigned(tokens at(1), "watchpoint", 65535)
        addWatchpoint(address)
        "WATCHPOINT " .. Cinder16Format address(address)
    )

    resetCommand := method(tokens,
        if(tokens size != 1, Exception raise("usage: reset"))
        machine reset
        refreshWatchpoints
        "RESET"
    )

    loadCommand := method(tokens,
        if(tokens size < 3,
            Exception raise(
                "usage: load raw <path> <big|little> [address] | " ..
                "load hex <path> [address]"
            )
        )

        format := tokens at(1)
        path := tokens at(2)
        candidate := Cinder16Machine new
        loaded := 0

        if(format == "raw",
            if(tokens size < 4 or tokens size > 5,
                Exception raise("usage: load raw <path> <big|little> [address]")
            )
            startAddress := 0
            if(tokens size == 5,
                startAddress = parseUnsigned(tokens at(4), "load address", 65535)
            )
            loaded = loader loadRawFile(
                candidate, path, tokens at(3), startAddress
            )
        ,
            if(format == "hex",
                if(tokens size > 4,
                    Exception raise("usage: load hex <path> [address]")
                )
                startAddress := 0
                if(tokens size == 4,
                    startAddress = parseUnsigned(tokens at(3), "load address", 65535)
                )
                loaded = loader loadHexFile(candidate, path, startAddress)
            ,
                Exception raise("load format must be 'raw' or 'hex'")
            )
        )

        setMachine(candidate)
        setBreakpoints(List clone)
        setWatchpoints(List clone)
        "LOAD words=" .. loaded asString
    )

    helpOutput := method(
        "run [budget]\n" ..
        "step\n" ..
        "back\n" ..
        "regs\n" ..
        "mem <address> [count]\n" ..
        "disasm <address> [count]\n" ..
        "break [address|clear]\n" ..
        "watch [address|clear]\n" ..
        "reset\n" ..
        "load raw <path> <big|little> [address]\n" ..
        "load hex <path> [address]\n" ..
        "trace [count]"
    )

    execute := method(line,
        tokens := line splitNoEmpties
        if(tokens size == 0, return "")
        command := tokens at(0) asLowercase

        if(command == "run", return runCommand(tokens))
        if(command == "step", return stepCommand(tokens))
        if(command == "back", return backCommand(tokens))
        if(command == "regs",
            if(tokens size != 1, Exception raise("usage: regs"))
            return regsOutput
        )
        if(command == "mem", return memOutput(tokens))
        if(command == "disasm", return disasmOutput(tokens))
        if(command == "break", return breakpointCommand(tokens))
        if(command == "watch", return watchpointCommand(tokens))
        if(command == "reset", return resetCommand(tokens))
        if(command == "load", return loadCommand(tokens))
        if(command == "trace", return traceOutput(tokens))
        if(command == "help", return helpOutput)

        Exception raise("unknown debugger command: " .. command)
    )
)
