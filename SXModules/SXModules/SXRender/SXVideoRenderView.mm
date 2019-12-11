//
//  SXVideoRenderView.m
//  SXModules
//
//  Created by shenxuecen on 2019/10/28.
//  Copyright © 2019 sxcc. All rights reserved.
//

#import "SXVideoRenderView.h"
#import "ShaderTypes.h"

@implementation SXRenderPointAttr

- (id)init {
    self = [super init];
    if (self) {
        _pointSize = 4;
        _pointColor = [UIColor redColor];
    }
    return self;
}

- (id)initWithPointSize:(float)ptSize PointColor:(UIColor *)color {
    self = [super init];
    if (self) {
        _pointSize = ptSize;
        _pointColor = color;
    }
    return self;
}
@end


@interface SXVideoRenderView ()
@property (assign, nonatomic) BOOL initialized;
@property (strong, nonatomic) id<MTLCommandQueue> commandQueue;
@property (strong, nonatomic) id<MTLLibrary> library;
//
@property (strong, nonatomic) id<MTLBuffer> drawQuadVertexBuffer;
// 自定义Draw的渲染目标纹理
@property (strong, nonatomic) id<MTLTexture> intermediateTexture;
@property (strong, nonatomic) MTLRenderPassDescriptor *intermediateTextureRenderDesc;
@property (assign, nonatomic) MTLViewport intermediateDrawCallViewPort;
// 覆盖渲染相机SampleBuffer到intermediateTexture
@property (strong, nonatomic) id<MTLRenderPipelineState> drawSampleBufferPipelineState;
// 叠加渲染归一化特征点到intermediateTexture
@property (strong, nonatomic) id<MTLRenderPipelineState> drawNormalizedPointsPipelineState;
// 叠加渲染mask到intermediateTexture
@property (strong, nonatomic) id<MTLRenderPipelineState> blendMaskPipelineState;

// 渲染intermediate texture到MTKView
@property (strong, nonatomic) id<MTLRenderPipelineState> screenRenderPipelineState;

// 渲染intermediate texture到CVPixelBuffer
@property (strong, nonatomic) id<MTLRenderPipelineState> pixelBufferRenderPipelineState;
@property (strong, nonatomic) MTLRenderPassDescriptor* pixelBufferRenderPassDesc;

@property (assign, nonatomic) CVMetalTextureCacheRef textureCache;
@end

@implementation SXVideoRenderView
#pragma mark - public interface

- (id)initWithFrame:(CGRect)frame
             Device:(id<MTLDevice>)device
        LibraryPath:(NSString * _Nullable)libraryPath
         BufferSize:(CGSize)bufferSize {
    self = [super initWithFrame:frame device:device];
    if (self) {
        _commandQueue = [self.device newCommandQueue];
        
        if (libraryPath) {
            NSError* error;
            _library = [self.device newLibraryWithFile:libraryPath error:&error];
            if (error) {
                NSLog(@"[SXVideoRenderView init:][Error]: Create Metal library with input path failed!");
                return nil;
            }
        } else {
            NSBundle* frameworkBundle = [NSBundle bundleForClass:[self class]];
            NSError* error;
            _library = [self.device newDefaultLibraryWithBundle:frameworkBundle error:&error];
            if (error) {
                NSLog(@"[SXVideoRenderView init:][Error]: Create Metal library with default path failed!");
                return nil;
            }
        }
        
        CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, self.device, nil, &_textureCache);
        if (self.textureCache == nil) {
            NSLog(@"[SXVideoRenderView init:][Error]: Failed to create texture cache");
            return nil;
        }
        [self setupIntermediateTextureRenderPipeline:bufferSize];
        [self setupPixelBufferRenderPipelineState];
        [self setupCommonBuffers];
        [self setupScreenRenderPipeline];
        [self setupDrawPointPipeline];
        [self setupMaskBlendRenderPipeline];
        [self setPaused:true];
        [self setEnableSetNeedsDisplay:true];
    }
    return self;
}

#pragma mark - draw calls
- (void)drawSampleBuffer:(CMSampleBufferRef)sampleBuffer CleanBuffer:(BOOL)clean {
    CVPixelBufferRef pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
    [self drawPixelBuffer:pixelBuffer CleanBuffer:clean];
}

