//
//  AppDelegate.h
//  LearningIsLife
//
//  Created by Tatsuo Unemi on 2022/12/24.
//

@import Cocoa;
@import simd;
#import "CommonTypes.h"

typedef struct { NSString *key; int flag, *v, fd, ud; } IntVarInfo;
typedef struct { NSString *key; int flag; float *v, fd, ud; } FloatVarInfo;
typedef struct { NSString *key; int flag; NSColor * __strong *v, *fd, *ud; } ColVarInfo;
typedef struct { NSString *key; int flag; NSUInteger v, fd, ud; } UIntegerVarInfo;
typedef struct { NSString *key; int flag; BOOL v, fd, ud; } BoolVarInfo;

extern IntVarInfo IntVars[];
extern FloatVarInfo FloatVars[];
extern ColVarInfo ColVars[];
extern UIntegerVarInfo UIntegerVars[];
extern BoolVarInfo BoolVars[];
extern SoundSrc sndData[NVoices];
#define GRID_W_TAG 0
#define GRID_H_TAG 1
#define MAX_STEPS_TAG 0
#define MAX_GOALCNT_TAG 1
#define MAX_STEPS (UIntegerVars[MAX_STEPS_TAG].v)
#define MAX_GOALCNT (UIntegerVars[MAX_GOALCNT_TAG].v)
#define SOUNDS_ON (BoolVars[0].v)
#define START_WIDTH_FULL_SCR (BoolVars[1].v)
#define RECORD_IMAGES (BoolVars[2].v)
#define SHOW_FPS (BoolVars[3].v)
#define SAVE_WHEN_TERMINATE (BoolVars[4].v)

extern simd_int2 Move[4], FixedObsP[NObstaclesDF], FixedStartP, FixedGoalP;
extern int nGridW, nGridH, nObstacles, maxNObstacles;
extern int newGridW, newGridH, newTileH, newMaxNObstacles, maxNObstacles;
extern int newStartX, newStartY, newGoalX, newGoalY;
extern simd_int2 *ObsP, *FieldP, StartP, GoalP, tileSize;
extern float *ObsHeight;
extern NSString *keyCntlPnl;
extern NSString *keyOldValue, *keyShouldRedraw, *keyShouldReviseVertices, *keySoundTestExited;
extern NSString *keyColorMode, *keyShapeMode, *keyObsMode;
extern NSString *scrForFullScrFD, *scrForFullScrUD, *keyScrForFullScr;
extern PTCLColorMode ptclColorModeFD, ptclColorModeUD;
extern PTCLShapeMode ptclShapeModeFD, ptclShapeModeUD;
extern ObstaclesMode obsModeFD, obsModeUD;
#define EXT_FOR_ALL_PROC(name,type) extern void name(void (^)(type *));
EXT_FOR_ALL_PROC(for_all_int_vars, IntVarInfo);
EXT_FOR_ALL_PROC(for_all_float_vars, FloatVarInfo);
EXT_FOR_ALL_PROC(for_all_uint_vars, UIntegerVarInfo);
EXT_FOR_ALL_PROC(for_all_bool_vars, BoolVarInfo)
EXT_FOR_ALL_PROC(for_all_color_vars, ColVarInfo)

extern NSUInteger col_to_ulong(NSColor *col);
extern NSColor *ulong_to_col(NSUInteger rgba);
extern NSUInteger hex_string_to_ulong(NSString *str);
extern void save_as_user_defaults(void);

@interface AppDelegate : NSObject <NSApplicationDelegate>
@end
