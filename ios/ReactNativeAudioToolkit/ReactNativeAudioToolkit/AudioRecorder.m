//
//  AudioManager.m
//  ReactNativeAudioToolkit
//
//  Created by Oskar Vuola on 28/06/16.
//  Copyright (c) 2016 Futurice.
//
//  Licensed under the MIT license. For more information, see LICENSE.

#import "AudioRecorder.h"
#import "RCTEventDispatcher.h"
#import "SDAVAssetExportSession.h"
//#import "RCTEventEmitter"
#import "Helpers.h"

@import AVFoundation;

@interface AudioRecorder () <AVAudioRecorderDelegate>

@property (nonatomic, strong) NSMutableDictionary *recorderPool;
@property (nonatomic, strong) NSMutableDictionary *fileNames;
@property (nonatomic, strong) NSMutableDictionary *orgFileNames;
@end

@implementation AudioRecorder
NSNumber *lastRecID;
NSDictionary *recordSetting;
NSString * _Nullable orgFilePath;
NSString * _Nullable lastFilePath;
@synthesize bridge = _bridge;

- (void)dealloc {
    AVAudioSession *audioSession = [AVAudioSession sharedInstance];
    NSError *error = nil;
    [audioSession setActive:NO error:&error];

    if (error) {
        NSLog (@"RCTAudioRecorder: Could not deactivate current audio session. Error: %@", error);
        return;
    }
}
-(void)audioSessionInterruptionNotification:(NSNotification*)notification {
    NSString* seccReason = @"";
    //Check the type of notification, especially if you are sending multiple AVAudioSession events here
    NSLog(@"Interruption notification name %@", notification.name);
    NSError *err = noErr;
    if ([notification.name isEqualToString:AVAudioSessionInterruptionNotification]) {
        seccReason = @"Interruption notification received";

        //Check to see if it was a Begin interruption
        if ([[notification.userInfo valueForKey:AVAudioSessionInterruptionTypeKey] isEqualToNumber:[NSNumber numberWithInt:AVAudioSessionInterruptionTypeBegan]]) {
            seccReason = @"Interruption began";
            NSLog(@"Interruption notification name %@ audio pause", notification.name);

            dispatch_time_t restartTime = dispatch_time(DISPATCH_TIME_NOW,
                                                        0.01 * NSEC_PER_SEC);
            dispatch_after(restartTime, dispatch_get_global_queue(0, 0), ^{
                AVAudioRecorder *recorder = [[self recorderPool] objectForKey:lastRecID];
                if (recorder) {
                    if(recorder.isRecording) {
                        [recorder stop];
                        NSLog(@"Interruption notification name Pauseing recording %@", lastRecID);
                    } else {
                        NSLog(@"Interruption notification name Already Paused %@", lastRecID);
                    }
                }else {
                    NSLog(@"Interruption notification name recording %@ not found", lastRecID);
                }
                  NSLog(@"Interruption notification Pauseing recording status %d",recorder.isRecording);
            });

        } else if([[notification.userInfo valueForKey:AVAudioSessionInterruptionTypeKey] isEqualToNumber:[NSNumber numberWithInt:AVAudioSessionInterruptionTypeEnded]]){
            seccReason = @"Interruption ended!";
             NSLog(@"Interruption notification name %@ audio resume", notification.name);
            //Start New Recording
            dispatch_time_t restartTime = dispatch_time(DISPATCH_TIME_NOW,
                                                        0.1 * NSEC_PER_SEC);
            dispatch_after(restartTime, dispatch_get_global_queue(0, 0), ^{
                AVAudioRecorder *recorder = [[self recorderPool] objectForKey:lastRecID];
                NSLog(@"Interruption notification Resumeing recording status %d",recorder.isRecording);
                if (recorder) {
                    if(!recorder.isRecording) {
                        NSString *filePath = [[self orgFileNames] objectForKey:lastRecID];
                        NSArray * fileNames =[[self fileNames] objectForKey:lastRecID];
                        NSString *tmpFileName = [self gnrTempFileName:filePath AndNumber:fileNames.count];
                        [[[self fileNames] objectForKey:lastRecID] addObject:tmpFileName];
                        NSURL *url = [NSURL fileURLWithPath:tmpFileName];
                        NSError *error = nil;
                        recorder = [[AVAudioRecorder alloc] initWithURL:url settings:recordSetting error:&error];
                        if (![recorder record]) {
                            NSLog(@"Interruption notification Error Resumeing recording");
                            return;
                        }
                        [[self recorderPool] setObject:recorder forKey:lastRecID];
                        NSLog(@"Interruption notification nameResumeing recording %@",lastRecID);
                    }else {
                         NSLog(@"Interruption notification Already Recording %d",recorder.isRecording);
                    }
                }else {
                    NSLog(@"Interruption notification name recording %@ not found",lastRecID);
                }
            });
        }
    }
}

