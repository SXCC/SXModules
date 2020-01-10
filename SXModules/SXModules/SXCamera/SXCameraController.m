//
//  SXCameraController.m
//  PLShortVideoKitDemo
//
//  Created by shenxuecen on 2019/11/21.
//  Copyright © 2019 Pili Engineering, Qiniu Inc. All rights reserved.
//

#import "SXCameraController.h"

API_AVAILABLE(ios(11.0))
@interface SXCameraController() <AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureDepthDataOutputDelegate>
@property (strong, nonatomic) dispatch_queue_t dataQueue;
@property (strong, nonatomic) AVCaptureSession* session;
@property (strong, nonatomic) AVCaptureDevice* currentDevice;
@property (strong, nonatomic) AVCaptureDeviceInput* deviceInput;
@property (strong, nonatomic) AVCaptureVideoDataOutput* videoDataOutput;
@property (strong, nonatomic) AVCaptureDepthDataOutput* depthDataOutput;
@property (assign, nonatomic) AVCaptureVideoOrientation videoOrientation;
@property (assign, nonatomic) BOOL mirror;
@property (strong, nonatomic) NSMutableArray<id<SXCameraControllerDataDelegate>>* dataDelegates;
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
    if ([[self.videoDataOutput connections] count] > 0) {
        AVCaptureConnection* conn = [self.videoDataOutput.connections firstObject];
        conn.videoOrientation = self.videoOrientation;
        conn.videoMirrored = self.mirror;
    }
    if ([[self.depthDataOutput connections] count] > 0) {
        AVCaptureConnection* conn = [self.depthDataOutput.connections firstObject];
        conn.videoOrientation = self.videoOrientation;
        conn.videoMirrored = self.mirror;
    }
}

- (void)captureOutput:(AVCaptureOutput *)output didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection {
    @synchronized (self.dataDelegates) {
        for (id<SXCameraControllerDataDelegate> delegate in self.dataDelegates) {
            [delegate captureOutput:output didOutputSampleBuffer:sampleBuffer fromConnection:connection];
        }
    }
}

- (void)depthDataOutput:(AVCaptureDepthDataOutput *)output didOutputDepthData:(AVDepthData *)depthData timestamp:(CMTime)timestamp connection:(AVCaptureConnection *)connection  API_AVAILABLE(ios(11.0)){
    @synchronized (self.dataDelegates) {
        for (id<SXCameraControllerDataDelegate> delegate in self.dataDelegates) {
            [delegate depthDataOutput:output didOutputDepthData:depthData timestamp:timestamp connection:connection];
        }
    }
}

- (dispatch_queue_t)dataQueue {
    if (_dataQueue == nil) {
        _dataQueue = dispatch_get_main_queue();
    }
    return _dataQueue;
}

#pragma mark - interface
#pragma mark - input device
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
    AVCaptureDevice* newDevice = [[AVCaptureDeviceDiscoverySession discoverySessionWithDeviceTypes:@[AVCaptureDeviceTypeBuiltInWideAngleCamera] mediaType:AVMediaTypeVideo position:position].devices firstObject];
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

#pragma mark - Device format & depth format
- (AVCaptureDeviceFormat *)activeDeviceFormat {
    return self.currentDevice.activeFormat;
}

- (AVCaptureDeviceFormat *)activeDepthDataFormat {
    if (@available(iOS 11.0, *)) {
        return self.currentDevice.activeDepthDataFormat;
    } else {
        return nil;
    }
}

- (NSArray<AVCaptureDeviceFormat *> *)supportedDeviceFormatsForCurrentDevice {
    return self.currentDevice.formats;
}

- (void)setActiveDeviceFormat:(AVCaptureDeviceFormat *)deviceFormat {
    if ([self.currentDevice lockForConfiguration:nil]) {
        self.currentDevice.activeFormat = deviceFormat;
        [self.currentDevice unlockForConfiguration];
    }
}

- (void)setActiveDepthDataFormat:(AVCaptureDeviceFormat *)depthDataOutput {
    if (@available(iOS 11.0, *)) {
        if ([self.currentDevice lockForConfiguration:nil]) {
            self.currentDevice.activeDepthDataFormat = depthDataOutput;
            [self.currentDevice unlockForConfiguration];
        }
    } else {
        // nop
    }
}

#pragma mark - camera output
- (void)addDataOutputDelegate:(id<SXCameraControllerDataDelegate>)delegate {
    @synchronized (self.dataDelegates) {
        if (![self.dataDelegates containsObject:delegate]) {
            [self.dataDelegates addObject:delegate];
        }
    }
}