- (void)drawPixelBuffer:(CVPixelBufferRef)pixelBuffer CleanBuffer:(BOOL)clean {
    if (clean) {
        self.intermediateTextureRenderDesc.colorAttachments[0].loadAction = MTLLoadActionClear;
    } else {
        self.intermediateTextureRenderDesc.colorAttachments[0].loadAction = MTLLoadActionLoad;
    }
    id<MTLCommandBuffer> commandBuffer = [self.commandQueue commandBuffer];
    id<MTLRenderCommandEncoder> renderCmdEncoder =
        [commandBuffer renderCommandEncoderWithDescriptor:self.intermediateTextureRenderDesc];
    [renderCmdEncoder setRenderPipelineState:self.drawSampleBufferPipelineState];
    [renderCmdEncoder setViewport:self.intermediateDrawCallViewPort];
    [renderCmdEncoder setVertexBuffer:self.drawQuadVertexBuffer offset:0 atIndex:0];

    if(CVPixelBufferGetPixelFormatType(pixelBuffer) == kCVPixelFormatType_32BGRA) {
        id<MTLTexture> texture = [self textureFromPixelBuffer:pixelBuffer];
        [renderCmdEncoder setFragmentTexture:texture atIndex:0];
        [renderCmdEncoder setFragmentTexture:texture atIndex:1];
        int textureType = 0;
        [renderCmdEncoder setFragmentBytes:&textureType length:sizeof(int) atIndex:0];
    } else {
        NSArray* textures = [self texturesFromYUVPixelBuffer:pixelBuffer];
        [renderCmdEncoder setFragmentTexture:textures[0] atIndex:0];
        [renderCmdEncoder setFragmentTexture:textures[1] atIndex:1];
        int textureType = 1;
        [renderCmdEncoder setFragmentBytes:&textureType length:sizeof(int) atIndex:0];
    }
    
    [renderCmdEncoder drawPrimitives:MTLPrimitiveTypeTriangleStrip vertexStart:0 vertexCount:4];
    [renderCmdEncoder endEncoding];
    [commandBuffer commit];
}

- (void)drawNormalizedPoints:(NSArray *)normalizedPoints {
    [self drawNormalizedPoints:normalizedPoints withAttr:[[SXRenderPointAttr alloc] init]] ;
}

- (void)drawNormalizedPoints:(NSArray *)normalizedPoints withAttr:(SXRenderPointAttr *)attr {
    if ([normalizedPoints count] == 0) {
        return;
    }
    int sum = (int)[normalizedPoints count];
    Vertex *buffer = (Vertex *)malloc(sizeof(Vertex) * sum);
    int index = 0;
    for (NSValue* item in normalizedPoints) {
        CGPoint pt = [item CGPointValue];
        buffer[index] = {{ float((pt.x - 0.5) * 2), float((0.5 - pt.y) * 2), 0, 1}, {0, 0}};
        index++;
    }
    id<MTLBuffer> drawPointBuffer = [self.device newBufferWithLength:sizeof(Vertex) * sum options:MTLResourceStorageModeShared];
    memcpy(drawPointBuffer.contents, buffer, sizeof(Vertex) * sum);
    free(buffer);
    id<MTLCommandBuffer> commandBuffer = [self.commandQueue commandBuffer];
    self.intermediateTextureRenderDesc.colorAttachments[0].loadAction = MTLLoadActionLoad;    // 保留intermediateTexture已有内容
    id<MTLRenderCommandEncoder> renderCmdEncoder =
        [commandBuffer renderCommandEncoderWithDescriptor:self.intermediateTextureRenderDesc];
    [renderCmdEncoder setRenderPipelineState:self.drawNormalizedPointsPipelineState];
    [renderCmdEncoder setViewport:self.intermediateDrawCallViewPort];
    [renderCmdEncoder setVertexBuffer:drawPointBuffer offset:0 atIndex:0];
    float ptSize = attr.pointSize;
    [renderCmdEncoder setVertexBytes:&ptSize length:sizeof(float) atIndex:1];
    CGFloat r, g, b, a;
    [attr.pointColor getRed:&r green:&g blue:&b alpha:&a];
    vector_float4 ptColor = {float(r), float(g), float(b), float(a)};
    [renderCmdEncoder setFragmentBytes:&ptColor length:sizeof(ptColor) atIndex:0];
    [renderCmdEncoder drawPrimitives:MTLPrimitiveTypePoint vertexStart:0 vertexCount:sum];
    [renderCmdEncoder endEncoding];
    [commandBuffer commit];
}

