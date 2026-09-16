#pragma description KORG Electribe 2 Sampler e2Sample.all
#pragma MIME application/e2s-sample-all
#pragma magic [ 65 32 73 20 73 61 6D 70 6C 65 20 61 6C 6C 1A 00 ] @ 0x00

#pragma pattern_limit 231072

#include <std/mem.pat>

//
// BEGIN WAV stuff
//

struct RiffHeader {
  char ckID[4] [[comment("Container Signature"), name("RIFF Header Signature")]];
  u32  ckSize [[comment("Size of RIFF Header"), name("RIFF Chunk Size")]];
  char format[4] [[comment("RIFF format"), name("WAVE Header Signature")]];
};

struct WaveChunk {
  char chunkId[4];
  u32  chunkSize;
};

enum WaveFormatType : u16 {
  Unknown,
  PCM,
  MS_ADPCM,
  IEEEFloatingPoint,
  ALAW = 6,
  MULAW,
  IMA_ADPCM  = 0x11,
  GSM610     = 0x31,
  MPEG       = 0x50,
  MPEGLAYER3 = 0x55,
};

struct WaveFormat {
  WaveFormatType formatTag;
  u16            channels;
  u32            samplesPerSec [[comment("Sample Frequency")]];
  u32            avgBytesPerSec [[comment("BPS - Used to estimate buffer size")]];
  u16            blockAlign;
};

struct WaveFormatEx {
  u16 bitsPerSample;
  u16 extendedDataSize;
};

struct WaveFormatExDummy {
  u16 bitsPerSample;
  u16 extendedDataSize;
  u8  extendedData[extendedDataSize];
};

struct WaveFormatPCM {
  u16 bitsPerSample;
};

struct WaveMSADPCMCoefSet {
  s16 coef1;    
  s16 coef2;
};

struct WaveFormatMSADPCM : WaveFormatEx {
  u16                samplesPerBlock;
  u16                numCoef;
  WaveMSADPCMCoefSet coef[numCoef];
};

bitfield WaveMPEGLayer {
  Layer1  : 1;
  Layer2  : 1;
  Layer3  : 1;
  padding : 13;
};

bitfield WaveMPEGMode {
  Stereo : 1;
  JointStereo : 1;
  DualChannel : 1;
  SingleChannel : 1;
  padding : 12;
};

bitfield WaveMPEGFlags {
  PrivateBit : 1;
  Copyright : 1;
  OriginalHome : 1;
  ProtectionBit : 1;
  IdMPEG1 : 1;
  padding : 11;
};

struct WaveFormatIEEEFloatingPoint : WaveFormatPCM {

};

struct WaveFormatMPEG : WaveFormatEx {
  WaveMPEGLayer    headLayersUsed;
  u32              headBitrate;
  WaveMPEGMode     headMode;
  u16              headModeExt;
  u16              headEmphasis;
  WaveMPEGFlags    headFlags;
  u32              PTSLow;
  u32              PTSHigh;
};

enum WaveFormatMPEGLayer3Flags : u32 {
  MPEGLAYER3_FLAG_PADDING_ISO,
  MPEGLAYER3_FLAG_PADDING_ON,
  MPEGLAYER3_FLAG_PADDING_OFF
};

struct WaveFormatMPEGLayer3 : WaveFormatEx {
  u16                       id;
  WaveFormatMPEGLayer3Flags flags;
  u16                       blockSize;
  u16                       framesPerBlock;
  u16                       codecDelay;
};

struct WaveFact {
  u32 uncompressedSize;
};

enum SampleLookupType : u32 {
  TYPE_LOOP_FORWARD,
  TYPE_LOOP_ALTERNATE,
  TYPE_LOOP_BACKWARD,
};

struct SampleLookup {
  u32              id;
  SampleLookupType type;
  u32              start;
  u32              end;
  u32              fraction;
  u32              playCount;
};

struct WaveSample {
  u32 manufacturer;
  u32 product;
  u32 samplePeriod;
  u32 MIDIUnityNote;
  u32 MIDIPitchFraction;
  u32 SMPTEFormat;
  u32 SMPTEOffset;
  u32 numSampleLoops;
  u32 sampleLoopsSize;

  SampleLookup lookups[numSampleLoops];
};

struct WaveCuePoint {
  u32  indentifier;
  u32  position;
  char chunkID[4];
  u32  chunkStart;
  u32  blockStart;
  u32  sampleOffset;
};

struct WaveCue {
  u32          numCuePoints;
  WaveCuePoint cuePoints[numCuePoints];
};

struct WaveLabel {
  u32  id;
  char text[];
  padding[sizeof(text) % 2];
};

using WaveNote = WaveLabel;

