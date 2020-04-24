//
//  SXMovieReader.m
//  SXModules
//
//  Created by shenxuecen on 2019/12/6.
//  Copyright © 2019 sxcc. All rights reserved.
//

#import "SXMovieReader.h"

@interface SXMovieReader ()
@property (copy, nonatomic) NSString* filePath;
@property (strong, nonatomic) AVAsset* movieAsset;
@property (strong, nonatomic) AVAssetTrack* movieAssetVideoTrack;
@property (strong, nonatomic) AVAssetReader *assetReader;
@property (strong, nonatomic) AVAssetReaderTrackOutput* assetReaderOutput;
@property (assign, nonatomic) NSInteger currentFrameIndex;
@property (assign, nonatomic) OSType pixelForamt;
@end


@implementation SXMovieReader

- (id)initWithFilePath:(NSString *)movieFilePath OutputPixelFormat:(OSType)pixelFormat {
    self = [super init];
    if (self) {
        self.filePath = movieFilePath;
        self.pixelForamt = pixelFormat;
    }
    return self;
}

- (BOOL)loadMovieAndStartReading {
    self.movieAsset = [AVAsset assetWithURL:[NSURL fileURLWithPath:self.filePath]];
    if (self.movieAsset == nil) {
        return false;
    }
    NSError* error;
    self.assetReader = [AVAssetReader assetReaderWithAsset:self.movieAsset error:&error];
    if (error) {
        NSLog(@"[SXMovieReder Error]: %@", [error localizedDescription]);
        return false;
    }
    self.movieAssetVideoTrack = [[self.movieAsset tracksWithMediaType:AVMediaTypeVideo] firstObject];
    if (self.movieAssetVideoTrack == nil) {
        return false;
    }
    self.assetReaderOutput = [[AVAssetReaderTrackOutput alloc] initWithTrack:self.movieAssetVideoTrack outputSettings:@{(NSString *)kCVPixelBufferPixelFormatTypeKey: @(self.pixelForamt)}];
    if (self.assetReaderOutput == nil) {
        return false;
    }
    [self.assetReader addOutput:self.assetReaderOutput];
    self.currentFrameIndex = -1;
    return [self.assetReader startReading];
}

- (NSInteger)getCurrentFrameIndex {
    return self.currentFrameIndex;
}

- (CMSampleBufferRef)getNextSampleBuffer:(AVAssetReaderStatus *)status {
    CMSampleBufferRef buffer = [self.assetReaderOutput copyNextSampleBuffer];
    if (buffer) {
        self.currentFrameIndex++;
        *status = AVAssetReaderStatusReading;
    } else {
        NSLog(@"[SXMovieReader] Read MOV Failed or Completed");
        *status = self.assetReader.status;
        return nil;
    }
    return buffer;
}


@end
