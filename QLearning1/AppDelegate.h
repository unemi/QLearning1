//
//  AppDelegate.h
//  QLearning1
//
//  Created by Tatsuo Unemi on 2022/12/24.
//

@import Cocoa;
@import simd;
#define NActs 4
#define NGridW 9
#define NGridH 6
#define NObstacles 7
#define TileSize 100
#define PTCLMaxX (NGridW*TileSize)
#define PTCLMaxY (NGridH*TileSize)

typedef struct { NSString *key; int *v, fd, flag; } IntVarInfo;
typedef struct { NSString *key; float *v, fd; int flag; } FloatVarInfo;
typedef struct { NSString *key; NSColor * __strong *v, *fd; int flag; } ColVarInfo;
typedef struct { NSString *key; NSUInteger v, fd; } UIntegerVarInfo;
typedef struct { NSString *key; BOOL v, fd; int flag; } BoolVarInfo;
extern UIntegerVarInfo UIntegerVars[];
extern BoolVarInfo BoolVars[];
#define MAX_STEPS (UIntegerVars[0].v)
#define MAX_GOALCNT (UIntegerVars[1].v)
#define START_WIDTH_FULL_SCR (BoolVars[0].v)
#define RECORD_IMAGES (BoolVars[1].v)

extern int Move[4][2], ObsP[NObstacles][2],
	FieldP[NGridW * NGridH - NObstacles][2], Obstacles[NGridH][NGridW],
	StartP[2], GoalP[2];
extern NSString *keyOldValue, *keyShouldRedraw;
extern NSString *keyColorMode, *keyDrawMethod;
extern unsigned long current_time_us(void);
extern void in_main_thread(void (^block)(void));

@interface ControlPanel : NSWindowController
	<NSWindowDelegate, NSMenuItemValidation>
@property (readonly) NSUndoManager *undoManager;
@end

@interface AppDelegate : NSObject <NSApplicationDelegate>
@end