- (NSMutableDictionary *) recorderPool {
    if (!_recorderPool) {
        _recorderPool = [NSMutableDictionary new];
    }
    return _recorderPool;
}

- (NSMutableDictionary *) fileNames {
    if (!_fileNames) {
        _fileNames = [NSMutableDictionary new];
    }
    return _fileNames;
}
- (NSMutableDictionary *) orgFileNames {
    if (!_orgFileNames) {
        _orgFileNames = [NSMutableDictionary new];
    }
    return _orgFileNames;
}

-(NSNumber *) keyForRecorder:(nonnull AVAudioRecorder*)recorder {
    return [[_recorderPool allKeysForObject:recorder] firstObject];
}


-(NSString *) gnrTempFileName:(NSString*)fullFileName AndNumber:(NSUInteger)number {
    //split
    NSString * pathExt = [fullFileName pathExtension];
    return [NSString stringWithFormat:@"%@.%lu.%@",fullFileName,number,pathExt];
}


#pragma mark - React exposed functions

RCT_EXPORT_MODULE();


RCT_EXPORT_METHOD(prepare:(nonnull NSNumber *)recorderId
                  withPath:(NSString * _Nullable)filename
                  withOptions:(NSDictionary *)options
                  withCallback:(RCTResponseSenderBlock)callback)
{
    if ([filename length] == 0) {
        NSDictionary* dict = [Helpers errObjWithCode:@"invalidpath"
                                         withMessage:@"Provided path was empty"];
        callback(@[dict]);
        return;
    } else if ([[self recorderPool] objectForKey:recorderId]) {
        NSDictionary* dict = [Helpers errObjWithCode:@"invalidpath"
                                         withMessage:@"Recorder with that id already exists"];
        callback(@[dict]);
        return;
    }

    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *documentsDirectory = [paths objectAtIndex:0];
    NSString *filePath = [documentsDirectory stringByAppendingPathComponent:filename];

    // Initialize audio session
    AVAudioSession *audioSession = [AVAudioSession sharedInstance];
    NSError *error = nil;
    [audioSession setCategory:AVAudioSessionCategoryPlayAndRecord withOptions:AVAudioSessionCategoryOptionMixWithOthers error:&error];
    if (error) {
        NSDictionary* dict = [Helpers errObjWithCode:@"preparefail" withMessage:@"Failed to set audio session category"];
        callback(@[dict]);

        return;
    }

    // Set audio session active
    [audioSession setActive:YES error:&error];
    if (error) {
        NSString *errMsg = [NSString stringWithFormat:@"Could not set audio session active, error: %@", error];
        NSDictionary* dict = [Helpers errObjWithCode:@"preparefail"
                                         withMessage:errMsg];
        callback(@[dict]);

        return;
    }
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(audioSessionInterruptionNotification:)
                                                 name:AVAudioSessionInterruptionNotification
                                               object:audioSession];

    // Settings for the recorder
    recordSetting = [Helpers recorderSettingsFromOptions:options];

    [[self orgFileNames] setObject:filePath forKey:recorderId];
    //create temp file name
    NSMutableArray * fileNames = [NSMutableArray new];
    NSString *tmpFileName = [self gnrTempFileName:filePath AndNumber:fileNames.count];
    [fileNames addObject:tmpFileName];
    [[self fileNames] setObject:fileNames forKey:recorderId];

    NSURL *url = [NSURL fileURLWithPath:tmpFileName];
    // Initialize a new recorder
    AVAudioRecorder *recorder = [[AVAudioRecorder alloc] initWithURL:url settings:recordSetting error:&error];
    if (error) {
        NSString *errMsg = [NSString stringWithFormat:@"Failed to initialize recorder, error: %@", error];
        NSDictionary* dict = [Helpers errObjWithCode:@"preparefail"
                                         withMessage:errMsg];
        callback(@[dict]);
        return;

    } else if (!recorder) {
        NSDictionary* dict = [Helpers errObjWithCode:@"preparefail" withMessage:@"Failed to initialize recorder"];
        callback(@[dict]);

        return;
    }
    recorder.delegate = self;
    [[self recorderPool] setObject:recorder forKey:recorderId];
    lastRecID = recorderId;
    BOOL success = [recorder prepareToRecord];
    if (!success) {
        [self destroyRecorderWithId:recorderId];
        NSDictionary* dict = [Helpers errObjWithCode:@"preparefail" withMessage:@"Failed to prepare recorder. Settings\
                              are probably wrong."];
        callback(@[dict]);
        return;
    }

    callback(@[[NSNull null], filePath]);
}

