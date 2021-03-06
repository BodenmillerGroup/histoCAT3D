//
//  IMCMetalViewAndRenderer.m
//  3DIMC
//
//  Created by Raul Catena on 9/5/17.
//  Copyright © 2017 CatApps. All rights reserved.
//

#import "IMCMetalViewAndRenderer.h"
#import <Metal/Metal.h>
#import <QuartzCore/QuartzCore.h>
#import "Matrix4.h"
#import "IMCMtkView.h"

@interface IMCMetalViewAndRenderer(){
    NSInteger voxelsToRenderCounter;
}

@property (strong, nonatomic) NSIndexSet *slicesObtained;
@property (assign, nonatomic) NSInteger renderWidth;
@property (assign, nonatomic) NSInteger renderHeight;
@property (assign, nonatomic) NSInteger slices;

@end

//typedef struct{
//    float x, y, z, w;
//} Vertex;

#define A -0.5, 0.5, 0.5
#define B -0.5, -0.5, 0.5
#define C 0.5, -0.5, 0.5
#define D 0.5, 0.5, 0.5

#define Q -0.5, 0.5, -0.5
#define R 0.5,  0.5, -0.5
#define S -0.5, -0.5, -0.5
#define T 0.5, -0.5, -0.5

float cubeVertexData[] = {
    
    A,B,C ,A,C,D,   //Front
    R,T,S ,R,S,Q,   //Back
    
    Q,S,B ,Q,B,A,   //Left
    D,C,T ,D,T,R,   //Right
    
    Q,A,D ,Q,D,R,   //Top
    B,S,T ,B,T,C    //Bot
};

bool heightDescriptor[] = {
    false,false,false ,false,false,false,   //Front
    true,true,true ,true,true,true,   //Back
    
    true,true,false ,true,false,false,   //Left
    false,false,true ,false,true,true,   //Right
    
    true,false,false, true,false,true,   //Top
    false,true,true,false,true,false    //Bot
};

//Lower are B,C,S,T


@implementation IMCMetalViewAndRenderer


-(instancetype)init{
    self = [super init];
    if(self){

        [self createMetalStack];
    }
    return self;
}


-(void)bakeData{

}

-(NSColor *)backGroundColor{
    return [[self.delegate backgroundColor]colorUsingColorSpace:[NSColorSpace sRGBColorSpace]];
}

-(void)projectionMatrixSetup:(MTKView *)view{
    float aspect = fabs(view.bounds.size.width / view.bounds.size.height);
    projectionMatrix = [Matrix4 makePerspectiveViewAngle:[Matrix4 degreesToRad:65.0] aspectRatio:aspect nearZ:0.01 farZ:5000];
}

-(BOOL)checkNeedsUpdate{
    __block BOOL update = NO;
    
    //Check Indexes
    NSArray *currentIndexes = [self.delegate inOrderIndexes].copy;
    if(self.indexesObtained.count != currentIndexes.count)
        update = YES;
    
    else
        for (NSInteger i = 0; i < self.indexesObtained.count; i++)
            if([self.indexesObtained[i] integerValue] != [currentIndexes[i] integerValue])
                update = YES;
    
    //Check colors
    NSArray * currentColors = [self.delegate colors];
    
    if(self.colorsObtained.count != currentColors.count)
        update = YES;
    
    else
        for (NSInteger i = 0; i < self.colorsObtained.count; i++){
    
            NSColor *a = self.colorsObtained[i];
            NSColor *b = currentColors[i];
            
            a = [a colorUsingColorSpace:[NSColorSpace sRGBColorSpace]];
            b = [b colorUsingColorSpace:[NSColorSpace sRGBColorSpace]];
            if(!CGColorEqualToColor(a.CGColor, b.CGColor))
                update = YES;
    
        }
    
    
    
    //Layers
    NSIndexSet *currentStacks = [self.delegate stacksIndexSet].copy;
    if(self.slicesObtained.count != currentStacks.count)
        update = YES;
    
    else
        [currentStacks enumerateIndexesUsingBlock:^(NSUInteger idx, BOOL *stop){
            if(![self.slicesObtained containsIndex:idx])
                update = YES;
        }];

    if(update == YES){
        self.colorsObtained = currentColors;
        self.indexesObtained = currentIndexes;
        self.slicesObtained = currentStacks;
    }
    
    return update;
}

