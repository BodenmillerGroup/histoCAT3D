//
//  shaders.metal
//  TestMetal2
//
//  Created by Raul Catena on 9/2/17.
//  Copyright © 2017 CatApps. All rights reserved.
//

#include <metal_stdlib>
#include <metal_matrix>

using namespace metal;

struct Constants {
    float4x4 baseModelMatrix;
    float4x4 modelViewMatrix;
    float4x4 projectionMatrix;
    float4x4 premultipliedMatrix;
    float3x3 normalMatrix;
};

struct PositionalData{
    float leftX;
    float rightX;
    float upperY;
    float lowerY;
    float nearZ;
    float farZ;
    float halfTotalThickness;
    uint totalLayers;
    uint widthModel;
    uint heightModel;
    uint areaModel;
    uint stride;
};

struct VertexOut{
    float4 position [[ position ]];
    float4 color;
    float3 normal;
    float3 eye;
};

struct Light
{
    float3 direction;
    float3 ambientColor;
    float3 diffuseColor;
    float3 specularColor;
};

constant Light light = {
    .direction = { 0.0, 0.0, 1.0 },
    .ambientColor = { 0.2, 0.2, 0.2 },
    .diffuseColor = { 0.8, 0.8, 0.9 },
    .specularColor = { 1, 1, 1 }
};

vertex VertexOut vertexShaderT(const device packed_float3 * vertexArray [[ buffer(4)]],
                              unsigned int iid [[ instance_id ]],
                              constant Constants & uniforms [[ buffer(1) ]],
                              constant PositionalData & positional [[ buffer(2) ]],
                              unsigned int vid [[ vertex_id ]])
{
    VertexOut out;
    float3 pos = float3(vertexArray[iid * 7]);
    out.position = uniforms.projectionMatrix * uniforms.baseModelMatrix * uniforms.modelViewMatrix * float4(pos, 1);
    out.color = float4(1.0f/vid, 1.0f/36 * vid, 0.5, 0.5);
    return out;
}

vertex VertexOut oldvertexShader(
                              const device packed_float3* vertex_array [[ buffer(0) ]],
                              constant Constants & uniforms [[ buffer(1) ]],
                              constant PositionalData & positional [[ buffer(2) ]],
                              const device bool * mask [[ buffer(3) ]],
                              const device float * zValues [[ buffer(4) ]],
                              const device float * colors [[ buffer(5) ]],
                              unsigned int vid [[ vertex_id ]],
                              unsigned int iid [[ instance_id ]]) {
    
    int x = iid % positional.widthModel;
    int y = (iid/positional.widthModel)%positional.heightModel;
    int z = iid / positional.areaModel;
    
    VertexOut out;
    unsigned int baseIndex = iid * 7;
    if(colors[baseIndex] == 0.0f){
        return out;
    }
    
    float3 pos = float3(vertex_array[vid][0] + x - positional.widthModel/2, vertex_array[vid][1] + y - positional.heightModel/2, vertex_array[vid][2]+ z);
    
    //if(mask[iid % positional.areaModel] == true){
        out.position = uniforms.projectionMatrix * uniforms.baseModelMatrix * uniforms.modelViewMatrix * float4(pos, 1);
        out.color = float4(1.0f/vid, 1.0f/36 * vid, 0.5, 0.5);
    //}
    
    return out;
    
    //return float4(vertex_array[vid], 1.0);
}

#define STRIDE_COLOR_ARRAY 8