- (void)blendMask:(unsigned char *)maskBytes
            Width:(int)width
           Height:(int)height
         Channels:(int)channels
      BytesPerRow:(int)rowBytes {
    MTLPixelFormat format;
    switch (channels) {
        case 4:
            format = MTLPixelFormatBGRA8Unorm;
            break;
        case 1:
            format = MTLPixelFormatR8Unorm;
            break;
        default:
            format = MTLPixelFormatR8Unorm;
            break;
    }
    
    MTLTextureDescriptor *textureDesc = [[MTLTextureDescriptor alloc] init];
    textureDesc.width = width;
    textureDesc.height = height;
    textureDesc.pixelFormat = format;
    textureDesc.usage = MTLTextureUsageShaderRead;
    
    id<MTLTexture> maskTexture = [self.device newTextureWithDescriptor:textureDesc];
    [maskTexture replaceRegion:{{0, 0, 0}, {static_cast<NSUInteger>(width), static_cast<NSUInteger>(height), 1}}
                   mipmapLevel:0
                     withBytes:maskBytes
                   bytesPerRow:rowBytes];
    
    id<MTLCommandBuffer> commandBuffer = [self.commandQueue commandBuffer];
    self.intermediateTextureRenderDesc.colorAttachments[0].loadAction = MTLLoadActionLoad;    // 保留intermediateTexture已有内容
    id<MTLRenderCommandEncoder> renderCmdEncoder =
        [commandBuffer renderCommandEncoderWithDescriptor:self.intermediateTextureRenderDesc];
    [renderCmdEncoder setRenderPipelineState:self.blendMaskPipelineState];
    [renderCmdEncoder setViewport:self.intermediateDrawCallViewPort];
    [renderCmdEncoder setVertexBuffer:self.drawQuadVertexBuffer offset:0 atIndex:0];

    [renderCmdEncoder setFragmentTexture:self.intermediateTexture atIndex:0]; // input and output
    [renderCmdEncoder setFragmentTexture:maskTexture atIndex:1];
    
    [renderCmdEncoder drawPrimitives:MTLPrimitiveTypeTriangleStrip vertexStart:0 vertexCount:4];
    [renderCmdEncoder endEncoding];
    [commandBuffer commit];
    
}

#pragma mark - draw call configs
- (void)setViewPort:(MTLViewport)newViewPort {
    self.intermediateDrawCallViewPort = newViewPort;
}

- (void)clearViewPortToDefault {
    self.intermediateDrawCallViewPort = {0, 0, static_cast<double>(self.intermediateTexture.width), static_cast<double>(self.intermediateTexture.height), 0, 1};
}

#pragma mark - output
- (void)renderToScreen {
    [self setNeedsDisplay];
}

- (void)drawRect:(CGRect)rect {
    if (self.currentDrawable == nil) {
        return;
    }
    id<MTLCommandBuffer> commandBuffer = [self.commandQueue commandBuffer];
    MTLRenderPassDescriptor *renderPassDesc = self.currentRenderPassDescriptor;
    if (renderPassDesc) {
        // draw background
        id<MTLRenderCommandEncoder> renderCmdEncoder =
            [commandBuffer renderCommandEncoderWithDescriptor:renderPassDesc];
        [renderCmdEncoder setRenderPipelineState:self.screenRenderPipelineState];
        [renderCmdEncoder setVertexBuffer:self.drawQuadVertexBuffer offset:0 atIndex:0];
        [renderCmdEncoder setFragmentTexture:self.intermediateTexture atIndex:0];
        [renderCmdEncoder setFragmentTexture:self.intermediateTexture atIndex:1];
        int textureType = 0;
        [renderCmdEncoder setFragmentBytes:&textureType length:sizeof(int) atIndex:0];
        [renderCmdEncoder drawPrimitives:MTLPrimitiveTypeTriangleStrip vertexStart:0 vertexCount:4];
        [renderCmdEncoder endEncoding];
        [commandBuffer presentDrawable:self.currentDrawable];
    }
    [commandBuffer commit];
    [commandBuffer waitUntilCompleted];
}

