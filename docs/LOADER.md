CINDER-16 IMAGE LOADER
======================

RULE
----

PARSE THE WHOLE IMAGE BEFORE WRITING ONE WORD.

A malformed image, invalid byte order, or out-of-range destination changes no
machine memory and creates no trace entry.

RAW BINARY IMAGE
----------------

A raw image is an even-length sequence of bytes. Every pair encodes one 16-bit
word. Byte order is mandatory.

```text
BIG ENDIAN

bytes 12 34 AB CD
words 1234 ABCD

LITTLE ENDIAN

bytes 34 12 CD AB
words 1234 ABCD
```

Hard failures:

```text
unknown byte order
odd byte count
non-byte value
image exceeds remaining memory
invalid start address
missing file
```

HEX TEXT IMAGE
--------------

A hexadecimal text image contains exactly four hexadecimal digits per word.
Words are separated by ASCII space, tab, carriage return, or line feed.
Letter case is ignored.

```text
1234 ABCD
0001 f00d
```

The format does not have a byte-order option. Each token directly represents
one 16-bit word in normal most-significant-digit-first notation.

The following are rejected instead of guessed or truncated:

```text
123
12345
12G4
1234,ABCD
```

MACHINE API
-----------

```text
loader := Cinder16Loader clone

loader loadRawBytes(machine, byteSequence, "big", startAddress)
loader loadRawBytes(machine, byteSequence, "little", startAddress)
loader loadHexText(machine, textSequence, startAddress)

loader loadRawFile(machine, path, "big", startAddress)
loader loadHexFile(machine, path, startAddress)
```

All methods return the number of words loaded.

DEBUGGER COMMANDS
-----------------

```text
load raw <path> <big|little> [address]
load hex <path> [address]
```

Debugger loads are transactional at machine-object level. A candidate machine
is built first. The active debugger machine is replaced only after the complete
image has parsed, passed bounds checks, and loaded successfully.
