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
#define SAMPLE_RATE 44100
#define QUE_LENGTH 256

static AudioUnit output = NULL;
static BOOL isRunning = NO;
static NSLock *soundBufLock = nil;
static NSRange sndQIdx = {0, 0};
static SoundQue sndQue[QUE_LENGTH], envSndQ[NGridW];
static CGFloat sndAmp = 1.;
static SoundSrc *sndData;
static NSString *reqSndName[NVoices];

static NSString *pathFmt = @"/Applications/iMovie.app/Contents/Resources/%@ Sound Effects/%@";
static void get_sound_data(SoundSrc *sp) {
	OSStatus err = noErr;
	@try {
		NSURL *url = (sp->type == nil)?
//			[NSBundle.mainBundle URLForResource:sp->name withExtension:@"aac"] :
			[NSURL fileURLWithPath:
				[NSString stringWithFormat:@"/System/Library/Sounds/%@.aiff", sp->name]] :
			[NSURL fileURLWithPath:[NSString stringWithFormat:pathFmt, sp->type, sp->name]];
		if (!url) @throw [NSString stringWithFormat:@"Could not find %@.aac.", sp->name];
		ExtAudioFileRef file;
		err = ExtAudioFileOpenURL((__bridge CFURLRef)url, &file);
		if (err) @throw [NSString stringWithFormat:@"Could not open %@.", url.path];
		AudioStreamBasicDescription sbDesc = {SAMPLE_RATE, kAudioFormatLinearPCM,
			kAudioFormatFlagIsFloat, sizeof(float) * sp->nCh,
			1, sizeof(float) * sp->nCh, sp->nCh, sizeof(float) * 8 };
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
		UInt32 bufSize = (UInt32)(sizeof(float) * sp->nCh * nFrames);
		float *newBuf;
		if ((newBuf = malloc(bufSize)) == NULL)
			@throw [NSString stringWithFormat:@"malloc buffer %d bytes.", bufSize];
		AudioBufferList bufList = {1, {sp->nCh, bufSize, newBuf}};
		UInt32 nbFrames = (UInt32)nFrames;
		NSString *errStr = @"";
		if ((err = ExtAudioFileRead(file, &nbFrames, &bufList))) {
			errStr = @"ExtAudioFileRead";
			free(newBuf);
		} else {
			sp->nFrames = nbFrames;
			if (sp->buf != NULL) free(sp->buf);
			sp->buf = newBuf;
#ifdef DEBUG
NSLog(@"%@: %d ch., %d frames loaded", sp->name, sp->nCh, sp->nFrames);
#endif
		}
		if ((err = ExtAudioFileDispose(file)))
			errStr = [errStr stringByAppendingString:@"ExtAudioFileDispose"];
		if (errStr.length > 0) @throw errStr;
	} @catch (NSString *msg) { err_msg(msg, err, NO); }
}
static float sound_sample(UInt32 nCh, SoundSrc *sndDt, long fPos, float fPosR) {
	return ((fPos < 0)? 0. : sndDt->buf[fPos]) * (1. - fPosR) +
		((fPos + nCh >= sndDt->nFrames * nCh)? 0 : sndDt->buf[fPos + nCh]) * fPosR;
}
static void add_sample(SoundQue *p, float *smp, BOOL repeat) {
	SoundSrc *sndDt = &sndData[p->type];
	p->fPos += p->pitchShift;
	if (repeat && p->fPos >= sndDt->nFrames) p->fPos -= sndDt->nFrames;
	long fPos = floor(p->fPos);
	float fPosR = p->fPos - fPos;
	if (fPos >= sndDt->nFrames) return;
	float ampL = ((p->pan < 0.)? 1. : 1. - p->pan);
	float ampR = ((p->pan > 0.)? 1. : 1. + p->pan);
	if (sndDt->nCh == 1) {
		float s = sound_sample(1, sndDt, fPos, fPosR) * p->amp;
		smp[0] += s * ampL;
		smp[1] += s * ampR;
	} else {
		smp[0] += sound_sample(2, sndDt, fPos * 2, fPosR) * p->amp * ampL;
		smp[1] += sound_sample(2, sndDt, fPos * 2 + 1, fPosR) * p->amp * ampR;
	}
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
		float smp[2] = { 0., 0. };
		for (NSInteger j = 0; j < NGridW; j ++)
			add_sample(&envSndQ[j], smp, YES);
		smp[0] /= NGridW / 1.5;
		smp[1] /= NGridW / 1.5;
		for (NSInteger j = 0; j < sndQIdx.length; j ++)
			add_sample(&sndQue[(sndQIdx.location + j) % QUE_LENGTH], smp, NO);
		float maxS = fmaxf(fabsf(smp[0]), fabsf(smp[1]));
		sndAmp = (maxS * sndAmp > 1.)? 1. / maxS :
			sndAmp + (((maxS > 1.)? 1. / maxS : 1.) - sndAmp) / SAMPLE_RATE;
		data0[i] = smp[0] * sndAmp;
		data1[i] = smp[1] * sndAmp;
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
BOOL init_audio_out(SoundSrc *sndSrc, NSInteger nSrcs) {
	if (output) return YES;
	OSStatus err = noErr;
	for (NSInteger i = 0; i < nSrcs; i ++) sndSrc[i].buf = NULL;
	@try {
		AURenderCallbackStruct auCallback;
		AudioComponentDescription desc = {kAudioUnitType_Output,
			kAudioUnitSubType_DefaultOutput, kAudioUnitManufacturer_Apple, 0, 0};
		AudioComponent audioComponent = AudioComponentFindNext(NULL, &desc);
		double sampleRate = SAMPLE_RATE;
		if (!audioComponent) @throw @"AudioComponent Failed.";
		if ((err = AudioComponentInstanceNew(audioComponent, &output)))
			@throw @"AudioUnit Component Failed.";
		auCallback.inputProc = my_render_callback;
		if ((err = AudioUnitSetProperty(output, kAudioUnitProperty_SetRenderCallback,
			kAudioUnitScope_Input, 0, &auCallback, sizeof(AURenderCallbackStruct))))
			@throw @"AudioUnitSetProperty RenderCallback";
		if ((err = AudioUnitSetProperty(output, kAudioUnitProperty_SampleRate,
			kAudioUnitScope_Input, 0, &sampleRate, sizeof(double))))
			@throw @"AudioUnitSetProperty SampleRate";
		if ((err = AudioUnitInitialize(output))) @throw @"AudioUnitInitialize";
		for (NSInteger i = 0; i < nSrcs; i ++) {
			get_sound_data(&sndSrc[i]);
			if (sndSrc[i].buf == NULL) sndSrc[i].name = @"None";
			reqSndName[i] = sndSrc[i].name; 
		}
		sndData = sndSrc;
		soundBufLock = [NSLock new];
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
	if ([reqSndName[sndType] isEqualToString:sndData[sndType].name]) return;
	sndData[sndType].name = reqSndName[sndType];
	[soundBufLock lock];
	get_sound_data(&sndData[sndType]);
	[soundBufLock unlock];
}
void change_sound_data(SoundType sndType, NSString *name) {
	if ([reqSndName[sndType] isEqualToString:name]) return;
	reqSndName[sndType] = name;
	if (isRunning) check_sound_changed(sndType);
}
void start_audio_out(void) {
	if (!output) return;
	OSStatus err;
	if ((err = AudioOutputUnitStart(output)) != noErr)
		err_msg(@"AudioOutputUnitStart", err, NO);
	else {
		isRunning = YES;
		check_sound_changed(SndBump);
		check_sound_changed(SndGoal);
	}
}
void stop_audio_out(void) {
	if (!output) return;
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
	[soundBufLock lock];
	sndQue[NSMaxRange(sndQIdx) % QUE_LENGTH] = *info;
	if (sndQIdx.length < QUE_LENGTH) sndQIdx.length ++;
	else sndQIdx.location = (sndQIdx.location + 1) % QUE_LENGTH;
	[soundBufLock unlock];
}
void set_audio_env_params(SoundEnvParam *prm) {
	for (NSInteger i = 0; i < NGridW; i ++) {
		envSndQ[i].pitchShift = prm[i].pitchShift;
		envSndQ[i].amp = prm[i].amp;
	}
}
