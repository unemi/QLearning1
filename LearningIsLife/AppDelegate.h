//
//  AppDelegate.h
//  LearningIsLife
//
//  Created by Tatsuo Unemi on 2022/12/24.
//

@import Cocoa;
@import simd;
#import "CommonTypes.h"

typedef struct { NSString *key; int *v, fd, flag; } IntVarInfo;
typedef struct { NSString *key; float *v, fd; int flag; } FloatVarInfo;
typedef struct { NSString *key; NSColor * __strong *v, *fd; int flag; } ColVarInfo;
typedef struct { NSString *key; NSUInteger v, fd; } UIntegerVarInfo;
typedef struct { NSString *key; BOOL v, fd; int flag; } BoolVarInfo;

extern IntVarInfo IntVars[];
extern FloatVarInfo FloatVars[];
extern ColVarInfo ColVars[];
extern UIntegerVarInfo UIntegerVars[];
extern BoolVarInfo BoolVars[];
extern SoundSrc sndData[NVoices];
#define MAX_STEPS_TAG 0
#define MAX_GOALCNT_TAG 1
#define MAX_STEPS (UIntegerVars[MAX_STEPS_TAG].v)
#define MAX_GOALCNT (UIntegerVars[MAX_GOALCNT_TAG].v)
#define SOUNDS_ON (BoolVars[0].v)
#define START_WIDTH_FULL_SCR (BoolVars[1].v)
#define RECORD_IMAGES (BoolVars[2].v)
#define SHOW_FPS (BoolVars[3].v)

extern simd_int2 Move[4], ObsP[NObstacles],
	FieldP[NGrids], StartP, GoalP;
extern int nActiveGrids;
extern int Obstacles[NGridH][NGridW];
extern NSString *keyCntlPnl;
extern NSString *keyOldValue, *keyShouldRedraw, *keyShouldReviseVertices, *keySoundTestExited;
extern NSString *keyColorMode, *keyShapeMode, *keyObsMode;
extern NSString *scrForFullScrFD, *keyScrForFullScr;
extern PTCLColorMode ptclColorModeFD;
extern PTCLShapeMode ptclShapeModeFD;
extern ObstaclesMode obsModeFD;
#define EXT_FOR_ALL_PROC(name,type) extern void name(void (^)(type *));
EXT_FOR_ALL_PROC(for_all_int_vars, IntVarInfo);
EXT_FOR_ALL_PROC(for_all_float_vars, FloatVarInfo);
EXT_FOR_ALL_PROC(for_all_uint_vars, UIntegerVarInfo);
EXT_FOR_ALL_PROC(for_all_bool_vars, BoolVarInfo)
EXT_FOR_ALL_PROC(for_all_color_vars, ColVarInfo)

extern NSUInteger col_to_ulong(NSColor *col);
extern NSColor *ulong_to_col(NSUInteger rgba);
extern NSUInteger hex_string_to_uint(NSString *str);

@interface AppDelegate : NSObject <NSApplicationDelegate>
@end
