Lobby doFile("src/Cinder16.io")

Cinder16Loader := Object clone do(
    isWhitespaceByte := method(value,
        value == 9 or value == 10 or value == 13 or value == 32
    )

    hexDigitValue := method(value,
        if(value >= 48 and value <= 57, return value - 48)
        if(value >= 65 and value <= 70, return value - 55)
        if(value >= 97 and value <= 102, return value - 87)
        -1
    )

    normalizedStartAddress := method(startAddress,
        if(startAddress isNil, startAddress = 0)
        Cinder16Util checkedIndex(startAddress, 65536, "load address")
        startAddress
    )

    parseRawBytes := method(bytes, byteOrder,
        if(byteOrder != "big" and byteOrder != "little",
            Exception raise(
                "raw image byte order must be 'big' or 'little'"
            )
        )
        if((bytes size % 2) != 0,
            Exception raise("raw image has an incomplete trailing word")
        )

        words := List clone
        index := 0
        while(index < bytes size,
            first := bytes at(index)
            second := bytes at(index + 1)

            if(first < 0 or first > 255 or second < 0 or second > 255,
                Exception raise("raw image contains a non-byte value")
            )

            if(byteOrder == "big",
                words append((first << 8) | second)
            ,
                words append((second << 8) | first)
            )
            index = index + 2
        )
        words
    )

    parseHexText := method(text,
        words := List clone
        currentWord := 0
        digitCount := 0
        index := 0

        while(index < text size,
            value := text at(index)
            if(isWhitespaceByte(value),
                if(digitCount != 0,
                    if(digitCount != 4,
                        Exception raise(
                            "hex image word at byte " ..
                            (index - digitCount) asString ..
                            " has " .. digitCount asString ..
                            " digits; expected 4"
                        )
                    )
                    words append(currentWord)
                    currentWord = 0
                    digitCount = 0
                )
            ,
                digit := hexDigitValue(value)
                if(digit < 0,
                    Exception raise(
                        "hex image contains invalid character at byte " ..
                        index asString
                    )
                )
                if(digitCount == 4,
                    Exception raise(
                        "hex image word at byte " ..
                        (index - digitCount) asString ..
                        " has more than 4 digits"
                    )
                )
                currentWord = (currentWord << 4) | digit
                digitCount = digitCount + 1
            )
            index = index + 1
        )

        if(digitCount != 0,
            if(digitCount != 4,
                Exception raise(
                    "hex image trailing word has " .. digitCount asString ..
                    " digits; expected 4"
                )
            )
            words append(currentWord)
        )
        words
    )

    commitWords := method(machine, words, startAddress,
        address := normalizedStartAddress(startAddress)
        machine loadWords(words, address)
        words size
    )

    loadRawBytes := method(machine, bytes, byteOrder, startAddress,
        words := parseRawBytes(bytes, byteOrder)
        commitWords(machine, words, startAddress)
    )

    loadHexText := method(machine, text, startAddress,
        words := parseHexText(text)
        commitWords(machine, words, startAddress)
    )

    fileContents := method(path,
        file := File with(path)
        if(file exists not,
            Exception raise("image file not found: " .. path)
        )
        file contents
    )

    loadRawFile := method(machine, path, byteOrder, startAddress,
        bytes := fileContents(path)
        loadRawBytes(machine, bytes, byteOrder, startAddress)
    )

    loadHexFile := method(machine, path, startAddress,
        text := fileContents(path)
        loadHexText(machine, text, startAddress)
    )
)
