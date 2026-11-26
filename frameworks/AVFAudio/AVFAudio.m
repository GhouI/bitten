/* AVFAudio without an audio device (see the header). A running engine
 * pulls each attached source node every 10 ms, as an output device
 * would, so programs' render callbacks keep time; the audio is dropped. */
#import <AVFAudio/AVFAudio.h>
#include <dispatch/dispatch.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

NSNotificationName const AVAudioEngineConfigurationChangeNotification = @"AVAudioEngineConfigurationChangeNotification";

@implementation AVAudioFormat {
    AudioStreamBasicDescription _asbd;
    AVAudioCommonFormat _common;
    BOOL _interleaved;
}
- (instancetype)initStandardFormatWithSampleRate:(double)rate channels:(AVAudioChannelCount)channels {
    return [self initWithCommonFormat:AVAudioPCMFormatFloat32 sampleRate:rate channels:channels interleaved:NO];
}
- (instancetype)initWithCommonFormat:(AVAudioCommonFormat)format sampleRate:(double)rate
                            channels:(AVAudioChannelCount)channels interleaved:(BOOL)interleaved {
    if (rate <= 0 || channels == 0 || format == AVAudioOtherFormat) return nil;
    if ((self = [super init])) {
        UInt32 bytes = format == AVAudioPCMFormatFloat64 ? 8 : format == AVAudioPCMFormatInt16 ? 2 : 4;
        _common = format;
        _interleaved = interleaved;
        _asbd.mSampleRate = rate;
        _asbd.mFormatID = kAudioFormatLinearPCM;
        _asbd.mFormatFlags = kAudioFormatFlagIsPacked | (format <= AVAudioPCMFormatFloat64 ? kAudioFormatFlagIsFloat
                                                                                         : kAudioFormatFlagIsSignedInteger) |
                             (interleaved ? 0 : kAudioFormatFlagIsNonInterleaved);
        _asbd.mBytesPerFrame = _asbd.mBytesPerPacket = interleaved ? bytes * channels : bytes;
        _asbd.mFramesPerPacket = 1;
        _asbd.mChannelsPerFrame = channels;
        _asbd.mBitsPerChannel = bytes * 8;
    }
    return self;
}
- (instancetype)initWithStreamDescription:(const AudioStreamBasicDescription *)asbd {
    if (!asbd || asbd->mFormatID != kAudioFormatLinearPCM) return nil;
    BOOL f = (asbd->mFormatFlags & kAudioFormatFlagIsFloat) != 0;
    AVAudioCommonFormat c = f ? (asbd->mBitsPerChannel == 64 ? AVAudioPCMFormatFloat64 : AVAudioPCMFormatFloat32)
                              : (asbd->mBitsPerChannel == 16 ? AVAudioPCMFormatInt16 : AVAudioPCMFormatInt32);
    return [self initWithCommonFormat:c sampleRate:asbd->mSampleRate channels:asbd->mChannelsPerFrame
                          interleaved:!(asbd->mFormatFlags & kAudioFormatFlagIsNonInterleaved)];
}
- (id)copyWithZone:(NSZone *)zone { return self; }
- (double)sampleRate { return _asbd.mSampleRate; }
- (AVAudioChannelCount)channelCount { return _asbd.mChannelsPerFrame; }
- (AVAudioCommonFormat)commonFormat { return _common; }
- (BOOL)isInterleaved { return _interleaved; }
- (BOOL)isStandard { return _common == AVAudioPCMFormatFloat32 && !_interleaved; }
- (const AudioStreamBasicDescription *)streamDescription { return &_asbd; }
- (BOOL)isEqual:(id)o {
    if (![o isKindOfClass:[AVAudioFormat class]]) return NO;
    AVAudioFormat *f = o;
    return f.sampleRate == self.sampleRate && f.channelCount == self.channelCount && f.commonFormat == _common &&
           f.isInterleaved == _interleaved;
}
- (NSUInteger)hash { return (NSUInteger)self.sampleRate ^ self.channelCount; }
- (NSString *)description {
    return [NSString stringWithFormat:@"<AVAudioFormat %p: %u ch, %g Hz, %@>", (void *)self, self.channelCount,
            self.sampleRate, self.isStandard ? @"Float32, deinterleaved" : @"PCM"];
}
@end

/* ---- buffers ---- */