- (void)removeDataOutputDelegate:(id<SXCameraControllerDataDelegate>)delegate {
    @synchronized (self.dataDelegates) {
        if ([self.dataDelegates containsObject:delegate]) {
            [self.dataDelegates removeObject:delegate];
        }
    }
}

#pragma mark - video data output
- (void)setDataOutputWithSettings:(NSDictionary *)videoSetting {
    [self.session beginConfiguration];
    if (self.videoDataOutput) {
        [self.session removeOutput:self.videoDataOutput];
        self.videoDataOutput = nil;
    }
    AVCaptureVideoDataOutput* videoDataOutput = [[AVCaptureVideoDataOutput alloc] init];
    [videoDataOutput setSampleBufferDelegate:self queue:self.dataQueue];
    videoDataOutput.videoSettings = videoSetting;
    if ([self.session canAddOutput:videoDataOutput]) {
        [self.session addOutput:videoDataOutput];
        self.videoDataOutput = videoDataOutput;
    }
    [self configCommonParams];
    [self.session commitConfiguration];
}

#pragma mark - depth data output
- (void)setDepthDataOutput {
    if (@available(iOS 11.0, *)) {
        [self.session beginConfiguration];
        if (self.depthDataOutput) {
            [self.session removeOutput:self.depthDataOutput];
            self.depthDataOutput = nil;
        }
        
        AVCaptureDepthDataOutput* depthDataOutput = [[AVCaptureDepthDataOutput alloc] init];
        [depthDataOutput setDelegate:self callbackQueue:self.dataQueue];
        if ([self.session canAddOutput:depthDataOutput]) {
            [self.session addOutput:depthDataOutput];
            self.depthDataOutput = depthDataOutput;
        }
        [self configCommonParams];
        [self.session commitConfiguration];
    } else {
        // nop
    }
}


#pragma mark - white balance
- (BOOL)supportsLockWhiteBalanceToCustomValue {
    return [self.currentDevice isLockingWhiteBalanceWithCustomDeviceGainsSupported];
}

- (void)setWhiteBalanceModeLockedWithDeviceWhiteBalanceGains:(AVCaptureWhiteBalanceGains)gains completionHandler:(void (^)(CMTime syncTime))handler {
    if([self.currentDevice lockForConfiguration:nil]) {
        [self.currentDevice setWhiteBalanceModeLockedWithDeviceWhiteBalanceGains:gains completionHandler:handler];
        [self.currentDevice unlockForConfiguration];
    }
}

- (AVCaptureWhiteBalanceGains)currentDeviceWhiteBalanceGains {
    return [self.currentDevice deviceWhiteBalanceGains];
}

- (float)maxiumWhiteBalanceGains {
    return [self.currentDevice maxWhiteBalanceGain];
}


- (AVCaptureWhiteBalanceTemperatureAndTintValues)temperatureAndTintValuesForDeviceWhiteBalanceGains:(AVCaptureWhiteBalanceGains)gains {
    return [self.currentDevice temperatureAndTintValuesForDeviceWhiteBalanceGains:gains];
}

- (AVCaptureWhiteBalanceGains)deviceWhiteBalanceGainsForTemperatureAndTintValues:(AVCaptureWhiteBalanceTemperatureAndTintValues)temperateTint {
    return [self.currentDevice deviceWhiteBalanceGainsForTemperatureAndTintValues:temperateTint];
}

- (void)setWhiteBalanceModel:(AVCaptureWhiteBalanceMode)model {
    if ([self.currentDevice lockForConfiguration:nil]) {
        [self.currentDevice setWhiteBalanceMode:model];
        [self.currentDevice unlockForConfiguration];
    }
}

#pragma mark - zoom factor
- (CGFloat)currentZoomFactor {
    return self.currentDevice.videoZoomFactor;
}

- (CGFloat)maxiumZoomFactor {
    if (@available(iOS 11.0, *)) {
        return [self.currentDevice maxAvailableVideoZoomFactor];
    } else {
        return 0.0;
    }
}

- (CGFloat)miniumZoomFactor {
    if (@available(iOS 11.0, *)) {
        return [self.currentDevice minAvailableVideoZoomFactor];
    } else {
        return 0.0;
    }
}

- (void)setZoomFactor:(CGFloat)newZoomFactor {
    if ([self.currentDevice lockForConfiguration:nil]) {
        [self.currentDevice setVideoZoomFactor:newZoomFactor];
        [self.currentDevice unlockForConfiguration];
    }
}

#pragma mark - other settings
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

#pragma mark - camera control
- (void)startCapture {
    [self.session startRunning];
}

- (void)stopCapture {
    [self.session stopRunning];
}

@end
