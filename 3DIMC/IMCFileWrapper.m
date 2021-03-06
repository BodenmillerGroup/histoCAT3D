//
//  IMCFileWrapper.m
//  3DIMC
//
//  Created by Raul Catena on 1/19/17.
//  Copyright © 2017 University of Zürich. All rights reserved.
//

#import "IMCFileWrapper.h"
#import "IMC_TxtLoader.h"
#import "IMC_MatlabLoader.h"
#import "IMCFileExporter.h"
#import "IMC_BIMCLoader.h"
#import "IMC_MCDLoader.h"
#import "IMC_TIFFLoader.h"

//TODO. Generate absolute path from relative and data coordinator in case the folder has been moved

@implementation IMCFileWrapper


-(NSString *)itemName{
    NSString *prefix = @"";
    if(self.hasChanges)prefix = @"Unsaved * ";
    return [prefix stringByAppendingString:self.fileName?self.fileName:@""];
}
-(NSString *)itemSubName{
    return self.relativePath;
}

#pragma mark paths

-(void)loadFileWithBlock:(void(^)(void))block{
    if(![self isLoaded]){
        dispatch_queue_t queue = dispatch_queue_create([IMCUtils randomStringOfLength:5].UTF8String, NULL);
        dispatch_async(queue, ^{
            [self loadLayerDataWithBlock:block];
        });
    }
}
-(void)loadOrUnloadFileWithBlock:(void(^)(void))block{
    if(![self isLoaded]){
        dispatch_queue_t queue = dispatch_queue_create([IMCUtils randomStringOfLength:5].UTF8String, NULL);
        dispatch_async(queue, ^{
            [self loadLayerDataWithBlock:block];
        });
    }else{
        [self unLoadLayerDataWithBlock:block];
    }
}

-(NSString *)baseDirectoryPath{
    return self.pathMainDoc.stringByDeletingLastPathComponent;
}

-(NSString *)workingFolder{
    NSString *relPath = [[self relativePath]stringByDeletingPathExtension];
    NSString *docPath = [self.pathMainDoc stringByDeletingLastPathComponent];
    return [[docPath stringByAppendingString:relPath] stringByAppendingString:@"_wd"];
}

-(NSString *)workingFolderRealative{
    NSString *relPath = [[self relativePath]stringByDeletingPathExtension];
    return [relPath stringByAppendingString:@"_wd"];
}

-(void)checkAndCreateWorkingFolder{
    [General checkAndCreateDirectory:[self workingFolder]];
}

#pragma mark more

-(NSArray *)allStacks{
    NSMutableArray *arr = @[].mutableCopy;
    for (IMCPanoramaWrapper *pan in self.children)
        for(IMCImageStack *stck in pan.children)
            [arr addObject:stck];
    return arr;
}

-(void)save{
    for(IMCImageStack *stck in [self allStacks]){
        if([stck hasTIFFBackstore]){
            [stck saveTIFFAtPath:[stck backStoreTIFFPath]];
            continue;
        }
        if([self.fileType isEqualToString:EXTENSION_BIMC])[stck saveBIMCAtPath:self.absolutePath];
        if([self.fileType hasPrefix:EXTENSION_TIFF_PREFIX])[stck saveTIFFAtPath:self.absolutePath];
    }
}

-(NSMutableArray *)containers{
    if(![self.jsonDictionary valueForKey:JSON_DICT_FILE_CONTAINERS])
        [self.jsonDictionary setValue:@[].mutableCopy forKey:JSON_DICT_FILE_CONTAINERS];
    
    return [self.jsonDictionary valueForKey:JSON_DICT_FILE_CONTAINERS];
}

#pragma mark loading

-(BOOL)isSoftLoaded{
    return [[self.jsonDictionary valueForKey:JSON_DICT_FILE_IS_SOFT_LOADED]boolValue];
}

-(void)populateJsonDictForSingleImageFile:(NSString *)path success:(BOOL *)success{
    IMCImageStack * imageStack;
    NSLog(@"1");
    if (self.children.count == 0) {
        //Suppose TXT has only 1 posible image. This condition avoid redoing dictionary.
        //TODO. Dict reparison function
        NSMutableArray *containers = [self containers];
        
        NSMutableDictionary *spContainer = [containers firstObject];
        if(!spContainer){
            spContainer = @{JSON_DICT_CONT_PANORAMA_NAME:self.fileName}.mutableCopy;
            [containers addObject:spContainer];
        }
        
        NSMutableArray *images = [spContainer valueForKey:JSON_DICT_CONT_PANORAMA_IMAGES];
        if(!images){
            images = @[@{JSON_DICT_IMAGE_NAME:self.fileName}.mutableCopy].mutableCopy;
            [spContainer setValue:images forKey:JSON_DICT_CONT_PANORAMA_IMAGES];
        }
        
        IMCPanoramaWrapper *panWrap = [[IMCPanoramaWrapper alloc]init];
        panWrap.jsonDictionary = containers.firstObject;
        panWrap.parent = self;
        
        imageStack = [[IMCImageStack alloc]init];
        imageStack.parent = panWrap;
        imageStack.jsonDictionary = images.firstObject;
    }
    else
        imageStack = (IMCImageStack *)self.children.firstObject.children.firstObject;
    
    if([imageStack hasTIFFBackstore]){
        path = [imageStack backStoreTIFFPath];
        
    }
    NSData *data = [NSData dataWithContentsOfFile:path];
    NSError * error = nil;
    data = [NSData dataWithContentsOfFile:path options:0 error:&error];
    if(error)
        NSLog(@"Error ---- > %@ %@", error, error.userInfo);
    NSLog(@"%@",data);
    [self loadSingleFiler:imageStack data:data path:path success:success];
}

