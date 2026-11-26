/* bitten SDK: CoreAudio's types (CoreAudioTypes.h), Darwin's layouts. */
#ifndef BITTEN_COREAUDIOTYPES_H
#define BITTEN_COREAUDIOTYPES_H
#include <stdint.h>

typedef int32_t OSStatus;
typedef double Float64;
typedef float Float32;
typedef uint32_t UInt32;
typedef uint64_t UInt64;
typedef int16_t SInt16;
typedef uint32_t AudioFormatID;
typedef uint32_t AudioFormatFlags;

typedef struct AudioBuffer {
    UInt32 mNumberChannels;
    UInt32 mDataByteSize;
    void *_Nullable mData;
} AudioBuffer;

typedef struct AudioBufferList {
    UInt32 mNumberBuffers;
    AudioBuffer mBuffers[1];
} AudioBufferList;

typedef struct AudioStreamBasicDescription {
    Float64 mSampleRate;
    AudioFormatID mFormatID;
    AudioFormatFlags mFormatFlags;
    UInt32 mBytesPerPacket;
    UInt32 mFramesPerPacket;
    UInt32 mBytesPerFrame;
    UInt32 mChannelsPerFrame;
    UInt32 mBitsPerChannel;
    UInt32 mReserved;
} AudioStreamBasicDescription;

typedef struct SMPTETime {
    SInt16 mSubframes, mSubframeDivisor;
    UInt32 mCounter, mType, mFlags;
    SInt16 mHours, mMinutes, mSeconds, mFrames;
} SMPTETime;

typedef struct AudioTimeStamp {
    Float64 mSampleTime;
    UInt64 mHostTime;
    Float64 mRateScalar;
    UInt64 mWordClockTime;
    SMPTETime mSMPTETime;
    UInt32 mFlags;
    UInt32 mReserved;
} AudioTimeStamp;

enum {
    kAudioFormatLinearPCM = 0x6c70636d, /* 'lpcm' */
    kAudioFormatFlagIsFloat = 1 << 0,
    kAudioFormatFlagIsBigEndian = 1 << 1,
    kAudioFormatFlagIsSignedInteger = 1 << 2,
    kAudioFormatFlagIsPacked = 1 << 3,
    kAudioFormatFlagIsNonInterleaved = 1 << 5,
};
enum { kAudioTimeStampSampleTimeValid = 1 << 0, kAudioTimeStampHostTimeValid = 1 << 1 };

#endif
