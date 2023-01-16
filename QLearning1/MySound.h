//
//  MySound.h
//  QLearning1 (originally developed for LoversFlow)
//
//  Created by Tatsuo Unemi on 2017/09/19.
//  Copyright © 2017, Tatsuo Unemi. All rights reserved.
//

#import "AppDelegate.h"

typedef struct {
	NSString *name, *type;
	UInt32 nCh, nFrames;
	float *buf;
} SoundSrc;

typedef struct {
	SoundType type;
	float pitchShift, pan, amp;
	float fPos;
} SoundQue;

typedef struct {
	float pitchShift, amp;
} SoundEnvParam;

extern BOOL init_audio_out(SoundSrc *sndSrc, NSInteger nSrcs);
extern void change_sound_data(SoundType sndType, NSString *name);
extern void start_audio_out(void);
extern void stop_audio_out(void);
extern void set_audio_events(SoundQue *info);
extern void set_audio_env_params(SoundEnvParam *prm);