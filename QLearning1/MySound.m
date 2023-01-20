//
//  MySound.m
//  QLearning1 (originally developed for LoversFlow)
//
//  Created by Tatsuo Unemi on 2017/09/19.
//  Copyright © 2017, Tatsuo Unemi. All rights reserved.
//

#import <AudioToolbox/AudioToolbox.h>
#import <AudioUnit/AudioUnit.h>
#import "MySound.h"
#import "AppDelegate.h"
#define SAMPLE_RATE 44100
#define QUE_LENGTH 256

typedef struct { const float *buf; int nCh; UInt32 nFrames; } SndSrcInfo;
typedef enum { RenderModeNormal, RenderModeTest } RenderMode;
static AudioUnit output = NULL;
static BOOL isRunning = NO;
static NSLock *soundBufLock = nil;
static NSRange sndQIdx = {0, 0};
static SoundQue sndQue[QUE_LENGTH], envSndQ[NGridW], testSndQ;
static CGFloat sndAmp = 1.;
static RenderMode renderMode = RenderModeNormal, reqRndrMode = RenderModeNormal;
static SndSrcInfo testSSInfo = { NULL, 2, 0 };
static NSString *testSoundPath = nil;
static NSMutableDictionary<NSString *, MySound *> *loadedSounds;

@interface MySound ()
@property NSUInteger refCount;
@property (readonly) NSData *data;
@property (readonly) int nChannels;
@end

@implementation MySound
- (instancetype)initWithPath:(NSString *)path nCh:(int)nCh {
	if (!(self = [super init])) return nil;
	OSStatus err;
	@try {
		NSURL *url = [NSURL fileURLWithPath:path];
		if (!url) @throw [NSString stringWithFormat:@"Could not make URL for %@.", path];
		ExtAudioFileRef file;
		err = ExtAudioFileOpenURL((__bridge CFURLRef)url, &file);
		if (err) @throw [NSString stringWithFormat:@"Could not open %@.", url.path];
		AudioStreamBasicDescription sbDesc = {SAMPLE_RATE, kAudioFormatLinearPCM,
			kAudioFormatFlagIsFloat, sizeof(float) * nCh,
			1, sizeof(float) * nCh, nCh, sizeof(float) * 8 };
		if ((err = ExtAudioFileSetProperty(file, kExtAudioFileProperty_ClientDataFormat,
			sizeof(sbDesc), &sbDesc)))
			@throw @"ExtAudioFileSetProperty ClientDataFormat";
		UInt32 dataSize = sizeof(sbDesc);
		if ((err = ExtAudioFileGetProperty(file, kExtAudioFileProperty_FileDataFormat,
			&dataSize, &sbDesc))) @throw @"ExtAudioFileGetProperty FileDataFormat";
		SInt64 nFrames = 0;
		dataSize = sizeof(nFrames);
		if ((err = ExtAudioFileGetProperty(file, kExtAudioFileProperty_FileLengthFrames,
			&dataSize, &nFrames))) @throw @"ExtAudioFileGetProperty FileLengthFrames";
		if (sbDesc.mSampleRate != SAMPLE_RATE) nFrames *= SAMPLE_RATE / sbDesc.mSampleRate;
		UInt32 bufSize = (UInt32)(sizeof(float) * nCh * nFrames);
		NSMutableData *newBuf = [NSMutableData dataWithLength:bufSize];
		if (newBuf == nil)
			@throw [NSString stringWithFormat:@"allocate buffer %d bytes.", bufSize];
		AudioBufferList bufList = {1, {nCh, bufSize, newBuf.mutableBytes}};
		UInt32 nbFrames = (UInt32)nFrames;
		if ((err = ExtAudioFileRead(file, &nbFrames, &bufList)))
			@throw @"ExtAudioFileRead";
		if ((err = ExtAudioFileDispose(file))) @throw @"ExtAudioFileDispose";
		_data = newBuf;
		_nChannels = nCh;
#ifdef DEBUG
NSLog(@"%@: %d ch., %d frames loaded", path.lastPathComponent, nCh, nbFrames);
#endif
	} @catch (NSString *msg) {
		err_msg(msg, err, NO);
		return nil;
	} @finally { return self; }
}
@end

