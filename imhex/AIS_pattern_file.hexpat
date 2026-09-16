#pragma description AM1802 AIS Script
#pragma magic [ 54 49 50 41 ] @ 0x0

/*
 * WARNING: This is quite incomplete. It's the bare minimum to make sense of the
 *          Electribe 2's flash dump AIS. Other AIS commands than that have yet
 *          to be added.
 */

import std.mem;
import std.core;
import std.io;
import type.size;
import type.fmt;
import type.base;
import type.magic;


struct Cmd_SectionLoad {
    const str NAME = "Section Load";
    type::Magic<"\x01YSX"> opcode;
    type::Hex<u32> addr;
    type::Size32 size;
    u8 data[size];
    padding[(4-(size%4)) % 4];
};

struct Cmd_JumpAndClose {
    const str NAME = "Jump And Close";
    type::Magic<"\x06YSX"> opcode;
    type::Hex<u32> addr; // entry point of ARM application
};

struct Cmd_FunctionExecute {
    const str NAME = "Function Execute";
    
    type::Magic<"\x0DYSX"> opcode;
    u16 func_idx;
    u16 arg_count;
    u32 args[arg_count];
};

struct Cmd_SequentialReadEnable {
    const str NAME = "Sequential Read Enable";
    
    type::Magic<"\x63YSX"> opcode;
};

struct Command {
    char opcode[4] [[no_unique_address, hidden]];
    match (opcode[0]) {
        (0x01):  Cmd_SectionLoad cmd [[inline]];
        (0x06):  Cmd_JumpAndClose cmd [[inline]];
        (0x0D):  Cmd_FunctionExecute cmd [[inline]];
        (0x63):  Cmd_SequentialReadEnable cmd [[inline]];
        (_):     continue;
    }
    std::core::set_display_name(this, cmd.NAME);
    if (opcode == "\x06YSX") // Jump and Close
        break;
};



#define MAX_COMMANDS 500

struct AIS {
    type::Magic<"TIPA"> magic;
    Command commands[MAX_COMMANDS] [[inline]];
};

AIS script @ 0x00;