- (void)renderToPixelBuffer:(CVPixelBufferRef)pixelBuffer {
    // get texture from pixelbuffer
    id<MTLTexture> targetTexture = [self textureFromPixelBuffer:pixelBuffer];
    // create render pipeline
    self.pixelBufferRenderPassDesc.colorAttachments[0].texture = targetTexture;
    
    id<MTLCommandBuffer> commandBuffer = [self.commandQueue commandBuffer];
    id<MTLRenderCommandEncoder> renderCmdEncoder = [commandBuffer renderCommandEncoderWithDescriptor:self.pixelBufferRenderPassDesc];
    [renderCmdEncoder setRenderPipelineState:self.pixelBufferRenderPipelineState];
    [renderCmdEncoder setVertexBuffer:self.drawQuadVertexBuffer offset:0 atIndex:0];
    [renderCmdEncoder setFragmentTexture:self.intermediateTexture atIndex:0];
    [renderCmdEncoder setFragmentTexture:self.intermediateTexture atIndex:1];
    int textureType = 0;
    [renderCmdEncoder setFragmentBytes:&textureType length:sizeof(int) atIndex:0];
    [renderCmdEncoder drawPrimitives:MTLPrimitiveTypeTriangleStrip vertexStart:0 vertexCount:4];
    [renderCmdEncoder endEncoding];
    [commandBuffer commit];
    [commandBuffer waitUntilCompleted];
}

#pragma mark - private interface
- (id<MTLTexture>)textureFromSampleBuffer:(CMSampleBufferRef)sampleBuffer {
    CVPixelBufferRef pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
    return [self textureFromPixelBuffer:pixelBuffer];
}

- (id<MTLTexture>)textureFromPixelBuffer:(CVPixelBufferRef)pixelBuffer {
    int width = (int)CVPixelBufferGetWidth(pixelBuffer);
    int height = (int)CVPixelBufferGetHeight(pixelBuffer);
    CVMetalTextureRef textureRef;
    CVMetalTextureCacheCreateTextureFromImage(kCFAllocatorDefault,
                                              self.textureCache,
                                              pixelBuffer, nil,
                                              MTLPixelFormatBGRA8Unorm,
                                              width, height, 0, &textureRef);
    if (textureRef != nil) {
        id<MTLTexture> texture = CVMetalTextureGetTexture(textureRef);
        CFRelease(textureRef);
        return texture;
    } else {
        MTLTextureDescriptor* textureDesc = [[MTLTextureDescriptor alloc] init];
        textureDesc.width = width;
        textureDesc.height = height;
        textureDesc.pixelFormat = MTLPixelFormatBGRA8Unorm;
        id<MTLTexture> texture = [self.device newTextureWithDescriptor:textureDesc];
        CVPixelBufferLockBaseAddress(pixelBuffer, 0);
        unsigned char* addr = (unsigned char*)CVPixelBufferGetBaseAddress(pixelBuffer);
        [texture replaceRegion:{{0, 0, 0},  {static_cast<NSUInteger>(width), static_cast<NSUInteger>(height), 1}} mipmapLevel:0 withBytes:addr bytesPerRow:CVPixelBufferGetBytesPerRow(pixelBuffer)];
        return texture;
    }
}

