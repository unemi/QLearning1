//
//  MyShaders.metal
//  LearningIsLife
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
	constant float2 *vertices [[buffer(IndexVertices)]],
	constant float4 *colors [[buffer(IndexColors)]],
	constant uint *nv [[buffer(IndexNVforP)]],
	constant float2 *geomFactor [[buffer(IndexGeomFactor)]]) {
    RasterizerData out = {{0.,0.,0.,1.}};
    out.position.xy = vertices[vertexID] / *geomFactor * 2. - 1.;
    out.color = (*nv == 0)? *colors : colors[vertexID / *nv];
    return out;
}
fragment float4 fragmentShader(RasterizerData in [[stage_in]]) {
    return in.color;
}
// Shader for texture with color
struct RasterizerDataTex {
	float4 position [[position]];
	float2 textureCoordinate;
};
vertex RasterizerDataTex vertexShaderTex(uint vertexID [[vertex_id]],
	constant float2 *vertices [[buffer(IndexVertices)]],
	constant float2 *geomFactor [[buffer(IndexGeomFactor)]]) {
    RasterizerDataTex out = {{0.,0.,0.,1.}, {0.,0.}};
    out.position.xy = vertices[vertexID] / *geomFactor * 2. - 1.;
    out.textureCoordinate = float2(vertexID % 2, 1 - vertexID / 2);
    return out;
}
fragment float4 fragmentShaderTex(RasterizerDataTex in [[stage_in]],
	texture2d<half> colorTexture [[texture(IndexTexture)]],
	constant float4 *color [[buffer(IndexFrgColor)]]) {
	constexpr sampler textureSampler(mag_filter::linear, min_filter::linear);
	const half4 s = colorTexture.sample(textureSampler, in.textureCoordinate);
    return *color * (float4){1.,1.,1.,s.a};
}
// Shader for Tracked Points
struct RasterizerDataTP {
	float4 position [[position]];
	float2 pixCoord;
};
vertex RasterizerDataTP vertexShaderTP(uint vertexID [[vertex_id]],
	constant float2 *vertices [[buffer(IndexVertices)]],
	constant float2 *geomFactor [[buffer(IndexGeomFactor)]]) {
    RasterizerDataTP out = {{0.,0.,0.,1.}};
    out.position.xy = vertices[vertexID] / *geomFactor * 2. - 1.;
    out.pixCoord = vertices[vertexID];
	return out;
}
fragment float4 fragmentShaderTP(RasterizerDataTP in [[stage_in]],
	constant uint *n [[buffer(IndexTPN)]],
	constant float3 *tpInfo [[buffer(IndexTPInfo)]],
	constant float4 *color [[buffer(IndexTPColor)]]) {
	float a = 0.;
	for (uint i = 0; i < *n; i ++)
		a = max(a, sqrt(1. - pow(min(1., distance(in.pixCoord, tpInfo[i].xy) / tpInfo[i].z), 2.)));
	return float4(color->rgb, color->a * a);
}
