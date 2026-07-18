#!/usr/bin/env io

Lobby doFile("src/Debugger.io")

debugger := Cinder16Debugger new

writeln("CINDER-16 DEBUGGER v0.1")
writeln("Type 'help' for commands. Type 'quit' to exit.")

while(true,
    "cinder16> " print
    File standardOutput flush

    line := File standardInput readLine
    if(line isNil, break)

    tokens := line splitNoEmpties
    if(tokens size > 0,
        command := tokens at(0) asLowercase
        if(command == "quit" or command == "exit", break)
    )

    result := nil
    exception := try(result = debugger execute(line))
    if(exception isNil,
        if(result isNil not and result size > 0, writeln(result))
    ,
        writeln("ERROR: ", exception error)
    )
)

writeln("BYE")
System exit(0)
