//
//  DrawSampleBuffer.metal
//  CameraDemo
//
//  Created by shenxuecen on 2019/10/28.
//  Copyright © 2019 baiduar. All rights reserved.
//

#include <metal_stdlib>
using namespace metal;

#import "ShaderTypes.h"

typedef struct {
    float4 position [[position]];
    float2 textureCoordinate;
} QuadVertexOut;

vertex QuadVertexOut
drawQuadVertexShader(uint vertexID [[vertex_id]],
                     constant Vertex* vertices [[buffer(0)]]) {
    
    QuadVertexOut out;
    out.position = vector_float4(0, 0, 0, 1);
    out.position.xy = vertices[vertexID].position.xy;
    out.textureCoordinate =vertices[vertexID].coordinate.xy;
    return out;
}

fragment float4
drawQuadFragmentShader(QuadVertexOut in [[stage_in]],
                       constant int* texture_type[[buffer(0)]],
                       texture2d<half> texture [[texture(0)]],
                       texture2d<half> texture1 [[texture(1)]]) {

    constexpr sampler textureSampler (mag_filter::linear,
                                      min_filter::linear);
    if(*texture_type == 0) { // bgr input
        const half4 colorPixel = texture.sample(textureSampler, in.textureCoordinate);
        return float4(colorPixel.r, colorPixel.g, colorPixel.b, 1);
    } else { // yuv intput
        const half4 ySample = texture.sample(textureSampler, in.textureCoordinate);
        const half4 uvSample = texture1.sample(textureSampler, in.textureCoordinate);
        
        float3 yuv;
        yuv.x = ySample.r;
        yuv.yz = float2(uvSample.rg - half2(0.5));
        
        float3x3 matrix = {
            {1.164, 1.164, 1.164},
            {0, -0.231, 2.112},
            {1.793, -0.533, 0}
        };
        float3 rgb = matrix * yuv;
        return float4(rgb, 1.0);
    }
    return float4(0, 0, 0, 1);
}