vertex VertexOut vertexShader(
                              const device packed_float3* vertex_array [[ buffer(0) ]],
                              constant Constants & uniforms [[ buffer(1) ]],
                              constant PositionalData & positional [[ buffer(2) ]],
                              const device bool * mask [[ buffer(3) ]],
                              //const device float * zValues [[ buffer(4) ]],
                              const device float * colors [[ buffer(4) ]],
                              const device bool * heightDescriptor [[ buffer(5) ]],
                              unsigned int vid [[ vertex_id ]],
                              unsigned int iid [[ instance_id ]]) {

    VertexOut out;
    out.position[0] = -100.0;
    unsigned int baseIndex = iid * STRIDE_COLOR_ARRAY;
//    if(colors[baseIndex] == 0.0f)//Precalculated 0 alpha if zero do not process further (optimization)
//        return out;
    
    float down = heightDescriptor[vid] == true? colors[baseIndex + 7] - 1.0f : 0;
    if(colors[baseIndex + 4] < positional.leftX)
        return out;
    if(colors[baseIndex + 4] > positional.rightX)
        return out;
    if(colors[baseIndex + 5] < positional.upperY)
        return out;
    if(colors[baseIndex + 5] > positional.lowerY)
        return out;
    if(colors[baseIndex + 6] < positional.nearZ)
        return out;
    if(colors[baseIndex + 6] > positional.farZ)
        return out;
    
    float3 pos = float3(vertex_array[vid][0] + colors[baseIndex + 4] - positional.widthModel/2,
                        vertex_array[vid][1] + colors[baseIndex + 5] - positional.heightModel/2,
                        vertex_array[vid][2] + colors[baseIndex + 6] - down - positional.halfTotalThickness);
    
    
    //out.position = uniforms.projectionMatrix * uniforms.baseModelMatrix * uniforms.modelViewMatrix * float4(pos, 1);
    out.position = uniforms.premultipliedMatrix * float4(pos, 1);
    out.color = float4(colors[baseIndex + 1], colors[baseIndex + 2], colors[baseIndex + 3], colors[baseIndex]);
    
    return out;
}

fragment float4 fragmentShader(const VertexOut interpolated [[ stage_in ]]){
    return interpolated.color;
}

vertex VertexOut sphereVertexShader(
                              const device packed_float3* vertex_array [[ buffer(0) ]],
                              constant Constants & uniforms [[ buffer(1) ]],
                              constant PositionalData & positional [[ buffer(2) ]],
                              const device float * colors [[ buffer(3) ]],
                              const device packed_float3* normals [[ buffer(4) ]],
                              unsigned int vid [[ vertex_id ]],
                              unsigned int iid [[ instance_id ]]) {
    
    VertexOut out;
    
    unsigned int baseIndex = iid * STRIDE_COLOR_ARRAY;
//    if(colors[baseIndex] == 0.0f)//Precalculated 0 alpha if zero do not process further (optimization)
//        return out;
//    if(colors[baseIndex + 4] < positional.leftX)
//        return out;
//    if(colors[baseIndex + 4] > positional.rightX)
//        return out;
//    if(colors[baseIndex + 5] < positional.upperY)
//        return out;
//    if(colors[baseIndex + 5] > positional.lowerY)
//        return out;
//    if(colors[baseIndex + 6] < positional.nearZ)
//        return out;
//    if(colors[baseIndex + 6] > positional.farZ)
//        return out;

    float3 pos = float3(vertex_array[vid][0] * colors[baseIndex + 7] + colors[baseIndex + 4] - positional.widthModel,
                        vertex_array[vid][1] * colors[baseIndex + 7] + colors[baseIndex + 5] - positional.heightModel,
                        vertex_array[vid][2] * colors[baseIndex + 7] + colors[baseIndex + 6] - positional.halfTotalThickness);
    
    
    out.position = uniforms.premultipliedMatrix * float4(pos, 1);
    out.color = float4(colors[baseIndex + 1], colors[baseIndex + 2], colors[baseIndex + 3], colors[baseIndex]);
    out.normal = (uniforms.modelViewMatrix * float4(normals[vid], 1)).xyz;
    return out;    
}

constant unsigned int cum[] = {405, 567, 729, 891, 1053, 1215, 1377, 1539, 1701, 1944};

