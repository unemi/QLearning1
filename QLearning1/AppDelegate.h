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
extern int Move[4][2], ObsP[NObstacles][2],
	FieldP[NGridW * NGridH - NObstacles][2], Obstacles[NGridH][NGridW],
	StartP[2], GoalP[2];
extern NSString *keyOldValue, *keyShouldRedraw;
extern NSString *keyColorMode, *keyDrawMethod;

@interface ControlPanel : NSWindowController <NSWindowDelegate>
@property (readonly) NSUndoManager *undoManager;
@end

@interface AppDelegate : NSObject <NSApplicationDelegate>
@end

@interface MyViewController : NSViewController
	<NSWindowDelegate, NSMenuItemValidation>
@end 
