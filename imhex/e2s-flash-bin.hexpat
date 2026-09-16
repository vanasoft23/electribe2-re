#pragma description KORG Electribe 2 flash dump
#pragma magic [ 54 49 50 41 ] @ 0x0
#pragma magic [ 50 54 53 54 ] @ 0x000EFF58

#pragma pattern_limit 0x400000

import std.mem;
import type.magic;

std::assert(std::mem::size() == 0x1000000, "Flash dump must be 16 MiB!");

////////////////////////////////////////
//
// First define required sub-patterns...
//
////////////////////////////////////////

//
// BEGIN AIS
//

import std.mem;
import std.core;
import std.io;
import type.size;
import type.fmt;
import type.base;


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

//
// END AIS
//


//
// BEGIN e2spat
//

struct KORGHeader
{
    char title[0x10];
    char dev_name[0x10];
    u32 version;
    u8 _0[0xdc];
};

struct E2SPatHeader
{
    type::Magic<"PTST"> ptst_magic;
    padding[12];
    //char ptst_str[0x10];
    
    char name[0x10];
    padding[2];
    u16 bpm;
    u8 swing;
    u8 length;
    u8 beat;
    u8 key;
    u8 scale;
    u8 chord_set;
    u8 level;
    padding[6];
    u8 gate_arp;
    padding[11];
    u8 mfx_type;
    padding[1]; // mfx_x ?
    padding[1]; // mfx_y ?
    padding[4];
    u8 alt_13_14;
    u8 alt_15_16;
};

struct Step
{
    bool has_notes;
    u8 gate;
    u8 velocity;
    u8 chord;
    s8 note0;
    s8 note1;
    s8 note2;
    s8 note3;
    padding[4];
};

struct Sequence
{
    Step steps[16];
};

struct Part
{
    u8 last_step;
    padding[1];
    u8 voice_assign;
    bool part_priority;
    bool motion_seq;
    bool trigger_pad_velocity;
    u16 scale_mode;
    u16 oscillator; // this.loc[this.offset + 8] + 0x100 * this.loc[this.offset + 9];
    padding[1];
    u8 edit_osc;
    u8 filter_type;
    u8 cutoff;
    u8 resonance;
    s8 eg_int;
    u8 mod_type;
    u8 mod_speed;
    u8 mod_depth;
    padding[1];
    u8 attack;
    u8 decay;
    padding[2];
    u8 level;
    s8 pan;
    bool amp_eg;
    bool mfx;
    u8 groove_type;
    u8 groove_depth;
    padding[2];
    u8 ifx; //?
    u8 fx; //?
    u8 ifx_edit;
    padding[1];
    s8 pitch;
    u8 glide;
    padding[5];
    u8 sequence_start;
    padding[3];
    
    Sequence sequences[4];
    //padding[0x300]; // step stuff
};

struct E2SPatFile
{
    E2SPatHeader header;
    padding[1978]; // motion seq data?
    Part parts[16];
    padding[1296];
};

//
// END e2spat
//

//
// Define various structs specific to flash...
//

struct Firmware {
    u32 base = $;
    
    u8 firmware[0x200000];
    /*
    u8 splash_screen[128*8] @ base + 0xF9854;    // have to verify again first
    E2SPatFile init_pattern @ base + 0x000CFF58; // incorrect on blue synth dump
    */
};

struct E2SAllPat_NoKORGHeader {
    u8 e2sAllPatHeader[0x10000];
    E2SPatFile patterns[250];
};

struct  _Unknown_File_64KiB {
    u8 GLST_GLED_block[0x100];
    u8 _ff_[0xFF00];
};

struct _SQEZ_Blob_1088KiB {
    u8 _SQEZ_blob_[0x20018];
    u8 _ff_32KiB_[0xEFFE8]; // 0x00660018
};

struct SliceVSBFile {
    u8 _data_[0x90000];
};

////////////////////////////////////////
//
// Flash layout
//
////////////////////////////////////////

AIS ais_bootscript                     @ 0x00000000;
Firmware firmware                      @ 0x00020000;
u8 KORGele2sUSR[0x00010000]            @ 0x00220000;
E2SAllPat_NoKORGHeader e2sallpat_file  @ 0x00230000;
u8 _ff_[0x8000]                        @ 0x00628000;
_Unknown_File_64KiB _UnknownFile1      @ 0x00630000;
_SQEZ_Blob_1088KiB _SQEZ_blob_1088KiB  @ 0x00640000;
SliceVSBFile _SliceVSBFile             @ 0x00750000;
u8 KORGelec2PCM[0x65F020]              @ 0x00800000;