-(void)syntheticCubes{
    float vals[] ={
        1.0f, 1.0f, 0.0f, 0.0f, -1.0f, -1.0f, -1.0f,
        1.0f, 0.0f, 1.0f, 0.0f, -1.0f, 1.0f, -1.0f,
        1.0f, 0.0f, 0.0f, 1.0f, 1.0f, -1.0f, -1.0f,
        1.0f, 0.0f, 1.0f, 1.0f, 1.0f, 1.0f, -1.0f,
        
        1.0f, 1.0f, 0.0f, 1.0f, -1.0f, -1.0f, 1.0f,
        1.0f, 1.0f, 1.0f, 0.0f, -1.0f, 1.0f, 1.0f,
        1.0f, 1.0f, 1.0f, 1.0f, 1.0f, -1.0f, 1.0f,
        0.0f, 0.0f, 0.0f, 0.0f, 1.0f, 1.0f, 1.0f
    };
    
    self.colorBuffer = [self.device newBufferWithBytes:vals length: 8 * 7 * sizeof(float) options:MTLResourceOptionCPUCacheModeDefault];
}

-(NSArray *)onlyExternals:(NSIndexSet *)indexSet inArrangedArray:(NSArray *)idx{
    NSMutableArray *res = @[].mutableCopy;
    
    for (NSArray *arr in idx)
        for (NSNumber *num in arr)
            if([indexSet containsIndex:num.integerValue]){
                [res addObject:@([idx indexOfObject:arr])];
                break;
            }
    return res;
}

