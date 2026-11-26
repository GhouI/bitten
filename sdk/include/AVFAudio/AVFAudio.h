/* AVFAudio's engine without an audio device: an engine starts and pulls
 * its source nodes in real time, and the samples go nowhere. Formats and
 * PCM buffers are real (deinterleaved float32 by default). */
#ifndef BITTEN_AVFAUDIO_H
#define BITTEN_AVFAUDIO_H
#import <Foundation/Foundation.h>
#include <CoreAudio/CoreAudioTypes.h>

#pragma clang assume_nonnull begin

typedef uint32_t AVAudioFrameCount;
typedef uint32_t AVAudioPacketCount;
typedef uint32_t AVAudioChannelCount;
typedef NSUInteger AVAudioNodeBus;
typedef double AVAudioFramePosition;

typedef NS_ENUM(NSUInteger, AVAudioCommonFormat) {
    AVAudioOtherFormat = 0,
    AVAudioPCMFormatFloat32 = 1,
    AVAudioPCMFormatFloat64 = 2,
    AVAudioPCMFormatInt16 = 3,
    AVAudioPCMFormatInt32 = 4,
};

extern NSNotificationName const AVAudioEngineConfigurationChangeNotification;

@interface AVAudioFormat : NSObject <NSCopying>
- (nullable instancetype)initStandardFormatWithSampleRate:(double)sampleRate channels:(AVAudioChannelCount)channels;
- (nullable instancetype)initWithCommonFormat:(AVAudioCommonFormat)format sampleRate:(double)sampleRate
                                     channels:(AVAudioChannelCount)channels interleaved:(BOOL)interleaved;
- (nullable instancetype)initWithStreamDescription:(const AudioStreamBasicDescription *)asbd;
@property (readonly) double sampleRate;
@property (readonly) AVAudioChannelCount channelCount;
@property (readonly) AVAudioCommonFormat commonFormat;
@property (readonly, getter=isInterleaved) BOOL interleaved;
@property (readonly, getter=isStandard) BOOL standard;
@property (readonly) const AudioStreamBasicDescription *streamDescription;
@end

@interface AVAudioBuffer : NSObject <NSCopying>
@property (readonly) AVAudioFormat *format;
@property (readonly) const AudioBufferList *audioBufferList;
@property (readonly) AudioBufferList *mutableAudioBufferList;
@end

@interface AVAudioPCMBuffer : AVAudioBuffer
- (nullable instancetype)initWithPCMFormat:(AVAudioFormat *)format frameCapacity:(AVAudioFrameCount)frameCapacity;
@property (readonly) AVAudioFrameCount frameCapacity;
@property AVAudioFrameCount frameLength;
@property (readonly) NSUInteger stride;
@property (readonly) float *const _Nonnull *_Nullable floatChannelData;
@property (readonly) int16_t *const _Nonnull *_Nullable int16ChannelData;
@property (readonly) int32_t *const _Nonnull *_Nullable int32ChannelData;
@end

@class AVAudioEngine;
@interface AVAudioNode : NSObject
@property (nullable, readonly, weak) AVAudioEngine *engine;
@property (readonly) NSUInteger numberOfInputs, numberOfOutputs;
- (AVAudioFormat *)outputFormatForBus:(AVAudioNodeBus)bus;
- (AVAudioFormat *)inputFormatForBus:(AVAudioNodeBus)bus;
- (void)reset;
@end

@interface AVAudioMixerNode : AVAudioNode
@property float outputVolume, volume, pan;
@end
@interface AVAudioOutputNode : AVAudioNode
@end
@interface AVAudioInputNode : AVAudioNode
@end

typedef OSStatus (^AVAudioSourceNodeRenderBlock)(BOOL *isSilence, const AudioTimeStamp *timestamp,
                                                 AVAudioFrameCount frameCount, AudioBufferList *outputData);
@interface AVAudioSourceNode : AVAudioNode
- (instancetype)initWithRenderBlock:(AVAudioSourceNodeRenderBlock)block;
- (instancetype)initWithFormat:(AVAudioFormat *)format renderBlock:(AVAudioSourceNodeRenderBlock)block;
@property float volume, pan;
@end

@interface AVAudioEngine : NSObject
@property (readonly) AVAudioMixerNode *mainMixerNode;
@property (readonly) AVAudioOutputNode *outputNode;
@property (readonly) AVAudioInputNode *inputNode;
@property (readonly, getter=isRunning) BOOL running;
@property (readonly) NSSet<AVAudioNode *> *attachedNodes;
- (void)attachNode:(AVAudioNode *)node;
- (void)detachNode:(AVAudioNode *)node;
- (void)connect:(AVAudioNode *)node1 to:(AVAudioNode *)node2 format:(nullable AVAudioFormat *)format;
- (void)connect:(AVAudioNode *)node1 to:(AVAudioNode *)node2 fromBus:(AVAudioNodeBus)bus1 toBus:(AVAudioNodeBus)bus2
         format:(nullable AVAudioFormat *)format;
- (void)disconnectNodeOutput:(AVAudioNode *)node;
- (void)disconnectNodeInput:(AVAudioNode *)node;
- (void)prepare;
- (BOOL)startAndReturnError:(NSError **)outError;
- (void)pause;
- (void)stop;
- (void)reset;
@end

#pragma clang assume_nonnull end
#endif
