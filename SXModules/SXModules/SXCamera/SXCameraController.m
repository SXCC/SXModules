//
//  SXCameraController.m
//  PLShortVideoKitDemo
//
//  Created by shenxuecen on 2019/11/21.
//  Copyright © 2019 Pili Engineering, Qiniu Inc. All rights reserved.
//

#import "SXCameraController.h"

@interface SXCameraController() <AVCaptureVideoDataOutputSampleBufferDelegate>
@property (strong, nonatomic) dispatch_queue_t dataQueue;
@property (strong, nonatomic) AVCaptureSession* session;
@property (strong, nonatomic) AVCaptureDevice* currentDevice;
@property (strong, nonatomic) AVCaptureDeviceInput* deviceInput;
@property (strong, nonatomic) AVCaptureVideoDataOutput* dataOutput;
@property (assign, nonatomic) AVCaptureVideoOrientation videoOrientation;
@property (assign, nonatomic) BOOL mirror;
@property (strong, nonatomic) NSMutableArray* dataDelegates;
@end

@implementation SXCameraController

- (id)init {
    self = [super init];
    if (self) {
        [self setupSession:AVCaptureSessionPreset1280x720];
        [self switchToDefaultDeviceOfPosition:AVCaptureDevicePositionBack];
        self.dataDelegates = [@[] mutableCopy];
    }
    return self;
}

- (void)setupSession:(AVCaptureSessionPreset)preset {
    self.session = [[AVCaptureSession alloc] init];
    self.session.sessionPreset = preset;
}

- (void)configCommonParams {
    if ([[self.dataOutput connections] count] > 0) {
        AVCaptureConnection* conn = [self.dataOutput.connections firstObject];
        conn.videoOrientation = self.videoOrientation;
        conn.videoMirrored = self.mirror;
    }
}

- (void)captureOutput:(AVCaptureOutput *)output didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection {
    @synchronized (self.dataDelegates) {
        for (id<AVCaptureAudioDataOutputSampleBufferDelegate> delegate in self.dataDelegates) {
            [delegate captureOutput:output didOutputSampleBuffer:sampleBuffer fromConnection:connection];
        }
    }
}

#pragma mark - interface
- (BOOL)setInputDevice:(AVCaptureDevice *)device {
    if (self.currentDevice == device) {
        return true;
    }
    NSError* error;
    AVCaptureDeviceInput* newDeviceInput = [AVCaptureDeviceInput deviceInputWithDevice:device error:&error];
    if (error) {
        NSLog(@"[SXCameraController setInputDevice:][Error]:%@", [error localizedDescription]);
        return false;
    }
    
    [self.session beginConfiguration];
    [self.session removeInput:self.deviceInput];
    if ([self.session canAddInput:newDeviceInput]) {
        [self.session addInput:newDeviceInput];
        self.deviceInput = newDeviceInput;
        self.currentDevice = device;
        [self configCommonParams];
        [self.session commitConfiguration];
        return true;
    } else {
        [self.session addInput:self.deviceInput];
        [self configCommonParams];
        [self.session commitConfiguration];
        NSLog(@"[SXCameraController setInputDevice:][Error]:Could not add new DeviceInput");
        return false;
    }
}

- (BOOL)switchToDefaultDeviceOfPosition:(AVCaptureDevicePosition)position {
    [self.session beginConfiguration];
    AVCaptureDevice* newDevice = [[AVCaptureDeviceDiscoverySession discoverySessionWithDeviceTypes:@[ AVCaptureDeviceTypeBuiltInWideAngleCamera] mediaType:AVMediaTypeVideo position:position].devices firstObject];
    AVCaptureDeviceInput* newDeviceInput = [AVCaptureDeviceInput deviceInputWithDevice:newDevice error:nil];
    [self.session removeInput:self.deviceInput];
    if ([self.session canAddInput:newDeviceInput]) {
        self.currentDevice = newDevice;
        self.deviceInput = newDeviceInput;
        [self.session addInput:self.deviceInput];
        [self configCommonParams];
        [self.session commitConfiguration];
        return true;
    } else {
        [self.session addInput:self.deviceInput];
        [self configCommonParams];
        [self.session commitConfiguration];
        return false;
    }
}

- (void)setDataOutputWithSettings:(NSDictionary *)videoSetting {
    [self.session beginConfiguration];
    if (self.dataOutput) {
        [self.session removeOutput:self.dataOutput];
        self.dataOutput = nil;
    }
    AVCaptureVideoDataOutput* videoDataOutput = [[AVCaptureVideoDataOutput alloc] init];
    self.dataQueue = dispatch_get_main_queue(); //dispatch_queue_create("com.sxc.sxccameradataqueue", DISPATCH_QUEUE_SERIAL);
    [videoDataOutput setSampleBufferDelegate:self queue:self.dataQueue];
    videoDataOutput.videoSettings = videoSetting;
    if ([self.session canAddOutput:videoDataOutput]) {
        [self.session addOutput:videoDataOutput];
        self.dataOutput = videoDataOutput;
    }
    [self configCommonParams];
    [self.session commitConfiguration];
}

- (void)addDataOutputDelegate:(id<AVCaptureVideoDataOutputSampleBufferDelegate>)delegate {
    @synchronized (self.dataDelegates) {
        if (![self.dataDelegates containsObject:delegate]) {
            [self.dataDelegates addObject:delegate];
        }
    }
}

- (void)removeDataOutputDelegate:(id<AVCaptureVideoDataOutputSampleBufferDelegate>)delegate {
    @synchronized (self.dataDelegates) {
        if ([self.dataDelegates containsObject:delegate]) {
            [self.dataDelegates removeObject:delegate];
        }
    }
}

- (void)setVideoMirror:(BOOL)mirror {
    if (self.mirror != mirror) {
        self.mirror = mirror;
        [self configCommonParams];
    }
}

- (void)setVideoDataOrientation:(AVCaptureVideoOrientation)orientation {
    if (self.videoOrientation != orientation) {
        self.videoOrientation = orientation;
        [self configCommonParams];
    }
}


- (void)setSessionPreset:(AVCaptureSessionPreset)preset {
    [self.session beginConfiguration];
    self.session.sessionPreset = preset;
    [self configCommonParams];
    [self.session commitConfiguration];
}

- (void)startCapture {
    [self.session startRunning];
}

- (void)stopCapture {
    [self.session stopRunning];
}

@end
