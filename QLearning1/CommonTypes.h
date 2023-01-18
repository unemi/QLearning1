//
//  CommonTypes.h
//  QLearning1
//
//  Created by Tatsuo Unemi on 2023/01/17.
//

#ifndef CommonTypes_h
#define CommonTypes_h

#define NActs 4
#define NGridW 9
#define NGridH 6
#define NObstacles 7
#define NActiveGrids (NGridW*NGridH-NObstacles)
#define TileSize 100
#define PTCLMaxX (NGridW*TileSize)
#define PTCLMaxY (NGridH*TileSize)

typedef enum {
	SndBump, SndGoal, SndGood, SndBad, SndEnvNoise,
	NVoices
} SoundType;

typedef struct { NSString *path; float mmin, mmax, vol; } SoundPrm;
typedef struct {
	NSString *key;
	UInt32 nCh;
	SoundPrm v, fd;
	NSString *loaded;
	UInt32 nFrames;
	float *buf;
	int FDBit;
} SoundSrc;

#endif /* CommonTypes_h */
