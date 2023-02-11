//
//  CommonTypes.h
//  LearningIsLife
//
//  Created by Tatsuo Unemi on 2023/01/17.
//

#ifndef CommonTypes_h
#define CommonTypes_h

#define NActs 4
#define NGridWDF 9
#define NGridHDF 6
#define nGrids (nGridW*nGridH)
#define NObstaclesDF 7
#define nActiveGrids (nGrids-nObstacles)
#define TileSizeWDF 100
#define TileSizeHDF 100
#define PTCLMaxX (nGridW*tileSize.x)
#define PTCLMaxY (nGridH*tileSize.y)
#define DISP_INTERVAL (1./60.)

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

#endif /* CommonTypes_h */