RCT_EXPORT_METHOD(record:(nonnull NSNumber *)recorderId withCallback:(RCTResponseSenderBlock)callback) {
    AVAudioRecorder *recorder = [[self recorderPool] objectForKey:recorderId];
    if (recorder) {
        if (![recorder record]) {
            NSDictionary* dict = [Helpers errObjWithCode:@"startfail" withMessage:@"Failed to start recorder"];
            callback(@[dict]);
            return;
        }else {

        }
    } else {
        NSDictionary* dict = [Helpers errObjWithCode:@"notfound" withMessage:@"Recorder with that id was not found"];
        callback(@[dict]);
        return;
    }
    callback(@[[NSNull null]]);
}

RCT_EXPORT_METHOD(stop:(nonnull NSNumber *)recorderId withCallback:(RCTResponseSenderBlock)callback) {
    AVAudioRecorder *recorder = [[self recorderPool] objectForKey:recorderId];
    if (recorder) {
        [recorder stop];
    } else {
        NSDictionary* dict = [Helpers errObjWithCode:@"notfound" withMessage:@"Recorder with that id was not found"];
        callback(@[dict]);
        return;
    }
    [self mergeAudioFiles:recorderId];
    callback(@[[NSNull null]]);
}


-(void)mergeAudioFiles:(nonnull NSNumber *)recorderId
{
    NSFileManager * fm = [[NSFileManager alloc] init];
    NSError * error;
    NSArray * filesNames = [[self fileNames] objectForKey:recorderId];
    NSString * filePath = [[self orgFileNames] objectForKey:recorderId];
    NSString * pathToSave =[NSString stringWithFormat:@"%@%@",filePath,@".m4a"];
   //if only one file name - copy result
    if(filesNames.count==1) {
        BOOL result = [fm moveItemAtPath:[filesNames objectAtIndex:0] toPath:filePath error:&error];
        if(!result) {
            NSLog(@"Error: %@", error);
        }
        return;
    }
    CMTime startTime = kCMTimeZero;
    AVMutableComposition *composition = [AVMutableComposition composition];
    AVMutableCompositionTrack *compositionAudioTrack =[AVMutableCompositionTrack alloc];
    compositionAudioTrack = [composition addMutableTrackWithMediaType:AVMediaTypeAudio preferredTrackID:kCMPersistentTrackID_Invalid];

    float audioEndTime=0;
    for (NSString *fileName in filesNames) {
        NSURL *audioUrl = [NSURL fileURLWithPath:fileName];
        AVURLAsset *audioasset = [[AVURLAsset alloc]initWithURL:audioUrl options:nil];
        CMTimeRange timeRange  = CMTimeRangeMake(kCMTimeZero, audioasset.duration);
        AVAssetTrack *audioAssetTrack= [[audioasset tracksWithMediaType:AVMediaTypeAudio] lastObject];
        [compositionAudioTrack insertTimeRange:timeRange ofTrack:audioAssetTrack atTime:startTime error:&error];
        startTime = CMTimeAdd(startTime, timeRange.duration);
        CMTime assetTime2 = [audioasset duration];
        Float64 duration2 = CMTimeGetSeconds(assetTime2);
        audioEndTime+=duration2;
//        CMTime creditsDuration = CMTimeMakeWithSeconds(5, 600);
//        CMTimeRange creditsRange = CMTimeRangeMake([[compositionAudioTrack asset] duration], creditsDuration);
//        [compositionAudioTrack insertEmptyTimeRange:creditsRange];
//        audioEndTime+=CMTimeGetSeconds(creditsDuration);
    }





    NSURL *exportUrl = [NSURL fileURLWithPath:pathToSave];

    float audioStartTime=0;
    CMTime startTime1 = CMTimeMake((int)(floor(audioStartTime * 100)), 100);
    CMTime stopTime = CMTimeMake((int)(ceil(audioEndTime * 100)), 100);
    CMTimeRange exportTimeRange = CMTimeRangeFromTimeToTime(startTime1, stopTime);


    SDAVAssetExportSession *encoder = [SDAVAssetExportSession.alloc initWithAsset:composition];
    encoder.outputFileType = AVFileTypeAppleM4A;
    encoder.outputURL = exportUrl;
    encoder.audioSettings = @
    {
    AVFormatIDKey: @(kAudioFormatMPEG4AAC),
    AVNumberOfChannelsKey: @2,
    AVSampleRateKey: @44100,
    AVEncoderBitRateKey: @128000,
    };
    encoder.timeRange = exportTimeRange;
    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
    NSLog(@"Starting Audio Marge");
    [encoder exportAsynchronouslyWithCompletionHandler:^
    {
        if (encoder.status == AVAssetExportSessionStatusCompleted)
        {
            [NSThread sleepForTimeInterval: 0.2];
            NSLog(@"Audio Marge succeeded");
            NSError * err = NULL;
//          BOOL result = [fm moveItemAtPath:lastFilePath toPath:[NSString stringWithFormat:@"%@%@",lastFilePath,@".p1"] error:&err];
            BOOL result = [fm moveItemAtPath:pathToSave toPath:filePath error:&err];
            if(!result) {
                NSLog(@"Error: %@", err);
            }
            NSLog(@"Audio Copied");
        }
        else if (encoder.status == AVAssetExportSessionStatusCancelled)
        {
            NSLog(@"Audio export cancelled");
        }
        else
        {
            NSLog(@"Audio export failed with error: %@ (%ld)", encoder.error.localizedDescription, encoder.error.code);
        }
         dispatch_semaphore_signal(semaphore);
    }];
    NSLog(@"Audio Wait to Finish");
    dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
    //cleanup
    for (NSString *fileName in filesNames) {
        [fm removeItemAtPath:fileName error:&error];
    }
    NSLog(@"Audio Marge Finished");
}

