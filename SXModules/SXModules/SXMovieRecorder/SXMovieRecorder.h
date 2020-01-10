//
//  SXMovieRecorder.h
//  SXModules
//
//  Created by 雪岑申 on 2019/11/30.
//  Copyright © 2019 sxcc. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>

@interface SXMovieRecorder : NSObject
- (id)initWithPath:(NSString *)path FileType:(AVFileType)fileType VideoSize:(CGSize)videoSize FrameRate:(NSInteger)frameRate BitRate:(NSInteger)bitRate;
- (NSString *)getFilePath;
- (BOOL)canAppendPixelBuffer;
- (void)startWriting;
- (CVPixelBufferRef)generatePixelBuffer;
- (BOOL)appendPixelBuffer:(CVPixelBufferRef)pixelBuffer;
- (void)finishWriting:(void(^)(void))handler;
@end

