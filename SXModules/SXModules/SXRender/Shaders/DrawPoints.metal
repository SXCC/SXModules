//
//  DrawPoints.metal
//  CameraDemo
//
//  Created by shenxuecen on 2019/10/28.
//  Copyright © 2019 baiduar. All rights reserved.
//

#include <metal_stdlib>
#include "ShaderTypes.h"
using namespace metal;

typedef struct {
    float4 position [[position]];
    float2 textureCoordinate;
    float pointsize[[point_size]];
} QuadVertexOut;

vertex QuadVertexOut
vertexDrawerVertexShader(uint vertexID [[vertex_id]],
                         constant Vertex* vertices [[buffer(0)]]) {
    QuadVertexOut out;
    out.position = vector_float4(0, 0, 0, 1);
    out.position.xy = vertices[vertexID].position.xy;
    out.textureCoordinate =vertices[vertexID].coordinate.xy;
    out.pointsize = 5.0;
    return out;
}

fragment float4
vertexDrawerFragmentShader(QuadVertexOut in [[stage_in]]) {
    return float4(0.0, 1.0, 0.0, 1.0);
}