-(void)updateColorBufferWithWidth:(NSInteger)width height:(NSInteger)height{
    
//    [self syntheticCubes];
//    return;
    voxelsToRenderCounter = 0;
    
    UInt8 *** data = [self.delegate threeDData];
    float * zPositions = [self.delegate zValues];
    float * zThicknesses = [self.delegate thicknesses];
    NSIndexSet *slices = [self.delegate stacksIndexSet];
    NSArray *arranged = [self.delegate inOrderIndexesArranged];
    NSArray *externals = [self onlyExternals:slices inArrangedArray:arranged];
    
    if(data && zPositions && zThicknesses){
        NSInteger area = width * height;
        CGRect rectToRender = [self.delegate rectToRender];
        AlphaMode alphaMode = [self.delegate alphaMode];
        self.slices = slices.count;
        int stride = 8;
        
        bool * mask = [self.delegate showMask];
        NSInteger ascertainWidth = 0;
        NSInteger firstToProcess = 0;
        for (NSInteger i = 0; i < area; i++) {
            if(mask[i] == true){
                firstToProcess = i;
                while (mask[i] == true) {
                    ascertainWidth++;
                    i++;
                }
                break;
            }
        }
        self.renderWidth = ascertainWidth;
        self.renderHeight = (NSInteger)round((fabs(rectToRender.size.height) * height));
        NSInteger renderableArea = self.renderWidth * self.renderHeight;
        NSInteger last = MIN(_renderHeight * width + firstToProcess, area);

        float * buff = calloc(renderableArea * slices.count * stride, sizeof(float));//Color components and positions
        
        if(buff){
            __block NSInteger x , y, cursor = 0;
            __block float  z = 0.0f, thickness = 0.0f;
            
            self.colorsObtained = [self.delegate colors];
            float minThresholdForAlpha = [self.delegate combinedAlpha];
            
            float * colors = (float *)malloc(self.colorsObtained.count * 3 * sizeof(float));
            
            for (int i = 0; i< self.colorsObtained.count; i++) {
                NSColor *colorObj = [self.colorsObtained objectAtIndex:i];
                colorObj = [colorObj colorUsingColorSpace:[NSColorSpace sRGBColorSpace]];
                colors[i * 3] = colorObj.redComponent/255.0f;
                colors[i * 3 + 1] = colorObj.greenComponent/255.0f;
                colors[i * 3 + 2] = colorObj.blueComponent/255.0f;
            }
            NSInteger numColors = self.colorsObtained.count;
            
            NSInteger realIndexesCount = self.indexesObtained.count;
            NSInteger realIndexes[realIndexesCount];
            for (NSInteger i = 0; i < self.indexesObtained.count; i++)
                realIndexes[i] = [self.indexesObtained[i]integerValue];
            
            
            
            for (NSNumber *num in externals) {
                NSInteger corresponding = num.integerValue;
                UInt8 ** sliceData = data[corresponding];
                if(sliceData){
                    x = 0;
                    y = 0;
                    z = zPositions[[[arranged[corresponding]firstObject]integerValue]];
                    thickness = zThicknesses[[[arranged[corresponding]firstObject]integerValue]];
                    UInt8 *chanData = NULL;
                    
                    for (NSInteger idx = 0; idx < realIndexesCount; idx++) {
                        NSInteger realIndex = realIndexes[idx];
                        
                        chanData = sliceData[realIndex];
                        if(chanData){
                            NSInteger internalCursor = 0;

                            for (NSInteger pix = firstToProcess; pix < last; pix++) {
                                
                                if(mask[pix] == false)
                                    continue;
                                
                                NSInteger internalStride = internalCursor * stride;
                                internalStride += cursor;
                                
                                if(numColors > 0){
                                    buff[internalStride + 1] += chanData[pix] * colors[idx * 3];
                                    buff[internalStride + 2] += chanData[pix] * colors[idx * 3 + 1];
                                    buff[internalStride + 3] += chanData[pix] * colors[idx * 3 + 2];
                                }else{
                                    RgbColor rgb = RgbFromFloatUnit(chanData[pix]/255.0f);
                                    buff[internalStride + 1] += rgb.r/255.0f;
                                    buff[internalStride + 2] += rgb.g/255.0f;
                                    buff[internalStride + 3] += rgb.b/255.0f;
                                }
                                buff[internalStride + 4] = internalCursor % _renderWidth;
                                buff[internalStride + 5] = internalCursor /_renderWidth;
                                buff[internalStride + 6] = z;
                                buff[internalStride + 7] = thickness;
                                
                                //Filters
                                float max = .0f;
                                float sum = .0f;
                                for (int i = 1; i < 4; i++){
                                    float val = buff[internalStride + i];
                                    if(val > max)
                                        max = val;
                                    sum += val;
                                    if(sum > 1.0f)
                                        break;
                                }
                                if(sum > 1.0f)sum = 1.0f;
                                
                                if(alphaMode == ALPHA_MODE_OPAQUE)
                                    buff[internalStride] = max < minThresholdForAlpha ? 0.0f : 1.0f;
                                else if(alphaMode == ALPHA_MODE_FIXED)
                                    buff[internalStride] = max < minThresholdForAlpha ? 0.0f : minThresholdForAlpha;//Alpha
                                else if(alphaMode == ALPHA_MODE_ADAPTIVE)
                                    buff[internalStride] = max < minThresholdForAlpha ? 0.0f : sum;//MIN(1.0f, sum);//Alpha
                                
                                internalCursor++;
                            }
                        }
                    }
                }
                cursor += renderableArea * stride;
            }

            NSInteger bufferSize = renderableArea * slices.count * stride;
            float * cleanBuffer = malloc(bufferSize * sizeof(float));
            
            //Inspect buried voxels
            [self applyBoost:renderableArea width:_renderWidth buffer:buff auxBuffer:cleanBuffer stride:stride bufferSize:bufferSize];
            
            //Remove all Zeroes
            NSInteger cleanIndex = 0;
            for (NSInteger m = 0; m < bufferSize; m+=stride) {
                if(buff[m] > 0){
                    for (NSInteger n = 0; n < stride; n++) {
                        cleanBuffer[cleanIndex + n] = buff[m + n];
                    }
                    cleanIndex += stride;
                }
            }
            voxelsToRenderCounter = cleanIndex/stride;
            if((cleanIndex + stride) * sizeof(float) < 1024000000)
                self.colorBuffer = [self.device newBufferWithBytes:cleanBuffer length:(cleanIndex + stride) * sizeof(float) options:MTLResourceOptionCPUCacheModeDefault];
            else
                self.colorBuffer = nil;
            
            NSLog(@"-%li", voxelsToRenderCounter);
            
            free(buff);
            free(cleanBuffer);
            free(colors);
        }
    }
}

