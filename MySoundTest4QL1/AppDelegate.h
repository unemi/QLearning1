//
//  AppDelegateS.h
//  MySoundTest4QL1
//
//  Created by Tatsuo Unemi on 2023/01/16.
//

#import <Cocoa/Cocoa.h>
#define NGridW 9

typedef enum {
	SndEnvNoise
} SoundType;

extern void err_msg(NSString *msg, OSStatus err, BOOL isFatal);

@interface AppDelegate : NSObject <NSApplicationDelegate>
@end

