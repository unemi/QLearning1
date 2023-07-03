//
//  SheetExtension.h
//  Learning is Life
//
//  Created by Tatsuo Unemi on 2023/06/30.
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@interface NSWindowController (SheetExtension) 
- (IBAction)sheetOk:(id)sender;
- (IBAction)sheetCancel:(id)sender;
@end

NS_ASSUME_NONNULL_END
