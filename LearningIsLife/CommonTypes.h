//
//  CommonTypes.h
//  LearningIsLife
//
//  Created by Tatsuo Unemi on 2023/01/17.
//

@import simd;
#ifndef CommonTypes_h
#define CommonTypes_h

#define NActs 4
#define NGridWDF 9
#define NGridHDF 6
#define nGrids (nGridW*nGridH)
#define NObstaclesDF 7
#define nActiveGrids (nGrids-nObstacles)
#define nGridsInUse ((obstaclesMode < ObsPointer)? nActiveGrids : nGrids)
#define TileSizeWDF 100
#define TileSizeHDF 100
#define PTCLMaxX (nGridW*tileSize.x)
#define PTCLMaxY (nGridH*tileSize.y)
#define DISP_INTERVAL (1./60.)

// Key code for US keyboard
typedef enum {
	KeyCodeA = 0, KeyCodeS, KeyCodeD, KeyCodeF, KeyCodeH,
		KeyCodeG, KeyCodeZ, KeyCodeX, KeyCodeC, KeyCodeV,
	KeyCodeB = 11, KeyCodeQ, KeyCodeW, KeyCodeE, KeyCodeR, KeyCodeY, KeyCodeT,
	KeyCode1 = 18, KeyCode2, KeyCode3, KeyCode4, KeyCode6, KeyCode5,
	KeyCodeEQU = 24,	// equal / plus sign
	KeyCode9, KeyCode7,
	KeyCodeMNS = 27,	// minus sign / under score
	KeyCode8, KeyCode0,
	KeyCodeCSB = 30,	// closing square bracket / brace
	KeyCodeO, KeyCodeU,
	KeyCodeOSB = 33,	// opening square bracket / brace
	KeyCodeI, KeyCodeP,
	KeyCodeRET = 36,
	KeyCodeL, KeyCodeJ,
	KeyCodeSQT = 39,	// single quote / double quote
	KeyCodeK,
	KeyCodeSCL = 41,	// semicolon / colon
	KeyCodeBSL = 42,	// back slash / vertical bar
	KeyCodeCMA = 43,	// comma / less than
	KeyCodeSLS = 44,	// slash / question mark
	KeyCodeN, KeyCodeM,
	KeyCodePRD = 47,	// period / greater than
	KeyCodeTAB = 48,
	KeyCodeBQT = 50,	// back quote / tilda
	KeyCodeBSP = 51,	// back space (delete)
	KeyCodeESC = 53,
	KeyCodeCLR = 71,	// clear
	KeyCodeENT = 76,	// enter
	KetCodeF5 = 96, KeyCodeF6, KeyCodeF7, KeyCodeF3, KeyCodeF8, KeyCodeF9,
	KeyCodeF11 = 103,
	KeyCodePSC = 105,	// print screen
	KeyCodeF10 = 109, KeyCodeF12 = 111,
	KeyCodeINS = 114,	// insert
	KeyCodeDEL = 117,	// delete
	KeyCodeF2 = 120, KeyCodeF1 = 122,
	KeyCodeLeft = 123, KeyCodeRight, KeyCodeDown, KeyCodeUp
} KyeCode;

enum {
	ShouldPostNotification = 1,
	ShouldRedrawScreen = 2,
	ShouldReviseVertices = 4
};

typedef enum { DispParticle, DispVector, DispQValues, DispNone } DisplayMode;
typedef enum { PTCLconstColor, PTCLangleColor, PTCLspeedColor } PTCLColorMode;
typedef enum { PTCLbyRectangles, PTCLbyTriangles, PTCLbyLines } PTCLShapeMode;
typedef enum { ObsFixed, ObsRandom, ObsPointer, ObsExternal } ObstaclesMode;

@class MySound;
typedef enum {
	SndBump, SndGoal, SndGood, SndBad, SndAmbience,
	NVoices
} SoundType;

typedef struct { NSString *path; float mmin, mmax, vol; } SoundPrm;
typedef struct {
	NSString *key;
	SoundPrm v, fd, ud;
	NSString *loaded;
	MySound *snd;
	int FDBit;
} SoundSrc;

extern unsigned long current_time_us(void);

typedef struct {
	int nGridW, nGridH;
	simd_int2 StartP, GoalP, TileSize;
	ObstaclesMode obsMode;
} WorldParams;
typedef struct {
	int MemSize, MemTrials;	// Agent
	float T0, T1, CoolingRate, InitQValue, Gamma, Alpha, StepsPerSec;	// Agent
	simd_int2 FixedStartP, FixedGoalP;	// World
	SoundSrc sndData[NVoices];	// Sound
} Parameters;

/**
//Agent.h:
extern simd_float4 *QTable;

//AppDelegate.h:
extern simd_int2 Move[4], FixedObsP[NObstaclesDF]
extern int nObstacles, maxNObstacles;
extern int newGridW, newGridH, newTileH, newMaxNObstacles, maxNObstacles;
extern int newStartX, newStartY, newGoalX, newGoalY;
extern simd_int2 *ObsP, *FieldP, StartP, GoalP, tileSize;
extern float *ObsHeight;
extern NSString *scrForFullScrFD, *scrForFullScrUD;
extern PTCLColorMode ptclColorModeFD, ptclColorModeUD;
extern PTCLShapeMode ptclShapeModeFD, ptclShapeModeUD;
extern ObstaclesMode obsModeFD, obsModeUD;

//Display.h
extern int NParticles, LifeSpan;
extern float Mass, Friction, StrokeLength, StrokeWidth, MaxSpeed;
extern NSColor * _Nonnull colBackground, * _Nonnull colObstacles,
extern PTCLColorMode ptclColorMode;
extern PTCLShapeMode ptclShapeMode;

//MainWindow.h:
extern NSString *scrForFullScr;
extern ObstaclesMode obstaclesMode, newObsMode;
extern float ManObsLifeSpan;
*/
#endif /* CommonTypes_h */
