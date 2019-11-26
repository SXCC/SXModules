//
//  DrawTargetTexture.metal
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
drawTargetTextureVertexShader(uint vertexID [[vertex_id]],
                             constant Vertex* vertices [[buffer(0)]]) {
    
    QuadVertexOut out;
    out.position = vector_float4(0, 0, 0, 1);
    out.position.xy = vertices[vertexID].position.xy;
    out.textureCoordinate =vertices[vertexID].coordinate.xy;
    return out;
}

fragment float4
drawTargetTextureFragmentShader(QuadVertexOut in [[stage_in]],
                               texture2d<half> texture [[texture(0)]]) {

    constexpr sampler textureSampler (mag_filter::linear,
                                      min_filter::linear);
    const half4 colorPixel = texture.sample(textureSampler, in.textureCoordinate);
    return float4(colorPixel.r, colorPixel.g, colorPixel.b, 1);
    
}
