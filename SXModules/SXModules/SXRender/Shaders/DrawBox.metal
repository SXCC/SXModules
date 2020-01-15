//
//  DrawBox.metal
//  SXModules
//
//  Created by shenxuecen on 2020/1/15.
//  Copyright © 2020 sxcc. All rights reserved.
//

#include <metal_stdlib>
using namespace metal;
#import "ShaderTypes.h"

typedef struct {
    float4 position [[position]];
    float2 textureCoordinate;
} QuadVertexOut;

vertex QuadVertexOut
drawBoxVertexShader(uint vertexID [[vertex_id]],
                     constant Vertex* vertices [[buffer(0)]]) {
    
    QuadVertexOut out;
    out.position = vector_float4(0, 0, 0, 1);
    out.position.xy = vertices[vertexID].position.xy;
    out.textureCoordinate =vertices[vertexID].coordinate.xy;
    return out;
}

fragment float4
drawBoxFragmentShader(QuadVertexOut in [[stage_in]],
                      constant float4* ptColor [[buffer(0)]]) {
    return *ptColor;
}
