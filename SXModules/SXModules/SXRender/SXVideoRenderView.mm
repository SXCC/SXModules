//
//  SXVideoRenderView.m
//  SXModules
//
//  Created by shenxuecen on 2019/10/28.
//  Copyright © 2019 sxcc. All rights reserved.
//

#import "SXVideoRenderView.h"
#import "ShaderTypes.h"

@interface SXVideoRenderView ()
@property (assign, nonatomic) BOOL initialized;
@property (strong, nonatomic) id<MTLCommandQueue> commandQueue;
@property (strong, nonatomic) id<MTLLibrary> library;
//
@property (strong, nonatomic) id<MTLBuffer> drawQuadVertexBuffer;
// 自定义Draw的渲染目标纹理
@property (strong, nonatomic) id<MTLTexture> targetTexture;
@property (strong, nonatomic) MTLRenderPassDescriptor *targetTextureRenderDesc;
// 覆盖渲染相机SampleBuffer到targetTexture
@property (strong, nonatomic) id<MTLRenderPipelineState> drawSampleBufferPipelineState;
// 叠加渲染归一化特征点到targetTexture
@property (strong, nonatomic) id<MTLRenderPipelineState> drawNormalizedPointsPipelineState;
@property (strong, nonatomic) id<MTLBuffer> drawPointBuffer;
// 叠加渲染mask到targetTexture
@property (strong, nonatomic) id<MTLRenderPipelineState> blendMaskPipelineState;

// 渲染target texture到MTKView
@property (strong, nonatomic) id<MTLRenderPipelineState> renderViewBGPipelineState;
@property (strong, nonatomic) id<MTLBuffer> renderViewBGVertexBuffer;

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
        [self setupTargetTextureRenderPipeline:bufferSize];
        [self setupCommonBuffers];
        [self setupRenderViewBGPipeline];
        [self setupDrawPointPipeline];
        [self setupMaskBlendRenderPipeline];
        [self setPaused:true];
        [self setEnableSetNeedsDisplay:true];
    }
    return self;
}


- (void)drawSampleBuffer:(CMSampleBufferRef)sampleBuffer {
    CVPixelBufferRef pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
    [self drawPixelBuffer:pixelBuffer];
}

- (void)drawPixelBuffer:(CVPixelBufferRef)pixelBuffer {
    self.targetTextureRenderDesc.colorAttachments[0].loadAction = MTLLoadActionClear;
    id<MTLCommandBuffer> commandBuffer = [self.commandQueue commandBuffer];
    id<MTLRenderCommandEncoder> renderCmdEncoder =
        [commandBuffer renderCommandEncoderWithDescriptor:self.targetTextureRenderDesc];
    [renderCmdEncoder setRenderPipelineState:self.drawSampleBufferPipelineState];
    [renderCmdEncoder setVertexBuffer:self.drawQuadVertexBuffer offset:0 atIndex:0];
    id<MTLTexture> texture = [self textureFromPixelBuffer:pixelBuffer];
    [renderCmdEncoder setFragmentTexture:texture atIndex:0];
    [renderCmdEncoder drawPrimitives:MTLPrimitiveTypeTriangleStrip vertexStart:0 vertexCount:4];
    [renderCmdEncoder endEncoding];
    [commandBuffer commit];
}