@implementation AVAudioBuffer {
@protected
    AVAudioFormat *_format;
    AudioBufferList *_list;
}
- (AVAudioFormat *)format { return _format; }
- (const AudioBufferList *)audioBufferList { return _list; }
- (AudioBufferList *)mutableAudioBufferList { return _list; }
- (id)copyWithZone:(NSZone *)zone { return self; }
@end

@implementation AVAudioPCMBuffer {
    AVAudioFrameCount _capacity, _length;
    void **_channels;
}
- (instancetype)initWithPCMFormat:(AVAudioFormat *)format frameCapacity:(AVAudioFrameCount)capacity {
    if (!format) return nil;
    if ((self = [super init])) {
        _format = format;
        _capacity = capacity;
        UInt32 n = format.isInterleaved ? 1 : format.channelCount;
        UInt32 bpf = format.streamDescription->mBytesPerFrame;
        _list = calloc(1, sizeof(AudioBufferList) + (n ? n - 1 : 0) * sizeof(AudioBuffer));
        _channels = calloc(n, sizeof(void *));
        _list->mNumberBuffers = n;
        for (UInt32 i = 0; i < n; i++) {
            _channels[i] = calloc(capacity ? capacity : 1, bpf);
            _list->mBuffers[i].mNumberChannels = format.isInterleaved ? format.channelCount : 1;
            _list->mBuffers[i].mData = _channels[i];
            _list->mBuffers[i].mDataByteSize = 0;
        }
    }
    return self;
}
- (void)dealloc {
    for (UInt32 i = 0; _list && i < _list->mNumberBuffers; i++) free(_channels[i]);
    free(_channels);
    free(_list);
}
- (AVAudioFrameCount)frameCapacity { return _capacity; }
- (AVAudioFrameCount)frameLength { return _length; }
- (void)setFrameLength:(AVAudioFrameCount)n {
    if (n > _capacity) n = _capacity;
    _length = n;
    for (UInt32 i = 0; i < _list->mNumberBuffers; i++)
        _list->mBuffers[i].mDataByteSize = n * _format.streamDescription->mBytesPerFrame;
}
- (NSUInteger)stride { return _format.isInterleaved ? _format.channelCount : 1; }
- (float *const *)floatChannelData {
    return _format.commonFormat == AVAudioPCMFormatFloat32 ? (float *const *)_channels : NULL;
}
- (int16_t *const *)int16ChannelData {
    return _format.commonFormat == AVAudioPCMFormatInt16 ? (int16_t *const *)_channels : NULL;
}
- (int32_t *const *)int32ChannelData {
    return _format.commonFormat == AVAudioPCMFormatInt32 ? (int32_t *const *)_channels : NULL;
}
@end

/* ---- nodes ---- */

@implementation AVAudioNode {
@package
    __weak AVAudioEngine *_engine;
    AVAudioFormat *_outputFormat;
}
- (AVAudioEngine *)engine { return _engine; }
- (NSUInteger)numberOfInputs { return 1; }
- (NSUInteger)numberOfOutputs { return 1; }
- (AVAudioFormat *)outputFormatForBus:(AVAudioNodeBus)bus {
    return _outputFormat ?: [[AVAudioFormat alloc] initStandardFormatWithSampleRate:48000 channels:2];
}
- (AVAudioFormat *)inputFormatForBus:(AVAudioNodeBus)bus { return [self outputFormatForBus:bus]; }
- (void)reset {}
@end

@implementation AVAudioMixerNode
@synthesize outputVolume = _outputVolume, volume = _volume, pan = _pan;
- (instancetype)init {
    if ((self = [super init])) _outputVolume = _volume = 1;
    return self;
}
@end
@implementation AVAudioOutputNode
- (NSUInteger)numberOfOutputs { return 0; }
@end
@implementation AVAudioInputNode
- (NSUInteger)numberOfInputs { return 0; }
@end

@implementation AVAudioSourceNode {
@package
    AVAudioSourceNodeRenderBlock _render;
    double _sampleTime;
}
@synthesize volume = _volume, pan = _pan;
- (instancetype)initWithRenderBlock:(AVAudioSourceNodeRenderBlock)block {
    return [self initWithFormat:[[AVAudioFormat alloc] initStandardFormatWithSampleRate:48000 channels:2] renderBlock:block];
}
- (instancetype)initWithFormat:(AVAudioFormat *)format renderBlock:(AVAudioSourceNodeRenderBlock)block {
    if ((self = [super init])) {
        _render = [block copy];
        _outputFormat = format;
        _volume = 1;
    }
    return self;
}
- (NSUInteger)numberOfInputs { return 0; }

