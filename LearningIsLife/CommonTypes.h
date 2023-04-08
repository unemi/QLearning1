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

typedef enum {
	KeyCodeA = 0, KeyCodeS, KeyCodeD, KeyCodeF, KeyCodeH,
		KeyCodeG, KeyCodeZ, KeyCodeX, KeyCodeC, KeyCodeV,
	KeyCodeQ = 12, KeyCodeW, KeyCodeE, KeyCodeR, KeyCodeY, KeyCodeT,
	KeyCode1 = 18, KeyCode2, KeyCode3, KeyCode4, KeyCode6, KeyCode5,
	KeyCodeRET = 36,
	KeyCodeTAB = 48,
	KeyCodeDEL = 51,
	KeyCodeESC = 53,
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
