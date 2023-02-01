//
//  CommonTypes.h
//  LearningIsLife
//
//  Created by Tatsuo Unemi on 2023/01/17.
//

#ifndef CommonTypes_h
#define CommonTypes_h

#define NActs 4
#define NGridW 9
#define NGridH 6
#define NGrids (NGridW*NGridH)
#define NObstacles 7
#define NActiveGrids (NGridW*NGridH-NObstacles)
#define TileSize 100
#define PTCLMaxX (NGridW*TileSize)
#define PTCLMaxY (NGridH*TileSize)

enum {
	ShouldPostNotification = 1,
	ShouldRedrawScreen = 2,
	ShouldReviseVertices = 4
};

typedef enum { DispParticle, DispVector, DispQValues, DispNone } DisplayMode;
typedef enum { PTCLconstColor, PTCLangleColor, PTCLspeedColor } PTCLColorMode;
typedef enum { PTCLbyRectangles, PTCLbyTriangles, PTCLbyLines } PTCLShapeMode;
typedef enum { ObsFixed, ObsRandom, ObsExternal } ObstaclesMode;

@class MySound;
typedef enum {
	SndBump, SndGoal, SndGood, SndBad, SndAmbience,
	NVoices
} SoundType;

typedef struct { NSString *path; float mmin, mmax, vol; } SoundPrm;
typedef struct {
	NSString *key;
	SoundPrm v, fd;
	NSString *loaded;
	MySound *snd;
	int FDBit;
} SoundSrc;

#endif /* CommonTypes_h */
