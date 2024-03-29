//
//  VecTypes.h
//  LearningIsLife
//
//  Created by Tatsuo Unemi on 2022/12/28.
//

#ifndef VecTypes_h
#define VecTypes_h

// Input data indices for vertex shaders
enum {
	IndexVertices,
	IndexGeomFactor,
	IndexAdjustMatrix,
	IndexColors,
	IndexNVforP
};
// Input data indices for fragment shaders
enum {
	IndexTexture,
	IndexFrgColor
};
// Input data indices for fragment shaders
enum {
	IndexTPN,
	IndexTPInfo,
	IndexTPColor,
	IndexTPGeoFactor,
	IndexInvAdjMx
};

#endif /* VecTypes_h */