vertex VertexOut stripedSphereVertexShader(
                                    const device packed_float3* vertex_array [[ buffer(0) ]],
                                    constant Constants & uniforms [[ buffer(1) ]],
                                    constant PositionalData & positional [[ buffer(2) ]],
                                    const device float * colors [[ buffer(3) ]],
                                    const device packed_float3* normals [[ buffer(4) ]],
                                    unsigned int vid [[ vertex_id ]],
                                    unsigned int iid [[ instance_id ]]) {
    
    VertexOut out;
    //unsigned int cum [] = {405, 567, 729, 891, 1053, 1215, 1377, 1539, 1701, 1944};
    unsigned int segment = 0;
    for(int a = 0; a < 10; a++)
        if(vid >= cum[a])
            segment = a + 1;
    
    int stripes = (positional.stride - 4)/4;
    int color = 1;
    
    if(stripes == 1){
        int pick[] = {0,0,0,0,0,0,0,0,0,0,};
        color += pick[segment];
    }
    if(stripes == 2){
        int pick[] = {0,0,1,1,1,1,1,1,0,0};
        color += pick[segment];
    }
    if(stripes == 3){
        int pick[] = {0,0,0,1,1,1,1,2,2,2};
        color += pick[segment];
    }
    if(stripes == 4){
        int pick[] = {0,0,1,1,1,2,2,2,3,3};
        color += pick[segment];
    }
    if(stripes == 5){
        int pick[] = {0,0,1,1,2,2,3,3,4,4};
        color += pick[segment];
    }
    if(stripes == 6){
        int pick[] = {0,1,1,2,2,3,3,4,4,5};
        color += pick[segment];
    }
    if(stripes == 7){
        int pick[] = {0,0,1,2,3,3,4,5,6,6};
        color += pick[segment];
    }
    if(stripes == 8){
        int pick[] = {0,0,1,2,3,4,5,6,7,7};
        color += pick[segment];
    }
    if(stripes == 9){
        int pick[] = {0,1,2,3,4,5,6,7,8,8};
        color += pick[segment];
    }
    if(stripes == 10){
        int pick[] = {0,1,2,3,4,5,6,7,8,9};
        color += pick[segment];
    }
    
    unsigned int baseIndex = iid * (positional.stride);
    
    float3 pos = float3(vertex_array[vid][0] * colors[baseIndex + 3] + colors[baseIndex + 0] - positional.widthModel,
                        vertex_array[vid][1] * colors[baseIndex + 3] + colors[baseIndex + 1] - positional.heightModel,
                        vertex_array[vid][2] * colors[baseIndex + 3] + colors[baseIndex + 2] - positional.halfTotalThickness);
    
    
    out.position = uniforms.premultipliedMatrix * float4(pos, 1);
    out.color = float4(colors[baseIndex + 4 * color + 1], colors[baseIndex + 4 * color + 2], colors[baseIndex + 4 * color + 3], 1);
    out.normal = (uniforms.modelViewMatrix * float4(normals[vid], 1)).xyz;
    return out;    
}

fragment float4 sphereFragmentShader(const VertexOut interpolated [[ stage_in ]]){
    float3 rgbCol = interpolated.color.rgb;
    float3 ambientTerm = light.ambientColor * rgbCol;
    
    float3 normal = normalize(interpolated.normal);
    float diffuseIntensity = saturate(dot(normal, light.direction));
    float3 diffuseTerm = light.diffuseColor * float3(interpolated.color.rgb) * diffuseIntensity;
    
    return float4(ambientTerm + diffuseTerm, interpolated.color.a);
    
    return interpolated.color;
}

//From Back
#define NUM_QUADS 1000.0

struct VertexOutBack{
    float4 position [[ position ]];
    float4 samplerPosition;
};

vertex VertexOutBack vertexShaderBack(
                                      const device packed_float3* vertex_array [[ buffer(2) ]],
                                      constant Constants & uniforms [[ buffer(1) ]],
                                      constant PositionalData & positional [[ buffer(0) ]],
                                      unsigned int vid [[ vertex_id ]],
                                      unsigned int iid [[ instance_id ]]) {
    
    VertexOutBack out;

    float maximumSide = max(positional.widthModel, positional.heightModel);
    maximumSide = max(maximumSide, positional.halfTotalThickness * 2);
    maximumSide *= 1.74;//1.732 is sqrt(3). This makes sure that the rotated model fits within the cube always
    
    float step_ = 1.74/NUM_QUADS;
    float3 pos = float3(vertex_array[vid][0] , vertex_array[vid][1], vertex_array[vid][2] - 0.87 + iid * step_);
    out.samplerPosition = uniforms.modelViewMatrix * float4(pos, 1);
    pos = float3(vertex_array[vid][0] * maximumSide , vertex_array[vid][1] * maximumSide, (vertex_array[vid][2] - 0.87 + iid * step_) * maximumSide);
    out.position = uniforms.projectionMatrix * uniforms.baseModelMatrix * float4(pos, 1);

    return out;
}

