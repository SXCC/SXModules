//
//  SXMovieRecorder.m
//  SXModules
//
//  Created by 雪岑申 on 2019/11/30.
//  Copyright © 2019 sxcc. All rights reserved.
//

#import "SXMovieRecorder.h"

@interface SXMovieRecorder ()
@property (copy, nonatomic) NSString* filePath;
@property (assign, nonatomic) AVFileType fileType;
@property (assign, nonatomic) CGSize videoSize;
@property (assign, nonatomic) NSInteger frameRate;
@property (assign, nonatomic) NSInteger bitRate;

@property (strong, nonatomic) AVAssetWriter* assetWriter;
@property (strong, nonatomic) AVAssetWriterInput* videoInput;
@property (strong, nonatomic) AVAssetWriterInputPixelBufferAdaptor* pixelBufferAdaptor;
@property (assign, nonatomic) CMTime pTime;
@end

@implementation SXMovieRecorder

- (id)initWithPath:(NSString *)path FileType:(AVFileType)fileType VideoSize:(CGSize)videoSize FrameRate:(NSInteger)frameRate BitRate:(NSInteger)bitRate {
    self = [super init];
    if (self) {
        _filePath = path;
        _fileType = fileType;
        _videoSize = videoSize;
        _frameRate = frameRate;
        _bitRate = bitRate;
        [self setupAssetWriter];
    }
    return self;
}

- (void)setupAssetWriter {
    NSError* error;
    self.assetWriter = [[AVAssetWriter alloc] initWithURL:[NSURL fileURLWithPath:self.filePath] fileType:self.fileType error:&error];
    if (error) {
        NSLog(@"[SXMovieRecorder-setupAssetWriter][Error]: %@", [error localizedDescription]);
        abort();
    }
    
    NSDictionary* videoSettings = @{
        AVVideoCompressionPropertiesKey: @{AVVideoAverageBitRateKey: @(self.bitRate)}, 
        AVVideoCodecKey: AVVideoCodecTypeH264,
        AVVideoWidthKey: @(self.videoSize.width),
        AVVideoHeightKey: @(self.videoSize.height)
    };
    self.videoInput = [[AVAssetWriterInput alloc] initWithMediaType:AVMediaTypeVideo outputSettings:videoSettings];
    [self.assetWriter addInput:self.videoInput];
    
    NSDictionary* pixelBufferAdaptorSettings = @{
        (NSString *)kCVPixelBufferPixelFormatTypeKey: @(kCVPixelFormatType_32BGRA),
        (NSString *)kCVPixelBufferWidthKey: @(self.videoSize.width),
        (NSString *)kCVPixelBufferHeightKey: @(self.videoSize.height)
    };
    self.pixelBufferAdaptor = [[AVAssetWriterInputPixelBufferAdaptor alloc] initWithAssetWriterInput:self.videoInput sourcePixelBufferAttributes:pixelBufferAdaptorSettings];
}

- (void)startWriting {
    [self.assetWriter startWriting];
    self.pTime = CMTimeMake(0, 120); // 120 as a timescale
    [self.assetWriter startSessionAtSourceTime:self.pTime];
}

- (BOOL)canAppendPixelBuffer {
    return self.videoInput.isReadyForMoreMediaData;
}

- (BOOL)appendPixelBuffer:(CVPixelBufferRef)pixelBuffer {
    if (!self.videoInput.isReadyForMoreMediaData) {
        [NSThread sleepForTimeInterval:0.1]; // wait video writer for 0.1s
    }
    
    if (!self.videoInput.isReadyForMoreMediaData) {
        NSLog(@"Drop One Frame");
        self.pTime = CMTimeAdd(self.pTime, CMTimeMake(120 / self.frameRate, 120));
        return false;
    }
    @try {
        [self.pixelBufferAdaptor appendPixelBuffer:pixelBuffer withPresentationTime:self.pTime];
        self.pTime = CMTimeAdd(self.pTime, CMTimeMake(120 / self.frameRate, 120));
        return true;
    }
    @catch (NSException *exception) {
        NSLog(@"[SXMovieRecorder][Error]: got exception %@", [exception description]);
        return false;
    }
}

- (void)finishWriting:(void(^)(void))handler {
    [self.assetWriter finishWritingWithCompletionHandler:^{
        if (handler) {
            handler();
        }
    }];
}

@end