- (NSArray<id<MTLTexture>> *)texturesFromYUVPixelBuffer:(CVPixelBufferRef)pixelBuffer {
    int yWidth = (int)CVPixelBufferGetWidthOfPlane(pixelBuffer, 0);
    int yHeight = (int)CVPixelBufferGetHeightOfPlane(pixelBuffer, 0);
    
    int uvWidth = (int)CVPixelBufferGetWidthOfPlane(pixelBuffer, 1);
    int uvHeight = (int)CVPixelBufferGetHeightOfPlane(pixelBuffer, 1);
    
    CVMetalTextureRef yTextureRef, uvTextureRef;
    
    CVPixelBufferLockBaseAddress(pixelBuffer, 0);
    CVMetalTextureCacheCreateTextureFromImage(kCFAllocatorDefault,
                                              self.textureCache,
                                              pixelBuffer, nil,
                                              MTLPixelFormatR8Unorm,
                                              yWidth, yHeight, 0, &yTextureRef);
    CVMetalTextureCacheCreateTextureFromImage(kCFAllocatorDefault,
                                              self.textureCache,
                                              pixelBuffer, nil,
                                              MTLPixelFormatRG8Unorm,
                                              uvWidth, uvHeight, 1, &uvTextureRef);
    if (yTextureRef != nil && uvTextureRef != nil) {
        id<MTLTexture> yTexture = CVMetalTextureGetTexture(yTextureRef);
        id<MTLTexture> uvTexture = CVMetalTextureGetTexture(uvTextureRef);
        CFRelease(yTextureRef);
        CFRelease(uvTextureRef);
        CVPixelBufferUnlockBaseAddress(pixelBuffer, 0);
        return @[yTexture, uvTexture];
    }
    
    MTLTextureDescriptor* yTextureDesc = [[MTLTextureDescriptor alloc] init];
    yTextureDesc.width = yWidth;
    yTextureDesc.height = yHeight;
    yTextureDesc.pixelFormat = MTLPixelFormatR8Unorm;
    id<MTLTexture> yTexture = [self.device newTextureWithDescriptor:yTextureDesc];
    unsigned char* addr = (unsigned char*)CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 0);
    [yTexture replaceRegion:{{0, 0, 0},  {static_cast<NSUInteger>(yWidth), static_cast<NSUInteger>(yHeight), 1}} mipmapLevel:0 withBytes:addr bytesPerRow:CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 0)];
    
    MTLTextureDescriptor* uvTextureDesc = [[MTLTextureDescriptor alloc] init];
    uvTextureDesc.width = uvWidth;
    uvTextureDesc.height = uvHeight;
    uvTextureDesc.pixelFormat = MTLPixelFormatRG8Unorm;
    id<MTLTexture> uvTexture = [self.device newTextureWithDescriptor:uvTextureDesc];
    addr = (unsigned char*)CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 1);
    [uvTexture replaceRegion:{{0, 0, 0},  {static_cast<NSUInteger>(uvHeight), static_cast<NSUInteger>(uvWidth), 1}} mipmapLevel:0 withBytes:addr bytesPerRow:CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 1)];
    
    CVPixelBufferUnlockBaseAddress(pixelBuffer, 0);
    
    return @[yTexture, uvTexture];
}


- (void)setupCommonBuffers {
    Vertex vll = Vertex{ {-1, -1, 1, 1}, {0, 1} };
    Vertex vlr = Vertex{ {1, -1, 1, 1}, {1, 1} };
    Vertex vul = Vertex{ {-1, 1, 1, 1}, {0, 0} };
    Vertex vur = Vertex{ {1, 1, 1, 1}, {1, 0} };
    Vertex vertex[4] = {vll, vlr, vul, vur};
    self.drawQuadVertexBuffer = [self.device newBufferWithBytes:vertex
                                                         length:sizeof(Vertex) * 4
                                                        options:MTLResourceStorageModeShared];
    memcpy(self.drawQuadVertexBuffer.contents, vertex, sizeof(Vertex) * 4);
}

- (void)setupScreenRenderPipeline {
    id<MTLFunction> vertexFunc = [self.library newFunctionWithName:@"drawQuadVertexShader"];
    id<MTLFunction> fragFunc = [self.library newFunctionWithName:@"drawQuadFragmentShader"];

    MTLRenderPipelineDescriptor *pipelineDesc = [[MTLRenderPipelineDescriptor alloc] init];
    pipelineDesc.colorAttachments[0].pixelFormat = self.colorPixelFormat;
    pipelineDesc.vertexFunction = vertexFunc;
    pipelineDesc.fragmentFunction = fragFunc;
    NSError *error;
    self.screenRenderPipelineState =
        [self.device newRenderPipelineStateWithDescriptor:pipelineDesc error:&error];
    if (error) {
      NSLog(@"%@", [error localizedDescription]);
      abort();
    }
}

- (void)setupDrawPointPipeline {
    // hard code: max 600点
    id<MTLFunction> vertexFunc = [self.library newFunctionWithName:@"vertexDrawerVertexShader"];
    id<MTLFunction> fragFunc = [self.library newFunctionWithName:@"vertexDrawerFragmentShader"];

    MTLRenderPipelineDescriptor *pipelineDesc = [[MTLRenderPipelineDescriptor alloc] init];
    pipelineDesc.colorAttachments[0].pixelFormat = self.colorPixelFormat;
    pipelineDesc.vertexFunction = vertexFunc;
    pipelineDesc.fragmentFunction = fragFunc;
    NSError *error;
    self.drawNormalizedPointsPipelineState =
        [self.device newRenderPipelineStateWithDescriptor:pipelineDesc error:&error];
    if (error) {
      NSLog(@"%@", [error localizedDescription]);
      abort();
    }
}