fragment float4 fragmentShaderBack(const VertexOutBack interpolated [[ stage_in ]],
                                  const device char * colors [[ buffer(0) ]],
                                  constant PositionalData & positional [[ buffer(1) ]],
                                  const device float * reverseDepths [[ buffer(2) ]]
                                  ){
    
    float x = interpolated.samplerPosition.x;
    float y = interpolated.samplerPosition.y;
    float z = interpolated.samplerPosition.z;
    
    if(x < -0.5 || x > 0.5 || y < -0.5 || y > 0.5 || z <= -0.5 || z >= 0.5){
        discard_fragment();
    }else{
        int ix = (int)round((x + 0.5) * positional.widthModel);
        int iy = (int)round((y + 0.5) * positional.heightModel);
        int iz = (int)round((z + 0.5) * (NUM_QUADS - 1));
        
        if(reverseDepths[iz] == -1.0){
            discard_fragment();
        }else{
            unsigned index = (reverseDepths[iz] * positional.areaModel + iy * positional.widthModel + ix) * 4;
            char a = colors[index];
            if(a == 0){
                discard_fragment();
            }else{
                char r = colors[index + 1];
                char g = colors[index + 2];
                char b = colors[index + 3];
                return float4(r/255.0, g/255.0, b/255.0, a/255);
            }
        }
    }
    return float4(0.0);
}

//Polygonized
//struct Material
//{
//    float3 ambientColor;
//    float3 diffuseColor;
//    float3 specularColor;
//    half specularPower;
//};
//
//constant Material material = {
//    .ambientColor = { 0.9, 0.1, 0 },
//    .diffuseColor = { 0.9, 0.1, 0 },
//    .specularColor = { 1, 1, 1 },
//    .specularPower = 100
//};

vertex VertexOut vertexShaderPolygonized(
                                      const device packed_float3 * vertex_array [[ buffer(0) ]],
                                      const device unsigned * indexes [[ buffer(1) ]],
                                      constant Constants & uniforms [[ buffer(2) ]],
                                      constant PositionalData & positional [[ buffer(3) ]],
                                      const device unsigned * cellId [[ buffer(4) ]],
                                      const device packed_float4 * colors [[ buffer(5) ]],
                                      const device packed_float3 * centroids [[ buffer(6) ]],
                                      const device packed_float3 * normals [[ buffer(7) ]],
                                      unsigned int vid [[ vertex_id ]]) {

    VertexOut out;
    unsigned cell = cellId[vid/3];
    packed_float3 vert = vertex_array[indexes[vid]];
    float3 centroid = centroids[cell];
    float3 recentered = vert;
    float factor = (positional.stride/100.0);
    recentered *= factor;
    recentered += centroid;
    float3 pos = float3(recentered[0], recentered[1], recentered[2]);
    out.position = uniforms.premultipliedMatrix * float4(pos, 1);
    float3 normal = normals[indexes[vid]];
    out.normal = (uniforms.modelViewMatrix * float4(normal, 1)).xyz;
    out.color = colors[cell];

    return out;
}

fragment float4 fragmentShaderPolygonized(const VertexOut interpolated [[ stage_in ]]){
    if(interpolated.color.a == 0.0f)
        discard_fragment();
    
    float3 rgbCol = interpolated.color.rgb;
    float3 ambientTerm = light.ambientColor * rgbCol;
    
    float3 normal = normalize(interpolated.normal);
    float diffuseIntensity = saturate(dot(normal, light.direction));
    float3 diffuseTerm = light.diffuseColor * float3(interpolated.color.rgb) * diffuseIntensity;
    
//    float3 specularTerm(0);
//    if (diffuseIntensity > 0)
//    {
//        float3 eyeDirection = normalize(interpolated.eye);
//        float3 halfway = normalize(light.direction + eyeDirection);
//        float specularFactor = pow(saturate(dot(normal, halfway)), material.specularPower);
//        specularTerm = light.specularColor * material.specularColor * specularFactor;
//    }
    
//    return float4(ambientTerm + diffuseTerm + specularTerm, 1);
//    return float4(normal[2]/2 + 0.5,0,0,1.0);
    return float4(ambientTerm + diffuseTerm, 1);
    
//    return interpolated.color;
}