- (void)drawNormalizedPoints:(NSArray *)normalizedPoints {
    if ([normalizedPoints count] == 0) {
        return;
    }
    int sum = 0;
    for (NSArray* arr in normalizedPoints) {
        sum += [arr count];
    }
    Vertex *buffer = (Vertex *)malloc(sizeof(Vertex) * sum);
    int index = 0;
    for (NSArray* arr in normalizedPoints) {
        for (NSValue* item in arr) {
            CGPoint pt = [item CGPointValue];
            buffer[index] = {{ float((pt.x - 0.5) * 2), float((0.5 - pt.y) * 2), 0, 1}, {0, 0}};
            index++;
        }
    }
    memcpy(self.drawPointBuffer.contents, buffer, sizeof(Vertex) * sum);
    free(buffer);
    
    id<MTLCommandBuffer> commandBuffer = [self.commandQueue commandBuffer];
    self.targetTextureRenderDesc.colorAttachments[0].loadAction = MTLLoadActionLoad;    // 保留targetTexture已有内容
    id<MTLRenderCommandEncoder> renderCmdEncoder =
        [commandBuffer renderCommandEncoderWithDescriptor:self.targetTextureRenderDesc];
    [renderCmdEncoder setRenderPipelineState:self.drawNormalizedPointsPipelineState];
    [renderCmdEncoder setVertexBuffer:self.drawPointBuffer offset:0 atIndex:0];
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
    self.targetTextureRenderDesc.colorAttachments[0].loadAction = MTLLoadActionLoad;    // 保留targetTexture已有内容
    id<MTLRenderCommandEncoder> renderCmdEncoder =
        [commandBuffer renderCommandEncoderWithDescriptor:self.targetTextureRenderDesc];
    [renderCmdEncoder setRenderPipelineState:self.blendMaskPipelineState];
    [renderCmdEncoder setVertexBuffer:self.drawQuadVertexBuffer offset:0 atIndex:0];

    [renderCmdEncoder setFragmentTexture:self.targetTexture atIndex:0]; // input and output
    [renderCmdEncoder setFragmentTexture:maskTexture atIndex:1];
    
    [renderCmdEncoder drawPrimitives:MTLPrimitiveTypeTriangleStrip vertexStart:0 vertexCount:4];
    [renderCmdEncoder endEncoding];
    [commandBuffer commit];
    
}

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
        [renderCmdEncoder setRenderPipelineState:self.renderViewBGPipelineState];
        [renderCmdEncoder setVertexBuffer:self.drawQuadVertexBuffer offset:0 atIndex:0];
        [renderCmdEncoder setFragmentTexture:self.targetTexture atIndex:0];
        [renderCmdEncoder drawPrimitives:MTLPrimitiveTypeTriangleStrip vertexStart:0 vertexCount:4];
        [renderCmdEncoder endEncoding];
        [commandBuffer presentDrawable:self.currentDrawable];
    }
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
    if (textureRef == nil) {
        MTLTextureDescriptor* textureDesc = [[MTLTextureDescriptor alloc] init];
        textureDesc.width = width;
        textureDesc.height = height;
        textureDesc.pixelFormat = MTLPixelFormatBGRA8Unorm;
        id<MTLTexture> texture = [self.device newTextureWithDescriptor:textureDesc];
        CVPixelBufferLockBaseAddress(pixelBuffer, 0);
        unsigned char* addr = (unsigned char*)CVPixelBufferGetBaseAddress(pixelBuffer);
        [texture replaceRegion:{{0, 0, 0},  {static_cast<NSUInteger>(width), static_cast<NSUInteger>(height), 1}} mipmapLevel:0 withBytes:addr bytesPerRow:CVPixelBufferGetBytesPerRow(pixelBuffer)];
        return texture;
    } else {
        id<MTLTexture> texture = CVMetalTextureGetTexture(textureRef);
        CFRelease(textureRef);
        return texture;
    }
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

- (void)setupRenderViewBGPipeline {
    id<MTLFunction> vertexFunc = [self.library newFunctionWithName:@"drawTargetTextureVertexShader"];
    id<MTLFunction> fragFunc = [self.library newFunctionWithName:@"drawTargetTextureFragmentShader"];

    MTLRenderPipelineDescriptor *pipelineDesc = [[MTLRenderPipelineDescriptor alloc] init];
    pipelineDesc.colorAttachments[0].pixelFormat = self.colorPixelFormat;
    pipelineDesc.vertexFunction = vertexFunc;
    pipelineDesc.fragmentFunction = fragFunc;
    NSError *error;
    self.renderViewBGPipelineState =
        [self.device newRenderPipelineStateWithDescriptor:pipelineDesc error:&error];
    if (error) {
      NSLog(@"%@", [error localizedDescription]);
      abort();
    }
}

- (void)setupDrawPointPipeline {
    // hard code: max 600点
    self.drawPointBuffer = [self.device newBufferWithLength:sizeof(Vertex) * 600 options:MTLResourceStorageModeShared];
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

- (void)setupTargetTextureRenderPipeline:(CGSize)size {
    MTLTextureDescriptor *textureDesc = [[MTLTextureDescriptor alloc] init];
    textureDesc.width = size.width;
    textureDesc.height = size.height;
    textureDesc.pixelFormat = MTLPixelFormatBGRA8Unorm;
    textureDesc.usage = MTLTextureUsageShaderRead | MTLTextureUsageShaderWrite | MTLTextureUsageRenderTarget;
    self.targetTexture = [self.device newTextureWithDescriptor:textureDesc];

    self.targetTextureRenderDesc = [[MTLRenderPassDescriptor alloc] init];
    self.targetTextureRenderDesc.colorAttachments[0].loadAction = MTLLoadActionDontCare;
    self.targetTextureRenderDesc.colorAttachments[0].storeAction = MTLStoreActionStore;
    self.targetTextureRenderDesc.colorAttachments[0].texture = self.targetTexture;

    id<MTLFunction> vertexFunc = [self.library newFunctionWithName:@"drawSampleBufferVertexShader"];
    id<MTLFunction> fragFunc = [self.library newFunctionWithName:@"drawSampleBufferFragmentShader"];

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