RCT_EXPORT_METHOD(pause:(nonnull NSNumber *)recorderId withCallback:(RCTResponseSenderBlock)callback) {
    AVAudioRecorder *recorder = [[self recorderPool] objectForKey:recorderId];
    if (recorder) {
        [recorder pause];
    } else {
        NSDictionary* dict = [Helpers errObjWithCode:@"notfound" withMessage:@"Recorder with that id was not found"];
        callback(@[dict]);
        return;
    }
    callback(@[[NSNull null]]);
}

RCT_EXPORT_METHOD(destroy:(nonnull NSNumber *)recorderId withCallback:(RCTResponseSenderBlock)callback) {
    [self destroyRecorderWithId:recorderId];
    callback(@[[NSNull null]]);
}

#pragma mark - Delegate methods
- (void)audioRecorderDidFinishRecording:(AVAudioRecorder *) aRecorder successfully:(BOOL)flag {
    if ([[_recorderPool allValues] containsObject:aRecorder]) {
        NSNumber *recordId = [self keyForRecorder:aRecorder];
        [self destroyRecorderWithId:recordId];
    }
}

- (void)destroyRecorderWithId:(NSNumber *)recorderId {
    if ([[[self recorderPool] allKeys] containsObject:recorderId]) {
        AVAudioRecorder *recorder = [[self recorderPool] objectForKey:recorderId];
        if (recorder) {
            [recorder stop];
            [[self recorderPool] removeObjectForKey:recorderId];
            NSString *eventName = [NSString stringWithFormat:@"RCTAudioRecorderEvent:%@", recorderId];
            [self.bridge.eventDispatcher sendAppEventWithName:eventName
                                                         body:@{@"event" : @"ended",
                                                                @"data" : [NSNull null]
                                                                }];
        }
    }
}

- (void)audioRecorderEncodeErrorDidOccur:(AVAudioRecorder *)recorder
                                   error:(NSError *)error {
    NSNumber *recordId = [self keyForRecorder:recorder];

    [self destroyRecorderWithId:recordId];
    NSString *eventName = [NSString stringWithFormat:@"RCTAudioRecorderEvent:%@", recordId];
    [self.bridge.eventDispatcher sendAppEventWithName:eventName
                                               body:@{@"event": @"error",
                                                      @"data" : [error description]
                                                      }];
}

@end