-(void)loadSingleFiler:(IMCImageStack *)imageStack data:(NSData *)data path:(NSString *)path success:(BOOL *)success{
    
    if([path.pathExtension isEqualToString:EXTENSION_TXT])
        *success = [IMC_TxtLoader loadTXTData:data toIMCImageStack:imageStack];
    
    if([path.pathExtension isEqualToString:EXTENSION_BIMC])
        *success = [IMC_BIMCLoader loadBIMCdata:data toIMCImageStack:imageStack];
    
    if([path.pathExtension isEqualToString:EXTENSION_TIFF]
       || [path.pathExtension isEqualToString:EXTENSION_TIF])
        *success = [IMC_TIFFLoader loadTIFFData:data toIMCImageStack:imageStack];
    
    if([path.pathExtension isEqualToString:EXTENSION_JPEG]
       || [path.pathExtension isEqualToString:EXTENSION_JPG]
       || [path.pathExtension isEqualToString:EXTENSION_BMP]
       || [path.pathExtension isEqualToString:EXTENSION_PNG])
        *success = [IMC_TIFFLoader loadNonTIFFData:data toIMCImageStack:imageStack];
    
    if([path.pathExtension isEqualToString:EXTENSION_M32])
        *success = [IMC_MatlabLoader loadMatDataETHZ:data toIMCImageStack:imageStack];

}

-(void)populateJsonDictForMCDImagesFile:(NSString *)path success:(BOOL *)success{
    //if (self.children.count != 1) {
    NSData *data = [NSData dataWithContentsOfFile:path];
    *success = [IMC_MCDLoader loadMCD:data toIMCFileWrapper:self];
    //}
}
-(void)softLoad{
    NSMutableArray *containers = [self containers];
    for (NSMutableDictionary *spContainer in containers) {
        NSMutableArray *images = [spContainer valueForKey:JSON_DICT_CONT_PANORAMA_IMAGES];
        
        IMCPanoramaWrapper *panWrap = [[IMCPanoramaWrapper alloc]init];
        panWrap.jsonDictionary = spContainer;
        panWrap.parent = self;
        
        for(id image in images){
            IMCImageStack * imageStack = [[IMCImageStack alloc]init];
            imageStack.parent = panWrap;
            imageStack.jsonDictionary = image;
        }
    }
    [self.jsonDictionary setValue:[NSNumber numberWithBool:YES] forKey:JSON_DICT_FILE_IS_SOFT_LOADED];
}

-(void)loadLayerDataWithBlock:(void (^)(void))block{
    
    if(![self canLoad])return;
    
    dispatch_queue_t aQ = dispatch_queue_create([IMCUtils randomStringOfLength:5].UTF8String, NULL);
    dispatch_async(aQ, ^{
        if([self isMemberOfClass:NSClassFromString(@"IMCPixelMap")]){
            [super loadLayerDataWithBlock:block];
            return;
        }
        NSString *path = [[self.pathMainDoc stringByDeletingLastPathComponent]stringByAppendingString:[self relativePath]];
        
        
        BOOL success = NO;
        if([path.pathExtension isEqualToString:EXTENSION_TXT]
           || [path.pathExtension isEqualToString:EXTENSION_BIMC]
           || [path.pathExtension isEqualToString:EXTENSION_TIFF]
           || [path.pathExtension isEqualToString:EXTENSION_TIF]
           || [path.pathExtension isEqualToString:EXTENSION_MAT]
           || [path.pathExtension isEqualToString:EXTENSION_JPG]
           || [path.pathExtension isEqualToString:EXTENSION_JPEG]
           || [path.pathExtension isEqualToString:EXTENSION_BMP]
           || [path.pathExtension isEqualToString:EXTENSION_PNG]){
            
            [self populateJsonDictForSingleImageFile:path success:&success];
        }
        if([path.pathExtension isEqualToString:EXTENSION_MCD]){
            [self populateJsonDictForMCDImagesFile:path success:&success];
        }
        if(!success)
            dispatch_async(dispatch_get_main_queue(), ^{
                [General runAlertModalWithMessage:@"Problem loading file"];
            });
        else
            [super loadLayerDataWithBlock:block];
    });
}
-(void)unLoadLayerDataWithBlock:(void (^)(void))block{
    self.isLoaded = NO;
    for (IMCPanoramaWrapper *wrap in self.children){
        wrap.isLoaded = NO;
        for (IMCImageStack *stck in self.children)
            [stck unLoadLayerDataWithBlock:nil];
    }
    [super unLoadLayerDataWithBlock:block];
}

@end
