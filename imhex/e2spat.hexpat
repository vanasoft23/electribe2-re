#pragma description KORG Electribe 2 Sampler Pattern
#pragma MIME application/e2spat
#pragma magic [ 4B 4F 52 47 00 00 00 00 00 00 00 00 00 00 00 00 65 32 73 61 6D 70 6C 65 72 00 00 00 00 00 00 00 ] @ 0x00
#pragma magic [ 50 54 53 54 ] @ 0x100

struct KORGHeader
{
    char title[0x10];
    char dev_name[0x10];
    u32 version;
    u8 _0[0xdc];
};

struct E2SPatHeader
{
    char ptst_str[0x10];
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

KORGHeader korg_header @ 0x0;
E2SPatHeader pattern_header @ 0x100;
Part parts[16] @ 0x900;