-(void)applyBoost:(NSInteger)renderableArea width:(NSInteger)width buffer:(float *)buff auxBuffer:(float *)cleanBuffer stride:(int)stride bufferSize:(NSInteger)bufferSize{
    NSInteger rws = _renderWidth * stride;
    NSInteger ras = renderableArea * stride;
    NSInteger removed = 0;
    NSInteger from = 0;
    NSInteger boost = [self.delegate boostModeCode];
    if(boost > 0){
        if(boost > 1)
            boost += 13;//Index 2 is 15 kernel
        else if(boost == 1)
            boost = 6;
        
        for (NSInteger m = 0; m < bufferSize; m+=stride) {
            if(buff[m] > 0){
                NSInteger mod = (m/stride)%_renderWidth;
                NSInteger modB = ((m/stride)%renderableArea)/_renderWidth;
                NSInteger modC = m / (renderableArea * stride);
                
                if(mod == 0 ||
                   mod == _renderWidth - 1 ||
                   modB == 0 ||
                   modB == _renderHeight - 1 ||
                   modC == 0 ||
                   m < ras ||
                   m > bufferSize - ras
                   ){
                    cleanBuffer[m] = 1.0f;
                    from++;
                    continue;
                }
                
                NSInteger count = 0;
                if(boost > 6){
                    
                    for (int z = -1; z < 2; z++){
                        if(count >= boost)
                            break;
                        for (int a = -1; a < 2; a++)
                            for (int b = -1; b < 2; b++) {
                                NSInteger idx = m + z * ras + a * rws + b * stride;
                                if(idx >= 0 && idx < bufferSize && idx != m)
                                    if(buff[idx] > 0)
                                        count++;
                                
                            }
                    }
                    
                    cleanBuffer[m] = count >= boost ? .0f : 1.0f;
                    if(count >= boost)removed++;
                    from++;
                    
                }else{
                    BOOL include = NO;
                    for (int z = 0; z < 6; z++) {
                        int notHit = 0;
                        for (int r = 1; r < 4; r++) {
                            NSInteger idx = m;
                            switch (z) {
                                case 0:
                                    idx += r * ras;
                                    break;
                                case 1:
                                    idx -= r * ras;
                                    break;
                                case 2:
                                    idx += r * rws;
                                    break;
                                case 3:
                                    idx -= r * rws;
                                    break;
                                case 4:
                                    idx += r * stride;
                                    break;
                                case 5:
                                    idx -= r * stride;
                                    break;
                                default:
                                    break;
                            }
                            if(idx >= 0 && idx < bufferSize && idx != m)
                                if(buff[idx] == 0)
                                    notHit++;
                            if(idx < 0 && idx > bufferSize)
                                notHit++;
                        }
                        if(notHit == 3){
                            include = YES;
                            break;
                        }
                    }
                    cleanBuffer[m] = include ? 1.0f : 0.0f;
                    if(!include)removed++;
                    from++;
                }
            }
        }

        for (NSInteger m = 0; m < bufferSize; m+=stride)
            if(cleanBuffer[m] == .0f)
                buff[m] = .0f;
        NSLog(@"Removed %li from %li", removed, from);
    }
    
}


