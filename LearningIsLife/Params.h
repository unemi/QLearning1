//Agent.h:
extern int MemSize, MemTrials;
extern float T0, T1, CoolingRate, InitQValue, Gamma, Alpha, StepsPerSec;
extern simd_float4 *QTable;

//AppDelegate.h:
extern SoundSrc sndData[NVoices];
extern simd_int2 Move[4], FixedObsP[NObstaclesDF], FixedStartP, FixedGoalP;
extern int nGridW, nGridH, nObstacles, maxNObstacles;
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