/* Ask the block for frames into a scratch buffer, and drop them. */
- (void)_bn_pull:(AVAudioFrameCount)frames {
    if (!_render || !frames) return;
    AVAudioPCMBuffer *b = [[AVAudioPCMBuffer alloc] initWithPCMFormat:[self outputFormatForBus:0] frameCapacity:frames];
    b.frameLength = frames;
    AudioTimeStamp ts;
    memset(&ts, 0, sizeof ts);
    ts.mSampleTime = _sampleTime;
    ts.mFlags = kAudioTimeStampSampleTimeValid;
    BOOL silence = NO;
    _render(&silence, &ts, frames, b.mutableAudioBufferList);
    _sampleTime += frames;
}
@end

@implementation AVAudioEngine {
    NSMutableSet<AVAudioNode *> *_nodes;
    AVAudioMixerNode *_mixer;
    AVAudioOutputNode *_output;
    AVAudioInputNode *_input;
    dispatch_source_t _timer;
    double _lastTime;
}
- (instancetype)init {
    if ((self = [super init])) {
        _nodes = [NSMutableSet set];
        _mixer = [AVAudioMixerNode new];
        _output = [AVAudioOutputNode new];
        _input = [AVAudioInputNode new];
        _output->_engine = _mixer->_engine = _input->_engine = self;
    }
    return self;
}
- (void)dealloc { [self stop]; }
- (AVAudioMixerNode *)mainMixerNode { return _mixer; }
- (AVAudioOutputNode *)outputNode { return _output; }
- (AVAudioInputNode *)inputNode { return _input; }
- (NSSet<AVAudioNode *> *)attachedNodes {
    NSMutableSet *s = [_nodes mutableCopy];
    [s addObject:_mixer];
    [s addObject:_output];
    return s;
}
- (BOOL)isRunning { return _timer != nil; }
- (void)attachNode:(AVAudioNode *)node {
    if (!node) return;
    [_nodes addObject:node];
    node->_engine = self;
}
- (void)detachNode:(AVAudioNode *)node {
    if (!node) return;
    [_nodes removeObject:node];
    node->_engine = nil;
}
- (void)connect:(AVAudioNode *)a to:(AVAudioNode *)b format:(AVAudioFormat *)format {
    [self connect:a to:b fromBus:0 toBus:0 format:format];
}
- (void)connect:(AVAudioNode *)a to:(AVAudioNode *)b fromBus:(AVAudioNodeBus)bus1 toBus:(AVAudioNodeBus)bus2
         format:(AVAudioFormat *)format {
    if (format && ![a isKindOfClass:[AVAudioSourceNode class]]) a->_outputFormat = format;
}
- (void)disconnectNodeOutput:(AVAudioNode *)node {}
- (void)disconnectNodeInput:(AVAudioNode *)node {}
- (void)prepare {}

static double now_seconds(void) {
    struct timespec t;
    clock_gettime(CLOCK_MONOTONIC, &t);
    return t.tv_sec + t.tv_nsec / 1e9;
}

- (BOOL)startAndReturnError:(NSError **)outError {
    if (_timer) return YES;
    _lastTime = now_seconds();
    _timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_global_queue(0, 0));
    dispatch_source_set_timer(_timer, dispatch_time(DISPATCH_TIME_NOW, 10 * NSEC_PER_MSEC), 10 * NSEC_PER_MSEC,
                              NSEC_PER_MSEC);
    __weak AVAudioEngine *weakSelf = self;
    dispatch_source_set_event_handler(_timer, ^{
        AVAudioEngine *e = weakSelf;
        if (!e) return;
        double t = now_seconds(), dt = t - e->_lastTime;
        e->_lastTime = t;
        NSArray *nodes;
        @synchronized(e) { nodes = e->_nodes.allObjects; }
        for (AVAudioNode *n in nodes) {
            if (![n isKindOfClass:[AVAudioSourceNode class]]) continue;
            AVAudioSourceNode *s = (AVAudioSourceNode *)n;
            double frames = dt * [s outputFormatForBus:0].sampleRate;
            [s _bn_pull:(AVAudioFrameCount)(frames > 48000 ? 48000 : frames)];
        }
    });
    dispatch_resume(_timer);
    return YES;
}
- (void)pause { [self stop]; }
- (void)stop {
    if (!_timer) return;
    dispatch_source_cancel(_timer);
    _timer = nil;
}
- (void)reset {}
@end
