//
//  MyShaders.metal
//  QLearning1
//
//  Created by Tatsuo Unemi on 2022/12/27.
//

#include <metal_stdlib>
#include "VecTypes.h"
using namespace metal;

// Shader for shapes, lines and polygons
struct RasterizerData {
	float4 position [[position]];
	float4 color;
};
vertex RasterizerData vertexShader(uint vertexID [[vertex_id]],
	constant vector_float2 *vertices [[buffer(IndexVertices)]],
	constant vector_float4 *colors [[buffer(IndexColors)]],
	constant uint *nv [[buffer(IndexNVforP)]],
	constant vector_float2 *geomFactor [[buffer(IndexGeomFactor)]]) {
    RasterizerData out = {{0.,0.,0.,1.}};
    out.position.xy = vertices[vertexID] / geomFactor->xy * 2. - 1.;
    out.color = (*nv == 0)? *colors : colors[vertexID / *nv];
    return out;
}
fragment float4 fragmentShader(RasterizerData in [[stage_in]]) {
    return in.color;
}
// Shader for texture
struct RasterizerDataTex {
	float4 position [[position]];
	float2 textureCoordinate;
};
vertex RasterizerDataTex vertexShaderTex(uint vertexID [[vertex_id]],
	constant vector_float2 *vertices [[buffer(IndexVertices)]],
	constant vector_float2 *geomFactor [[buffer(IndexGeomFactor)]]) {
    RasterizerDataTex out = {{0.,0.,0.,1.}, {0.,0.}};
    out.position.xy = vertices[vertexID] / geomFactor->xy * 2. - 1.;
    out.textureCoordinate = float2(vertexID % 2, 1 - vertexID / 2);
    return out;
}
fragment float4 fragmentShaderTex(RasterizerDataTex in [[stage_in]],
	texture2d<half> colorTexture [[texture(IndexTexture)]]) {
	constexpr sampler textureSampler(mag_filter::linear, min_filter::linear);
	const half4 s = colorTexture.sample(textureSampler, in.textureCoordinate);
    return float4(s.bgra);
}