- (void)setupIntermediateTextureRenderPipeline:(CGSize)size {
    MTLTextureDescriptor *textureDesc = [[MTLTextureDescriptor alloc] init];
    textureDesc.width = size.width;
    textureDesc.height = size.height;
    textureDesc.pixelFormat = MTLPixelFormatBGRA8Unorm;
    textureDesc.usage = MTLTextureUsageShaderRead | MTLTextureUsageShaderWrite | MTLTextureUsageRenderTarget;
    self.intermediateTexture = [self.device newTextureWithDescriptor:textureDesc];

    self.intermediateTextureRenderDesc = [[MTLRenderPassDescriptor alloc] init];
    self.intermediateTextureRenderDesc.colorAttachments[0].loadAction = MTLLoadActionDontCare;
    self.intermediateTextureRenderDesc.colorAttachments[0].storeAction = MTLStoreActionStore;
    self.intermediateTextureRenderDesc.colorAttachments[0].texture = self.intermediateTexture;
    
    self.intermediateDrawCallViewPort = {0, 0, static_cast<double>(textureDesc.width), static_cast<double>(textureDesc.height), 0, 1};

    id<MTLFunction> vertexFunc = [self.library newFunctionWithName:@"drawQuadVertexShader"];
    id<MTLFunction> fragFunc = [self.library newFunctionWithName:@"drawQuadFragmentShader"];

    MTLRenderPipelineDescriptor *pipelineDesc = [[MTLRenderPipelineDescriptor alloc] init];
    pipelineDesc.colorAttachments[0].pixelFormat = MTLPixelFormatBGRA8Unorm;
    pipelineDesc.vertexFunction = vertexFunc;
    pipelineDesc.fragmentFunction = fragFunc;
    NSError *error;
    self.drawSampleBufferPipelineState =
        [self.device newRenderPipelineStateWithDescriptor:pipelineDesc error:&error];
    if (error) {
       NSLog(@"%@", [error localizedDescription]);
       abort();
    }
}

- (void)setupPixelBufferRenderPipelineState {
    self.pixelBufferRenderPassDesc = [[MTLRenderPassDescriptor alloc] init];
    self.pixelBufferRenderPassDesc.colorAttachments[0].loadAction = MTLLoadActionClear;
    self.pixelBufferRenderPassDesc.colorAttachments[0].storeAction = MTLStoreActionStore;
    
    MTLRenderPipelineDescriptor* pipelineDesc = [[MTLRenderPipelineDescriptor alloc] init];
    pipelineDesc.colorAttachments[0].pixelFormat = MTLPixelFormatBGRA8Unorm;
    
    id<MTLFunction> vertexFunc = [self.library newFunctionWithName:@"drawQuadVertexShader"];
    id<MTLFunction> fragFunc = [self.library newFunctionWithName:@"drawQuadFragmentShader"];
    pipelineDesc.vertexFunction = vertexFunc;
    pipelineDesc.fragmentFunction = fragFunc;
    
    NSError *error;
    self.pixelBufferRenderPipelineState =
        [self.device newRenderPipelineStateWithDescriptor:pipelineDesc error:&error];
    if (error) {
       NSLog(@"%@", [error localizedDescription]);
       abort();
    }
}



- (void)setupMaskBlendRenderPipeline {
    id<MTLFunction> vertexFunc = [self.library newFunctionWithName:@"blendMaskVertexShader"];
    id<MTLFunction> fragFunc = [self.library newFunctionWithName:@"blendMaskFragmentShader"];
    MTLRenderPipelineDescriptor *pipelineDesc = [[MTLRenderPipelineDescriptor alloc] init];
    pipelineDesc.colorAttachments[0].pixelFormat = self.colorPixelFormat;
    pipelineDesc.vertexFunction = vertexFunc;
    pipelineDesc.fragmentFunction = fragFunc;
    NSError *error;
    self.blendMaskPipelineState =
        [self.device newRenderPipelineStateWithDescriptor:pipelineDesc error:&error];
    if (error) {
      NSLog(@"%@", [error localizedDescription]);
      abort();
    }
}
@end
