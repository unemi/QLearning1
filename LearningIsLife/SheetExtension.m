//
//  SheetExtension.m
//  Learning is Life
//
//  Created by Tatsuo Unemi on 2023/06/30.
//

#import "SheetExtension.h"

@implementation NSWindowController (SheetExtension)
- (IBAction)sheetOk:(id)sender {
	[self.window.sheetParent endSheet:self.window returnCode:NSModalResponseOK];
}
- (IBAction)sheetCancel:(id)sender {
	[self.window.sheetParent endSheet:self.window returnCode:NSModalResponseCancel];
}
@end