struct WaveListItem : WaveChunk {
  if (chunkId == "labl") {
    WaveLabel label;
  } else if (chunkId == "note") {
    WaveNote note;
  } else {
    padding[(chunkSize + 1) >> 1 << 1];
  }
};

u64 listEnd;

struct WaveList {
  char type[4];

  WaveListItem item[while ($ < listEnd)];
};

u32 paddedChunkSize;





enum EsliCategory : s16 {
  ANALOG = 0,
  AUDIO_IN,
  KICK,
  SNARE,
  CLAP,
  HIHAT,
  CYMBAL,
  HITS,
  SHOTS,
  VOICE,
  SE,
  FX,
  TOM,
  PERC,
  PHRASE    ,
  LOOP,
  PCM,
  USER
};

struct SliceData
{
    s32 start;
    u32 length;
    u32 attackLength;
    u32 amplitude;
};

struct WaveEsliData
{
    u16 sampleID;
    char sampleName[16];
    EsliCategory category;
    u16 absoluteSampleNumber;
    padding[12]; //u8 fixedString[12];
    s16 playbackPeriod;
    u16 volume;
    padding[2];
    u32 startPoint;
    u32 loopPoint;
    u32 endPoint;
    u8 oneShot;
    padding[7];
    u32 dataLengthWaveFile;
    padding[1];
    u8 stereo;
    u8 playLevel;
    padding[5];
    u32 sampleRate;
    padding[1];
    s8 sampleTune;
    u16 sampleIDAgain;
    
    //u8 endPadding[1092];
    SliceData slicesData[64];
    u8 slicesActiveSteps[64];
    u8 slicingNumSteps;
    u8 slicingBeat;
    u8 slicesNumActiveSteps;
    padding[1];
};



struct WavData {
  WaveChunk chunk;
  paddedChunkSize = (chunk.chunkSize + 1) >> 1 << 1;

  if (chunk.chunkId == "fmt ") {
    WaveFormat fmt;

    if (fmt.formatTag == WaveFormatType::PCM) {
      WaveFormatPCM pcmExtraData;
      padding[paddedChunkSize - sizeof(fmt) - sizeof(pcmExtraData)];
    } else if (fmt.formatTag == WaveFormatType::MS_ADPCM) {
      WaveFormatMSADPCM msAdpcmExtraData;
      padding[paddedChunkSize - sizeof(fmt) - sizeof(msAdpcmExtraData)];
    } else if (fmt.formatTag == WaveFormatType::MPEG) {
      WaveFormatMPEG mpegExtraData;
      padding[paddedChunkSize - sizeof(fmt) - sizeof(mpegExtraData)];
    } else if (fmt.formatTag == WaveFormatType::MPEGLAYER3) {
      WaveFormatMPEGLayer3 mpegLayer3ExtraData;
      padding[paddedChunkSize - sizeof(fmt) - sizeof(mpegLayer3ExtraData)];
    } else if (fmt.formatTag == WaveFormatType::IEEEFloatingPoint) {
        WaveFormatIEEEFloatingPoint ieeFloatingPointExtraData;
        padding[paddedChunkSize - sizeof(fmt) - sizeof(ieeFloatingPointExtraData)];
    } else {
      WaveFormatExDummy unknown;
      padding[paddedChunkSize - sizeof(fmt) - sizeof(unknown)];
    }
  } else if (chunk.chunkId == "data") {
    //padding[paddedChunkSize];
    s16 samples[paddedChunkSize / 2];
  } else if (chunk.chunkId == "fact") {
    WaveFact fact;
    padding[paddedChunkSize - sizeof(fact)];
  } else if (chunk.chunkId == "smpl") {
    WaveSample smpl;
    padding[paddedChunkSize - sizeof(smpl)];
  } else if (chunk.chunkId == "cue ") {
    WaveCue cue;
    padding[paddedChunkSize - sizeof(cue)];
  } else if (chunk.chunkId == "LIST") {
    listEnd = $ + chunk.chunkSize;
    WaveList list;
    padding[paddedChunkSize % 1];
  } else if (chunk.chunkId == "korg") {
    WaveChunk esliChunk;
    WaveEsliData esliData;
  } else {
    padding[paddedChunkSize];
  }
};


struct WaveFile
{
    RiffHeader header;
    WavData fmtChunk;
    WavData dataChunk;
    WavData korgChunk;
};

//
// END WAV stuff
//



struct E2sSampleFile
{
    char name[14];
    padding[88-14];
    u32 absoluteWavFileAddrs[1002];
    
    //WaveFile f[1];
    WaveFile waveFile[while(!std::mem::eof())];
};


E2sSampleFile e2sSampleFile @ 0x00;