-(void)drawInMTKView:(IMCMtkView *)view{
    view.framebufferOnly = NO;
    if(view.refresh == NO && !self.forceColorBufferRecalculation)
        return;

    view.refresh = NO;
    
    if(!self.device){
        self.device = view.device;
        [self createMetalStack];
    }
    //Projection Matrix
    [self projectionMatrixSetup:view];
    
    //Uniforms
    Constants uniforms;
    
    uniforms.modelViewMatrix = view.rotationMatrix->glkMatrix;
    uniforms.baseModelMatrix = view.baseModelMatrix->glkMatrix;
    uniforms.projectionMatrix = projectionMatrix->glkMatrix;
    GLKMatrix4 premultiplied = GLKMatrix4Multiply(uniforms.baseModelMatrix, uniforms.modelViewMatrix);
    uniforms.premultipliedMatrix = GLKMatrix4Multiply(uniforms.projectionMatrix, premultiplied);
    
    self.uniformsBuffer = [self.device newBufferWithBytes:&uniforms length:sizeof(uniforms) options:MTLResourceOptionCPUCacheModeDefault];
    
    //Size model
    NSInteger width = [self.delegate witdhModel];
    NSInteger height = [self.delegate heightModel];
    NSInteger areaModel = width * height;
    
    //Positional Data
    
    PositionalData positional;
    positional.lowerY = view.lowerYOffset * height;
    positional.upperY = view.upperYOffset * height;
    positional.leftX = view.leftXOffset * width;
    positional.rightX = view.rightXOffset * width;
    positional.halfTotalThickness = [self.delegate zValues][self.delegate.stacksIndexSet.lastIndex]/2;
    positional.nearZ = view.nearZOffset * positional.halfTotalThickness * 2;
    positional.farZ = view.farZOffset * positional.halfTotalThickness * 2;
    positional.widthModel = (uint)self.renderWidth;
    positional.heightModel = (uint)self.renderHeight;
    positional.totalLayers = (uint)self.slices;
    positional.areaModel = (uint)(self.renderWidth * self.renderHeight);
    positional.stride = 1;
    
    self.positionalBuffer = [self.device newBufferWithBytes:&positional length:sizeof(positional) options:MTLResourceOptionCPUCacheModeDefault];
    
    //prepareData
    if([self checkNeedsUpdate] || self.forceColorBufferRecalculation)
        [self updateColorBufferWithWidth:width height:height];
    self.forceColorBufferRecalculation = NO;
    if(!self.colorBuffer)
        return;
    
    //Mask //TODO. Not do everytime
    bool * mask = [self.delegate showMask];
    if(mask)
        self.maskBuffer = [self.device newBufferWithBytes:mask length:areaModel options:MTLResourceOptionCPUCacheModeDefault];//cpuCacheModeWriteCombined
    else
        return;
    
    //Get drawable
    id<CAMetalDrawable> drawable = [view currentDrawable];
    if(!drawable)
        return;
    
    view.depthStencilPixelFormat = MTLPixelFormatDepth32Float;
    
    //Create a render pass descriptor
    MTLRenderPassDescriptor * rpd = view.currentRenderPassDescriptor;//[MTLRenderPassDescriptor new];
    if(!rpd)
        return;
    
    id<MTLTexture> text = [drawable texture];
    rpd.colorAttachments[0].texture = drawable.texture;
    rpd.colorAttachments[0].loadAction = MTLLoadActionClear;
    NSColor *bg = [self backGroundColor];
    rpd.colorAttachments[0].clearColor = MTLClearColorMake(bg.redComponent, bg.greenComponent, bg.blueComponent, bg.alphaComponent);
    rpd.colorAttachments[0].storeAction = MTLStoreActionStore;
    
    
    //Create a command Buffer
    id<MTLCommandBuffer> comBuffer = [self.commandQueue commandBuffer];
    
    //Create encoder for command buffer
    id<MTLRenderCommandEncoder> renderEncoder = [comBuffer renderCommandEncoderWithDescriptor:rpd];
    [renderEncoder setRenderPipelineState:self.pipelineState];
    
    [renderEncoder setVertexBuffer:self.vertexBuffer offset:0 atIndex:0];
    [renderEncoder setVertexBuffer:self.uniformsBuffer offset:0 atIndex:1];
    [renderEncoder setVertexBuffer:self.positionalBuffer offset:0 atIndex:2];
    [renderEncoder setVertexBuffer:self.maskBuffer offset:0 atIndex:3];
    //[renderEncoder setVertexBuffer:self.layerIndexesBuffer offset:0 atIndex:4];
    [renderEncoder setVertexBuffer:self.colorBuffer offset:0 atIndex:4];
    [renderEncoder setVertexBuffer:self.heightDescriptor offset:0 atIndex:5];

    AlphaMode alphaMode = [self.delegate alphaMode];
    if(alphaMode == ALPHA_MODE_OPAQUE)
        [renderEncoder setDepthStencilState:self.stencilState];
    [renderEncoder setFrontFacingWinding:MTLWindingCounterClockwise];
    [renderEncoder setCullMode:  MTLCullModeNone ];
    
    //[renderEncoder drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:sizeof(cubeVertexData)];
    //[renderEncoder drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:36 instanceCount:self.renderWidth * self.renderHeight * self.slices];//8 for synthetic
    if(voxelsToRenderCounter > 0)
        [renderEncoder drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:36 instanceCount:voxelsToRenderCounter];//8 for synthetic
    
    [renderEncoder endEncoding];
    
    [comBuffer addCompletedHandler:^(id<MTLCommandBuffer> buffer){
        //view.refresh = NO;
        view.lastRenderedTexture = text;
    }];
    
    //Commit
    [comBuffer presentDrawable:drawable];
    [comBuffer commit];
}
-(void)mtkView:(MTKView *)view drawableSizeWillChange:(CGSize)size{
    [self projectionMatrixSetup:view];
}

