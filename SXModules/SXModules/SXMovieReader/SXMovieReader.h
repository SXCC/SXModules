//
//  SXMovieReader.h
//  SXModules
//
//  Created by shenxuecen on 2019/12/6.
//  Copyright © 2019 sxcc. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface SXMovieReader : NSObject

- (id)initWithFilePath:(NSString *)movieFilePath OutputPixelFormat:(OSType)pixelFormat;
- (BOOL)loadMovieAndStartReading;
- (NSInteger)getCurrentFrameIndex;
- (CMSampleBufferRef)getNextSampleBuffer:(AVAssetReaderStatus *)status;
@end

NS_ASSUME_NONNULL_END