static void release_mySound(NSString *path) {
	if (path.length == 0) return;
	MySound *orgSnd = loadedSounds[path];
	if (orgSnd != nil && (-- orgSnd.refCount) == 0) loadedSounds[path] = nil;
}
static BOOL get_sound_buf(NSString *path, int nCh, const float **buf, UInt32 *nFrames) {
	if (path.length == 0) { *buf = NULL; return YES; }
	MySound *mySnd = loadedSounds[path];
	if (mySnd == nil) {
		mySnd = [MySound.alloc initWithPath:path nCh:nCh];
		if (mySnd == nil) return NO;
		if (loadedSounds == nil) loadedSounds = NSMutableDictionary.new;
		loadedSounds[path] = mySnd;
	}
	mySnd.refCount ++;
	*buf = mySnd.data.bytes;
	*nFrames = (int)mySnd.data.length / sizeof(float) / nCh;
	return YES;
}
static void get_sound_data(SoundSrc *sp, OSStatus *err) {
	*err = noErr;
	if ([sp->v.path isEqualToString:sp->loaded]) return;
	if (!get_sound_buf(sp->v.path, sp->nCh, &sp->buf, &sp->nFrames)) return;
	release_mySound(sp->loaded);
	sp->loaded = sp->v.path;
}
static simd_float2 stereo_sample(SoundQue *p, SndSrcInfo *ssInfo, BOOL repeat) {
	p->fPos += p->pitchShift;
	if (repeat && p->fPos >= ssInfo->nFrames) p->fPos -= ssInfo->nFrames;
	long fPos = floor(p->fPos);
	float fPosR = p->fPos - fPos;
	if (fPos < 0 || fPos >= ssInfo->nFrames) return 0.;
	simd_float2 amp = {
		(p->pan < 0.)? 1. : 1. - p->pan,
		(p->pan > 0.)? 1. : 1. + p->pan };
	amp *= p->amp;
	if (ssInfo->nCh == 2) {
		simd_float2 *src = (simd_float2 *)ssInfo->buf;
		return (src[fPos] * (1. - fPosR) +
			((fPos + 1 < ssInfo->nFrames)? src[fPos + 1] * fPosR : 0.)) * amp;
	} else return (ssInfo->buf[fPos] * (1. - fPosR) +
		((fPos + 1 < ssInfo->nFrames)? ssInfo->buf[fPos + 1] * fPosR : 0.)) * amp;
}
static void set_adjusted_sample(float *bL, float *bR, simd_float2 smp) {
	float maxS = simd_reduce_max(simd_abs(smp));
	sndAmp = (maxS * sndAmp > 1.)? 1. / maxS :
		sndAmp + (((maxS > 1.)? 1. / maxS : 1.) - sndAmp) / SAMPLE_RATE;
	smp *= sndAmp;
	*bL = smp.x;
	*bR = smp.y;
}
static OSStatus my_render_callback(void *inRefCon,
	AudioUnitRenderActionFlags *ioActionFlags, const AudioTimeStamp *inTimeStamp,
	UInt32 inBusNumber, UInt32 inNumberFrames, AudioBufferList *ioData) {
	float *data0 = ioData->mBuffers[0].mData, *data1 = ioData->mBuffers[1].mData;
	if (sndQIdx.length == 0 && sndData[SndEnvNoise].buf == NULL) {
		memset(data0, 0, inNumberFrames * sizeof(float));
		memset(data1, 0, inNumberFrames * sizeof(float));
		return noErr;
	}
	[soundBufLock lock];
	for (NSInteger i = 0; i < inNumberFrames; i ++) {
		simd_float2 smp = { 0., 0. };
		SoundSrc *sndDt = &sndData[SndEnvNoise];
		SndSrcInfo ssInfo = {sndDt->buf, sndDt->nCh, sndDt->nFrames};
		for (NSInteger j = 0; j < NGridW; j ++)
			smp += stereo_sample(&envSndQ[j], &ssInfo, YES);
		smp /= NGridW / 1.5;
		for (NSInteger j = 0; j < sndQIdx.length; j ++) {
			SoundQue *sq = &sndQue[(sndQIdx.location + j) % QUE_LENGTH];
			sndDt = &sndData[sq->type];
			ssInfo = (SndSrcInfo){sndDt->buf, sndDt->nCh, sndDt->nFrames};
			smp += stereo_sample(sq, &ssInfo, NO);
		}
		set_adjusted_sample(&data0[i], &data1[i], smp);
	}
	NSInteger i = 0;
	for (NSInteger j = 0; j < sndQIdx.length; j ++) {
		SoundQue *p = &sndQue[(sndQIdx.location + j) % QUE_LENGTH];
		if (p->fPos < sndData[p->type].nFrames) {
			if (i == j) i ++;
			else sndQue[(sndQIdx.location + (i ++)) % QUE_LENGTH] = *p;
		}
	}
	sndQIdx.length = i;
	[soundBufLock unlock];
	return noErr;
}
static OSStatus test_render_callback(void *inRefCon,
	AudioUnitRenderActionFlags *ioActionFlags, const AudioTimeStamp *inTimeStamp,
	UInt32 inBusNumber, UInt32 inNumberFrames, AudioBufferList *ioData) {
	float *data0 = ioData->mBuffers[0].mData, *data1 = ioData->mBuffers[1].mData;
	if (testSSInfo.buf == NULL) {
		memset(data0, 0, inNumberFrames * sizeof(float));
		memset(data1, 0, inNumberFrames * sizeof(float));
		return noErr;
	}
	[soundBufLock lock];
	for (NSInteger i = 0; i < inNumberFrames; i ++)
		set_adjusted_sample(&data0[i], &data1[i],
			stereo_sample(&testSndQ, &testSSInfo, YES));
	[soundBufLock unlock];
	return noErr;
}
static OSStatus set_render_callback(AURenderCallback callback) {
	AURenderCallbackStruct auCallback;
	auCallback.inputProc = callback;
	return AudioUnitSetProperty(output, kAudioUnitProperty_SetRenderCallback,
		kAudioUnitScope_Input, 0, &auCallback, sizeof(AURenderCallbackStruct));
}
BOOL init_audio_out(void) {
	if (output) return YES;
	OSStatus err = noErr;
	for (SoundType type = 0; type < NVoices; type ++) sndData[type].buf = NULL;
	@try {
		AudioComponentDescription desc = {kAudioUnitType_Output,
			kAudioUnitSubType_DefaultOutput, kAudioUnitManufacturer_Apple, 0, 0};
		AudioComponent audioComponent = AudioComponentFindNext(NULL, &desc);
		double sampleRate = SAMPLE_RATE;
		if (!audioComponent) @throw @"AudioComponent Failed.";
		if ((err = AudioComponentInstanceNew(audioComponent, &output)))
			@throw @"AudioUnit Component Failed.";
		AURenderCallbackStruct auCallback;
		auCallback.inputProc = my_render_callback;
		if ((err = set_render_callback(my_render_callback)))
			@throw @"AudioUnitSetProperty RenderCallback";
		if ((err = AudioUnitSetProperty(output, kAudioUnitProperty_SampleRate,
			kAudioUnitScope_Input, 0, &sampleRate, sizeof(double))))
			@throw @"AudioUnitSetProperty SampleRate";
		if ((err = AudioUnitInitialize(output))) @throw @"AudioUnitInitialize";
		soundBufLock = NSLock.new;
		soundBufLock.name = @"Sound buffer lock";
	} @catch (NSString *msg) {
		if (output) {
			AudioComponentInstanceDispose(output);
			output = NULL;
		}
		err_msg(msg, err, NO);
		return NO;
	}
	for (int i = 0; i < NGridW; i ++)
		envSndQ[i] = (SoundQue){SndEnvNoise, 1.,
			(float)i / (NGridW - 1) * 1.8 - .9, 1., 0};
	return YES;
}
static void check_sound_changed(SoundType sndType) {
	SoundSrc *s = &sndData[sndType];
	if ([s->loaded isEqualToString:s->v.path]) return;
	[soundBufLock lock];
	OSStatus err;
	@try { get_sound_data(&sndData[sndType], &err); }
	@catch (NSString *msg) { err_msg(msg, err, NO); }
	[soundBufLock unlock];
}
void change_sound_data(SoundType sndType, NSString *name) {
	SoundSrc *s = &sndData[sndType];
	if ([s->v.path isEqualToString:name]) return;
	s->v.path = name;
	if (isRunning) check_sound_changed(sndType);
}
void start_audio_out(void) {
	if (!output) return;
	if (renderMode != reqRndrMode) {
		stop_audio_out();
		OSStatus err;
		@try {
			if ((err = AudioUnitUninitialize(output)))
				@throw @"AudioUnitUninitialize";
			AudioUnitRenderProc proc = (reqRndrMode == RenderModeNormal)?
				my_render_callback : test_render_callback;
			if ((err = set_render_callback(proc)))
				@throw @"AudioUnitSetProperty RenderCallback";
			if ((err = AudioUnitInitialize(output)))
				@throw @"AudioUnitInitialize";
			renderMode = reqRndrMode;
		} @catch (NSString *msg) {
			err_msg(msg, err, NO); return;
		}
	} else if (isRunning) return;
	OSStatus err;
	if ((err = AudioOutputUnitStart(output)) != noErr)
		err_msg(@"AudioOutputUnitStart", err, NO);
	else {
		isRunning = YES;
		if (renderMode == RenderModeNormal)
			for (SoundType type = 0; type < NVoices; type ++)
				check_sound_changed(type);
	}
}
void stop_audio_out(void) {
	if (!output || !isRunning) return;
	OSStatus err;
	if ((err = AudioOutputUnitStop(output)) != noErr)
		err_msg(@"AudioOutputUnitStop", err, NO);
	else isRunning = NO;
}
void reset_audio_events(void) {
	sndQIdx = (NSRange){0, 0};
	sndAmp = 0.;
}
void set_audio_events(SoundQue *info) {
	if (renderMode != RenderModeNormal) return;
	[soundBufLock lock];
	sndQue[NSMaxRange(sndQIdx) % QUE_LENGTH] = *info;
	if (sndQIdx.length < QUE_LENGTH) sndQIdx.length ++;
	else sndQIdx.location = (sndQIdx.location + 1) % QUE_LENGTH;
	[soundBufLock unlock];
}
void set_audio_env_params(SoundEnvParam *prm) {
	if (renderMode != RenderModeNormal) return;
	for (NSInteger i = 0; i < NGridW; i ++) {
		envSndQ[i].pitchShift = prm[i].pitchShift;
		envSndQ[i].amp = prm[i].amp;
	}
}
void enter_test_mode(NSString *path, float pm, float vol) {
	if (!output) return;
	stop_audio_out();
	reqRndrMode = RenderModeTest;
	testSndQ = (SoundQue){ -1, powf(2.f, pm), 0., vol, 0 };
	if (get_sound_buf(path, 2, &testSSInfo.buf, &testSSInfo.nFrames)) {
		if (testSoundPath != nil) release_mySound(testSoundPath);
		testSoundPath = path;
		start_audio_out();
	}
}
void exit_test_mode(void) {
	if (!output) return;
	stop_audio_out();
	reqRndrMode = RenderModeNormal;
}
void set_test_mode_pm(float pm) { testSndQ.pitchShift = powf(2.f, pm); }
void set_test_mode_vol(float vol) { testSndQ.amp = vol; }
