//
//  MySound.h
//  QLearning1 (originally developed for LoversFlow)
//
//  Created by Tatsuo Unemi on 2017/09/19.
//  Copyright © 2017, Tatsuo Unemi. All rights reserved.
//

#import "CommonTypes.h"

typedef struct {
	SoundType type;
	float pitchShift, pan, amp;
	float fPos;
} SoundQue;

typedef struct {
	float pitchShift, amp;
} SoundEnvParam;

extern BOOL init_audio_out(void);
extern void change_sound_data(SoundType sndType, NSString *name);
extern void start_audio_out(void);
extern void stop_audio_out(void);
extern void set_audio_events(SoundQue *info);
extern void set_audio_env_params(SoundEnvParam *prm);
extern void enter_test_mode(NSString *path, float pm, float vol);
extern void exit_test_mode(void);
extern void set_test_mode_pm(float pm);
extern void set_test_mode_vol(float vol);

@interface MySound : NSObject
- (instancetype)initWithPath:(NSString *)path nCh:(int)nCh;
@end
