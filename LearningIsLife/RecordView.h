//
//  RecordView.h
//  LearningIsLife
//
//  Created by Tatsuo Unemi on 2023/01/05.
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@class Display;
@interface RecordView : NSView
- (void)addImage:(Display *)display infoText:(NSString *)infoText;
- (void)loadImages;
- (void)saveImages;
- (void)clearImages;
@end

NS_ASSUME_NONNULL_END