-(void)createMetalStack{
    //Create layer. Removed since introduced MetalKit
    //_metalLayer = [[CAMetalLayer alloc]init];
    //_metalLayer.device = self.device;
    //_metalLayer.pixelFormat = MTLPixelFormatBGRA8Unorm;
    //_metalLayer.framebufferOnly = YES;
    //_metalLayer.frame = self.bounds;
    //[_layer addSublayer:_metalLayer];
    
    //Add VD for cube
    NSInteger dataSize = sizeof(cubeVertexData);
    self.vertexBuffer = [self.device newBufferWithBytes:cubeVertexData length:dataSize options:MTLResourceOptionCPUCacheModeDefault];
    NSInteger dataSizeHeightDescriptor = sizeof(heightDescriptor);
    self.heightDescriptor = [self.device newBufferWithBytes:heightDescriptor length:dataSizeHeightDescriptor options:MTLResourceOptionCPUCacheModeDefault];
    //Create pipeline state
    id<MTLLibrary> defaultLibrary = [self.device newDefaultLibrary];
    id<MTLFunction> vertexProgram = [defaultLibrary newFunctionWithName:@"vertexShader"];
    id<MTLFunction> fragmentProgram = [defaultLibrary newFunctionWithName:@"fragmentShader"];
    
    MTLRenderPipelineDescriptor * pipelineDescriptor = [MTLRenderPipelineDescriptor new];
    pipelineDescriptor.vertexFunction = vertexProgram;
    pipelineDescriptor.fragmentFunction = fragmentProgram;
    pipelineDescriptor.depthAttachmentPixelFormat = MTLPixelFormatDepth32Float;
    pipelineDescriptor.colorAttachments[0].blendingEnabled = YES;
    
    pipelineDescriptor.colorAttachments[0].rgbBlendOperation = MTLBlendOperationAdd;
    pipelineDescriptor.colorAttachments[0].alphaBlendOperation = MTLBlendOperationAdd;
    //pipelineDescriptor.colorAttachments[0].sourceRGBBlendFactor = MTLBlendFactorSourceAlpha;
    //pipelineDescriptor.colorAttachments[0].sourceAlphaBlendFactor = MTLBlendFactorSourceAlpha;
    pipelineDescriptor.colorAttachments[0].destinationRGBBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
    pipelineDescriptor.colorAttachments[0].destinationAlphaBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
    
    pipelineDescriptor.colorAttachments[0].pixelFormat = MTLPixelFormatBGRA8Unorm; ////// Kontuz. Must coincide with CAMetalLayer
    
    //Expensive. Do least possible
    NSError *error;
    _pipelineState = [self.device newRenderPipelineStateWithDescriptor:pipelineDescriptor error:&error];
    if(error)
        NSLog(@"Some error %@ %@", error, error.localizedDescription);
    
    _commandQueue = [self.device newCommandQueue];
    
    //Stencil
    MTLDepthStencilDescriptor * desc = [MTLDepthStencilDescriptor new];
    desc.depthCompareFunction = MTLCompareFunctionLess;
    desc.depthWriteEnabled = YES;
    self.stencilState = [self.device newDepthStencilStateWithDescriptor:desc];
}


-(void)addLabelsOverlayed:(IMCMtkView *)view{
    
    if([[self.delegate legends]state] == NSControlStateValueOn){
        NSArray *colorsObtained = [self.delegate colors];
        NSArray *channsObtained = [self.delegate channelsForCell];
        NSArray *indexesObtained = [self.delegate inOrderIndexes];
        CGFloat width = view.bounds.size.width;
        float sizeLabels = [self.delegate sizeLabels];
        CGFloat heigthLabel = sizeLabels + 5.0f;
        
        if(colorsObtained.count == indexesObtained.count || colorsObtained.count == 0){
            int index = 0;
            for (NSNumber *chann in indexesObtained) {
                NSTextField *field = index < view.labels.count ? view.labels[index] : [[NSTextField alloc]initWithFrame:CGRectZero];
                if(![view.labels containsObject:field]){
                    [view.labels addObject:field];
                    [view addSubview:field];
                }
                NSString * str = channsObtained[MIN(channsObtained.count - 1, labs(chann.integerValue))];
                if(str){
                    field.frame = NSMakeRect(10.0f, heigthLabel * index, width, heigthLabel);
                    field.textColor = colorsObtained.count == 0 ? [NSColor whiteColor] : colorsObtained[MAX(0, MIN(index, colorsObtained.count - 1))];
                    field.backgroundColor = [NSColor clearColor];
                    field.font = [NSFont systemFontOfSize:sizeLabels];
                    field.bordered = NO;
                    field.selectable = NO;
                    field.editable = NO;
                    [field setStringValue:str];
                    index++;
                }
            }
            for (NSInteger i = index; i < view.labels.count; i++) {
                [(NSView *)view.labels[i] setFrame:CGRectZero];
            }
        }
    }
    else
        for (NSTextField *f in view.labels)
            f.frame = CGRectZero;
}

@end
